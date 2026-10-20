import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/song.dart';

class StatisticsService extends ChangeNotifier {
  StatisticsService._();

  static final StatisticsService instance = StatisticsService._();

  static const String _fileName = 'statistics.decibex';
  static const Duration _countThreshold = Duration(seconds: 5);

  File? _file;
  Map<String, int> _playCounts = {};
  bool _loaded = false;

  /// Canción actualmente siendo escuchada (para contar 5s).
  Song? _trackedSong;
  Duration _trackedPosition = Duration.zero;
  bool _countedForCurrentTrack = false;

  Map<String, int> get playCounts => Map.unmodifiable(_playCounts);

  Future<void> init() async {
    if (_loaded) return;
    await _resolveFile();
    await _load();
    _loaded = true;
  }

  Future<void> _resolveFile() async {
    // En Android, getApplicationDocumentsDirectory() apunta a
    // /storage/emulated/0/Android/data/<package>/files/
    final dir = await getApplicationDocumentsDirectory();
    _file = File('${dir.path}/$_fileName');
    debugPrint('[StatisticsService] Archivo de estadísticas: ${_file!.path}');
  }

  Future<void> _load() async {
    final file = _file;
    if (file == null) return;

    try {
      if (!await file.exists()) {
        _playCounts = {};
        return;
      }

      final content = await file.readAsString();
      if (content.trim().isEmpty) {
        _playCounts = {};
        return;
      }

      final decoded = jsonDecode(content);
      if (decoded is Map<String, dynamic>) {
        _playCounts = decoded.map(
          (key, value) => MapEntry(key, (value as num).toInt()),
        );
      } else if (decoded is Map) {
        _playCounts = decoded.map(
          (key, value) => MapEntry(key.toString(), (value as num).toInt()),
        );
      } else {
        _playCounts = {};
      }

      debugPrint('[StatisticsService] Cargadas ${_playCounts.length} entradas');
      notifyListeners();
    } catch (error) {
      debugPrint('[StatisticsService] Error al cargar estadísticas: $error');
      _playCounts = {};
    }
  }

  Future<void> _save() async {
    final file = _file;
    if (file == null) return;

    try {
      await file.parent.create(recursive: true);
      final json = jsonEncode(_playCounts);
      await file.writeAsString(json, flush: true);
    } catch (error) {
      debugPrint('[StatisticsService] Error al guardar estadísticas: $error');
    }
  }

  /// Clave única de la canción. Usa la ruta normalizada si existe;
  /// si no, título + artista en minúsculas.
  String _songKey(Song song) {
    final path = song.filePath?.trim();
    if (path != null && path.isNotEmpty) {
      return path.replaceAll('\\', '/');
    }
    return '${song.title.trim().toLowerCase()}::${song.artist.trim().toLowerCase()}';
  }

  int getPlayCount(Song song) => _playCounts[_songKey(song)] ?? 0;

  /// Llamado por PlaybackService cuando cambia la canción actual.
  void onSongChanged(Song? song) {
    _trackedSong = song;
    _trackedPosition = Duration.zero;
    _countedForCurrentTrack = false;
  }

  /// Llamado por PlaybackService cuando cambia la posición de reproducción.
  void onPositionChanged(Duration position) {
    final song = _trackedSong;
    if (song == null || _countedForCurrentTrack) return;

    _trackedPosition = position;

    if (position >= _countThreshold) {
      _countedForCurrentTrack = true;
      unawaited(_increment(song));
    }
  }

  /// Reset si se reinicia la pista (seek a 0, nueva canción, etc.).
  void onSeek(Duration position) {
    if (position < _countThreshold) {
      _countedForCurrentTrack = false;
    }
    _trackedPosition = position;
  }

  Future<void> _increment(Song song) async {
    final key = _songKey(song);
    _playCounts[key] = (_playCounts[key] ?? 0) + 1;
    debugPrint(
      '[StatisticsService] Reproducción contada: ${song.title} '
      '(total: ${_playCounts[key]})',
    );
    notifyListeners();
    await _save();
  }

  Future<void> reset() async {
    _playCounts = {};
    notifyListeners();
    await _save();
  }
}
