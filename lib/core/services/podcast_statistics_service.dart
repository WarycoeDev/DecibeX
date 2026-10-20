import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/song.dart';

/// Datos guardados por episodio de podcast.
class PodcastEpisodeStats {
  final bool completed;
  final Duration lastPosition;
  final Duration duration;
  final int plays;
  final DateTime? lastPlayedAt;

  const PodcastEpisodeStats({
    this.completed = false,
    this.lastPosition = Duration.zero,
    this.duration = Duration.zero,
    this.plays = 0,
    this.lastPlayedAt,
  });

  PodcastEpisodeStats copyWith({
    bool? completed,
    Duration? lastPosition,
    Duration? duration,
    int? plays,
    DateTime? lastPlayedAt,
  }) {
    return PodcastEpisodeStats(
      completed: completed ?? this.completed,
      lastPosition: lastPosition ?? this.lastPosition,
      duration: duration ?? this.duration,
      plays: plays ?? this.plays,
      lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'completed': completed,
    'lastPositionMs': lastPosition.inMilliseconds,
    'durationMs': duration.inMilliseconds,
    'plays': plays,
    'lastPlayedAt': lastPlayedAt?.toIso8601String(),
  };

  factory PodcastEpisodeStats.fromJson(Map<String, dynamic> json) {
    final playedAtRaw = json['lastPlayedAt'];
    return PodcastEpisodeStats(
      completed: json['completed'] == true,
      lastPosition: Duration(
        milliseconds: (json['lastPositionMs'] as num?)?.toInt() ?? 0,
      ),
      duration: Duration(
        milliseconds: (json['durationMs'] as num?)?.toInt() ?? 0,
      ),
      plays: (json['plays'] as num?)?.toInt() ?? 0,
      lastPlayedAt: playedAtRaw is String
          ? DateTime.tryParse(playedAtRaw)
          : null,
    );
  }
}

class PodcastStatisticsService extends ChangeNotifier {
  PodcastStatisticsService._();

  static final PodcastStatisticsService instance = PodcastStatisticsService._();

  static const String _fileName = 'podcast_statistics.decibex';

  /// Umbral de "casi terminado": 95 % de la duración → completed.
  static const double _completionRatio = 0.95;

  /// Frecuencia con la que guardamos la posición mientras suena.
  static const Duration _saveInterval = Duration(seconds: 5);

  File? _file;
  Map<String, PodcastEpisodeStats> _stats = {};
  bool _loaded = false;

  Timer? _saveTimer;
  Timer? _flushTimer;

  /// Episodio actualmente en seguimiento (solo podcasts).
  Song? _trackedEpisode;
  Duration _trackedPosition = Duration.zero;
  Duration _trackedDuration = Duration.zero;
  bool _trackedCompletedThisSession = false;

  Future<void> init() async {
    if (_loaded) return;
    await _resolveFile();
    await _load();
    _loaded = true;
  }

  Future<void> _resolveFile() async {
    final dir = await getApplicationDocumentsDirectory();
    _file = File('${dir.path}/$_fileName');
    debugPrint('[PodcastStats] Archivo: ${_file!.path}');
  }

  Future<void> _load() async {
    final file = _file;
    if (file == null) return;

    try {
      if (!await file.exists()) {
        _stats = {};
        return;
      }
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) {
        _stats = {};
        return;
      }
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        _stats = decoded.map(
          (key, value) => MapEntry(
            key,
            PodcastEpisodeStats.fromJson(value as Map<String, dynamic>),
          ),
        );
      }
      debugPrint('[PodcastStats] Cargados ${_stats.length} episodios');
      notifyListeners();
    } catch (error) {
      debugPrint('[PodcastStats] Error al cargar: $error');
      _stats = {};
    }
  }

  Future<void> _save() async {
    final file = _file;
    if (file == null) return;
    try {
      await file.parent.create(recursive: true);
      final payload = <String, dynamic>{
        for (final entry in _stats.entries) entry.key: entry.value.toJson(),
      };
      await file.writeAsString(jsonEncode(payload), flush: true);
    } catch (error) {
      debugPrint('[PodcastStats] Error al guardar: $error');
    }
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveInterval, () {
      unawaited(_save());
    });
  }

  /// Clave estable para un episodio. Usa la ruta normalizada; si no hay,
  /// título + artista en minúsculas.
  String _keyFor(Song song) {
    final path = song.filePath?.trim();
    if (path != null && path.isNotEmpty) {
      return path.replaceAll('\\', '/');
    }
    return '${song.title.trim().toLowerCase()}::${song.artist.trim().toLowerCase()}';
  }

  PodcastEpisodeStats? statsFor(Song song) => _stats[_keyFor(song)];

  bool isCompleted(Song song) => _stats[_keyFor(song)]?.completed ?? false;

  Duration resumePositionFor(Song song) {
    final s = _stats[_keyFor(song)];
    if (s == null) return Duration.zero;
    // Si ya está terminado, reanudar desde el inicio.
    if (s.completed) return Duration.zero;
    return s.lastPosition;
  }

  // ---------- API que consume PlaybackService ----------

  /// Llamado cuando la canción actual cambia. Solo se activa para podcasts.
  void onSongChanged(Song? song, {Duration duration = Duration.zero}) {
    // Guardar el episodio anterior antes de cambiar.
    _persistCurrent(force: true);

    _trackedEpisode = (song != null && song.isPodcast) ? song : null;
    _trackedPosition = Duration.zero;
    _trackedDuration = duration;
    _trackedCompletedThisSession = false;

    if (_trackedEpisode != null) {
      final existing = _stats[_keyFor(_trackedEpisode!)];
      _stats[_keyFor(
        _trackedEpisode!,
      )] = (existing ?? const PodcastEpisodeStats()).copyWith(
        plays: (existing?.plays ?? 0) + 1,
        lastPlayedAt: DateTime.now(),
        duration: duration > Duration.zero
            ? duration
            : (existing?.duration ?? Duration.zero),
      );
      notifyListeners();
      unawaited(_save());
    }

    _startFlushTimer();
  }

  /// Llamado desde `positionStream`.
  void onPositionChanged(Duration position) {
    final episode = _trackedEpisode;
    if (episode == null) return;

    _trackedPosition = position;

    // Si llegó al 95 % y aún no estaba marcado, marcar completed.
    if (!_trackedCompletedThisSession &&
        _trackedDuration > Duration.zero &&
        position.inMilliseconds >=
            _trackedDuration.inMilliseconds * _completionRatio) {
      _trackedCompletedThisSession = true;
      _markCompleted(episode);
    }

    _scheduleSave();
  }

  /// Llamado desde `durationStream`.
  void onDurationChanged(Duration duration) {
    _trackedDuration = duration;
    final episode = _trackedEpisode;
    if (episode == null) return;

    final current = _stats[_keyFor(episode)];
    _stats[_keyFor(episode)] = (current ?? const PodcastEpisodeStats())
        .copyWith(duration: duration);

    _scheduleSave();
  }

  /// Llamado cuando la pista termina (`ProcessingState.completed`).
  void onTrackCompleted() {
    final episode = _trackedEpisode;
    if (episode == null) return;
    _markCompleted(episode);
    _persistCurrent(force: true);
  }

  /// Llamado desde `seek` para mantener la posición persistida coherente.
  void onSeek(Duration position) {
    final episode = _trackedEpisode;
    if (episode == null) return;
    _trackedPosition = position;
    if (position < _trackedDuration * _completionRatio) {
      _trackedCompletedThisSession = false;
    }
    _scheduleSave();
  }

  /// Llamado desde `pause`, `stop`, `dispose` o al cerrar el player.
  Future<void> flush() async {
    _persistCurrent(force: true);
    await _save();
  }

  // ---------- internos ----------

  void _startFlushTimer() {
    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _persistCurrent(force: false);
    });
  }

  void _persistCurrent({required bool force}) {
    final episode = _trackedEpisode;
    if (episode == null) return;

    final key = _keyFor(episode);
    final existing = _stats[key] ?? const PodcastEpisodeStats();

    // Si aún no hay duración conocida, no guardamos posición 0 como “avance”.
    final duration = _trackedDuration > Duration.zero
        ? _trackedDuration
        : existing.duration;

    final position = _trackedPosition;

    // No sobrescribir completed con una posición inicial.
    final completed = existing.completed || _trackedCompletedThisSession;

    _stats[key] = existing.copyWith(
      completed: completed,
      lastPosition: position,
      duration: duration,
    );

    if (force)
      unawaited(_save());
    else
      _scheduleSave();
  }

  void _markCompleted(Song episode) {
    final key = _keyFor(episode);
    final existing = _stats[key] ?? const PodcastEpisodeStats();
    _stats[key] = existing.copyWith(
      completed: true,
      lastPosition: existing.duration > Duration.zero
          ? existing.duration
          : _trackedDuration,
      duration: _trackedDuration > Duration.zero
          ? _trackedDuration
          : existing.duration,
    );
    notifyListeners();
    unawaited(_save());
  }

  Future<void> clear() async {
    _stats = {};
    notifyListeners();
    await _save();
  }

  @override
  void dispose() {
    _flushTimer?.cancel();
    _saveTimer?.cancel();
    unawaited(flush());
    super.dispose();
  }
}
