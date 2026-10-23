import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../models/song.dart';
import 'fade_index.dart';
import 'playback_queue.dart';
import 'settings_service.dart';
import 'statistics_service.dart';
import 'podcast_statistics_service.dart';

class PlaybackService extends ChangeNotifier {
  PlaybackService._() {
    _player.playerStateStream.listen((state) {
      _isPlaying = state.playing;

      if (state.processingState != ProcessingState.completed) {
        _completionHandled = false;
      } else if (!_completionHandled) {
        _completionHandled = true;
        unawaited(_handleTrackCompleted());
      }

      if (!_isPlaying && _seekTarget != null) {
        _seekStartedAt = null;
      }

      _syncFadeTimer();
      notifyListeners();
    });

    _player.positionStream.listen((value) {
      final target = _seekTarget;

      if (target != null) {
        final isCloseToTarget =
            (value.inMilliseconds - target.inMilliseconds).abs() <= 1000;

        if (_isPlaying) {
          final startedAt = _seekStartedAt;
          final isRecent =
              startedAt != null &&
              DateTime.now().difference(startedAt) <
                  const Duration(milliseconds: 1500);

          if (isCloseToTarget) {
            _seekTarget = null;
          } else if (isRecent) {
            return;
          } else {
            _seekTarget = null;
          }
        } else if (!isCloseToTarget) {
          return;
        }
      }

      _position = value;

      StatisticsService.instance.onPositionChanged(value);
      PodcastStatisticsService.instance.onPositionChanged(value);

      notifyListeners();
    });

    _player.durationStream.listen((value) {
      _duration = value ?? Duration.zero;
      PodcastStatisticsService.instance.onDurationChanged(_duration);
      notifyListeners();
    });

    _player.sequenceStateStream.listen((sequenceState) {
      final taggedSong = sequenceState.currentSource?.tag;

      if (taggedSong is Song) {
        final changed =
            _currentSong == null || !_sameSong(_currentSong!, taggedSong);

        _currentSong = taggedSong;
        _currentQueueIndex = _indexOfSong(_playingSongs, taggedSong);

        if (changed) {
          _position = Duration.zero;
          _seekTarget = null;
          _seekStartedAt = null;

          StatisticsService.instance.onSongChanged(taggedSong);
          PodcastStatisticsService.instance.onSongChanged(taggedSong);
        }
      }

      notifyListeners();
    });

    _player.errorStream.listen((error) {
      debugPrint('[PlaybackService] Error de audio: $error');
    });

    // Cambios de preamp / ReplayGain / fades se aplican a la pista actual
    // al instante (sin esperar a la siguiente canción).
    SettingsService.instance.addListener(_onSettingsChanged);
  }

  static final PlaybackService instance = PlaybackService._();

  final AudioPlayer _player = AudioPlayer();
  final Random _random = Random();

  List<Song> _playingSongs = [];
  List<Song> _shuffleOrder = [];

  Song? _currentSong;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  bool _isPlaying = false;
  bool _isLoading = false;
  bool _shuffleEnabled = false;
  bool _completionHandled = false;
  bool _handlingCompletion = false;

  int _currentQueueIndex = -1;
  int _shuffleCursor = -1;

  LoopMode _repeatMode = LoopMode.off;

  Duration? _seekTarget;
  DateTime? _seekStartedAt;

  // --- Volumen / fades ---

  /// Último volumen enviado al reproductor (-1 = desconocido).
  double _lastAppliedVolume = -1;

  /// Frecuencia con la que se reevalúa el volumen mientras suena la pista.
  static const Duration _fadeTick = Duration(milliseconds: 40);
  Timer? _fadeTimer;

  /// Índice "posición → ganancia" y la clave (fadeIn ms, fadeOut ms,
  /// duración ms) con la que se construyó.
  FadeIndex? _fadeIndex;
  (int, int, int)? _fadeIndexKey;

  Song? get currentSong => _currentSong;
  Duration get position => _position;
  Duration get duration => _duration;
  bool get isPlaying => _isPlaying;
  bool get isLoading => _isLoading;
  bool get shuffleEnabled => _shuffleEnabled;
  LoopMode get repeatMode => _repeatMode;
  ProcessingState get processingState => _player.processingState;
  Duration get bufferedPosition => _player.bufferedPosition;
  double get speed => _player.speed;
  List<Song> get playingSongs => List.unmodifiable(_playingSongs);

  int? get currentIndex => _currentQueueIndex >= 0 ? _currentQueueIndex : null;

  bool get canPlayPrevious {
    if (_isLoading || _playingSongs.isEmpty || _currentSong == null) {
      return false;
    }

    if (_position > const Duration(seconds: 3)) {
      return true;
    }

    if (_shuffleEnabled) {
      return _shuffleCursor > 0 ||
          (_repeatMode == LoopMode.all && _playingSongs.length > 1);
    }

    return _currentQueueIndex > 0 ||
        (_repeatMode == LoopMode.all && _playingSongs.length > 1);
  }

  bool get canPlayNext {
    if (_isLoading || _playingSongs.isEmpty || _currentSong == null) {
      return false;
    }

    if (_shuffleEnabled) {
      return _shuffleCursor >= 0 &&
          (_shuffleCursor < _shuffleOrder.length - 1 ||
              (_repeatMode == LoopMode.all && _playingSongs.length > 1));
    }

    return _currentQueueIndex >= 0 &&
        (_currentQueueIndex < _playingSongs.length - 1 ||
            (_repeatMode == LoopMode.all && _playingSongs.length > 1));
  }

  void _onSettingsChanged() {
    _syncFadeTimer();

    if (_currentSong == null) return;
    unawaited(_applyVolume());
  }

  bool _sameSong(Song a, Song b) {
    final pathA = a.filePath?.trim();
    final pathB = b.filePath?.trim();

    if (pathA != null &&
        pathA.isNotEmpty &&
        pathB != null &&
        pathB.isNotEmpty) {
      return pathA.replaceAll('\\', '/') == pathB.replaceAll('\\', '/');
    }

    return a.title.trim().toLowerCase() == b.title.trim().toLowerCase() &&
        a.artist.trim().toLowerCase() == b.artist.trim().toLowerCase();
  }

  int _indexOfSong(List<Song> songs, Song song) {
    return songs.indexWhere((item) => _sameSong(item, song));
  }

  Song? _songAt(int index) {
    if (index < 0 || index >= _playingSongs.length) {
      return null;
    }

    return _playingSongs[index];
  }

  void _buildShuffleOrder({Song? keepCurrentFirst}) {
    _shuffleOrder = List<Song>.from(_playingSongs);

    if (_shuffleOrder.length > 1) {
      for (var i = _shuffleOrder.length - 1; i > 0; i--) {
        final j = _random.nextInt(i + 1);
        final temp = _shuffleOrder[i];
        _shuffleOrder[i] = _shuffleOrder[j];
        _shuffleOrder[j] = temp;
      }
    }

    if (keepCurrentFirst != null) {
      final currentIndex = _indexOfSong(_shuffleOrder, keepCurrentFirst);

      if (currentIndex > 0) {
        final current = _shuffleOrder.removeAt(currentIndex);
        _shuffleOrder.insert(0, current);
      }
    }

    _shuffleCursor = _currentSong == null
        ? -1
        : _indexOfSong(_shuffleOrder, _currentSong!);
  }

  Future<void> toggleShuffle() => setShuffle(!_shuffleEnabled);

  Future<void> setShuffle(bool enabled) async {
    if (_shuffleEnabled == enabled) return;

    _shuffleEnabled = enabled;

    if (enabled) {
      _buildShuffleOrder(keepCurrentFirst: _currentSong);
    } else {
      _shuffleOrder = [];
      _shuffleCursor = -1;
    }

    debugPrint(
      '[PlaybackService] Aleatorio ${enabled ? "activado" : "desactivado"}',
    );

    notifyListeners();
  }

  Future<void> setRepeatMode(LoopMode mode) async {
    if (_repeatMode == mode) return;

    _repeatMode = mode;

    final label = switch (mode) {
      LoopMode.one => 'repetir canción',
      LoopMode.all => 'repetir cola',
      LoopMode.off => 'desactivado',
    };

    debugPrint('[PlaybackService] Repetición: $label');
    notifyListeners();
  }

  Future<void> cycleRepeatMode() {
    final nextMode = switch (_repeatMode) {
      LoopMode.off => LoopMode.one,
      LoopMode.one => LoopMode.all,
      LoopMode.all => LoopMode.off,
    };

    return setRepeatMode(nextMode);
  }

  Future<void> playQueue() async {
    final queue = PlaybackQueue.instance.songs;

    if (queue.isEmpty) {
      await stop();
      return;
    }

    final availableSongs = <Song>[];

    for (final song in queue) {
      final path = song.filePath;

      if (path == null || path.isEmpty || !await File(path).exists()) {
        debugPrint('[PlaybackService] Archivo no disponible: ${song.title}');
        continue;
      }

      availableSongs.add(song);
    }

    if (availableSongs.isEmpty) {
      debugPrint('[PlaybackService] No hay archivos reproducibles en la cola.');
      await stop();
      return;
    }

    _playingSongs = availableSongs;
    _currentSong = null;
    _currentQueueIndex = -1;
    _shuffleOrder = [];
    _shuffleCursor = -1;
    _position = Duration.zero;
    _duration = Duration.zero;
    _seekTarget = null;
    _seekStartedAt = null;

    if (_shuffleEnabled) {
      _buildShuffleOrder();
    }

    final firstSong = _shuffleEnabled
        ? _shuffleOrder.first
        : availableSongs.first;

    _isLoading = true;
    notifyListeners();

    try {
      await _loadAndPlaySong(firstSong);

      debugPrint(
        '[PlaybackService] Reproduciendo cola: ${availableSongs.length} canciones',
      );
    } catch (error) {
      debugPrint('[PlaybackService] No se pudo cargar la cola: $error');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ===========================================================================
  // VOLUMEN · FADE IN / FADE OUT
  //
  // El volumen final es siempre:
  //
  //     volumen = baseVolume(ReplayGain + preamp) × FadeIndex.gainAt(posición)
  //
  // Al depender solo de la posición (no del tiempo transcurrido), el seek, la
  // pausa y la reanudación funcionan sin lógica adicional. La duración de
  // cada fade sale de SettingsService.
  // ===========================================================================

  /// Envía un volumen al reproductor sin ninguna comprobación.
  Future<void> _setVolumeRaw(double volume) async {
    _lastAppliedVolume = volume;
    await _player.setVolume(volume);
  }

  /// Devuelve el índice vigente, reconstruyéndolo si cambió la duración de
  /// algún fade (settings) o la duración de la pista.
  FadeIndex? _currentFadeIndex() {
    final settings = SettingsService.instance;

    final inMs = settings.fadeInEnabled
        ? (settings.fadeInDuration * 1000).round()
        : 0;
    final outMs = settings.fadeOutEnabled
        ? (settings.fadeOutDuration * 1000).round()
        : 0;

    if (inMs <= 0 && outMs <= 0) return null;

    final trackMs = _duration.inMilliseconds;
    final key = (inMs, outMs, trackMs);

    if (_fadeIndex == null || _fadeIndexKey != key) {
      _fadeIndex = FadeIndex.build(
        fadeIn: Duration(milliseconds: inMs),
        fadeOut: Duration(milliseconds: outMs),
        track: _duration,
      );
      _fadeIndexKey = key;
    }

    return _fadeIndex;
  }

  /// Volumen base derivado de ReplayGain (por pista + preamp global).
  double _baseVolume(Song song) {
    final settings = SettingsService.instance;

    if (!settings.replayGainEnabled) return 1.0;

    final trackGainDb = song.replayGainDb ?? 0.0;
    final totalGainDb = trackGainDb + settings.replayGainPreamp;

    if (totalGainDb == 0) return 1.0;

    return pow(10, totalGainDb / 20).toDouble().clamp(0.0, 4.0);
  }

  /// Calcula y aplica el volumen que toca en [at] (por defecto, la posición
  /// real del reproductor). Solo llama al plugin si el valor cambió.
  Future<void> _applyVolume({Duration? at, bool force = false}) async {
    final song = _currentSong;
    if (song == null) return;

    final position = at ?? _player.position;
    final fadeGain = _currentFadeIndex()?.gainAt(position) ?? 1.0;
    final target = (_baseVolume(song) * fadeGain).clamp(0.0, 4.0).toDouble();

    if (!force) {
      // Los extremos (0 absoluto y volumen pleno) nunca se omiten por
      // tolerancia: tienen que alcanzarse exactos.
      final isEndpoint = target == 0.0 || fadeGain >= 1.0;
      final unchanged = isEndpoint
          ? target == _lastAppliedVolume
          : (target - _lastAppliedVolume).abs() < 0.001;

      if (unchanged) return;
    }

    await _setVolumeRaw(target);
  }

  /// El timer corre solo mientras suena la pista y hay algún fade activo.
  void _syncFadeTimer() {
    final settings = SettingsService.instance;
    final needed =
        _isPlaying && (settings.fadeInEnabled || settings.fadeOutEnabled);

    if (needed) {
      _fadeTimer ??= Timer.periodic(_fadeTick, (_) {
        unawaited(_applyVolume());
      });
    } else {
      _fadeTimer?.cancel();
      _fadeTimer = null;
    }
  }

  // ===========================================================================
  // REPRODUCCIÓN
  // ===========================================================================

  Future<void> _loadAndPlaySong(Song song) async {
    final path = song.filePath;

    if (path == null || path.isEmpty || !await File(path).exists()) {
      debugPrint('[PlaybackService] Archivo no disponible: ${song.title}');
      return;
    }

    _completionHandled = false;
    _seekTarget = null;
    _seekStartedAt = null;
    _position = Duration.zero;
    _duration = Duration.zero;
    _currentSong = song;
    _currentQueueIndex = _indexOfSong(_playingSongs, song);

    StatisticsService.instance.onSongChanged(song);
    PodcastStatisticsService.instance.onSongChanged(song);

    if (_shuffleEnabled) {
      _shuffleCursor = _indexOfSong(_shuffleOrder, song);

      if (_shuffleCursor < 0) {
        _buildShuffleOrder(keepCurrentFirst: song);
        _shuffleCursor = _indexOfSong(_shuffleOrder, song);
      }
    }

    notifyListeners();

    // Reanudar podcasts desde la posición guardada (si no terminó).
    final initialPosition = song.isPodcast
        ? PodcastStatisticsService.instance.resumePositionFor(song)
        : Duration.zero;

    // Silencio absoluto ANTES de cargar la nueva fuente: si el reproductor
    // sigue en "playing", empezaría a sonar en cuanto estuviera listo y se
    // escaparía audio con el volumen de la pista anterior.
    await _setVolumeRaw(0.0);

    final loadedDuration = await _player.setAudioSource(
      AudioSource.file(path, tag: song),
      initialPosition: initialPosition,
    );

    // Con la duración conocida ya se puede construir el índice completo.
    if (loadedDuration != null) {
      _duration = loadedDuration;
    }

    // Volumen que toca en la posición inicial: 0.0 absoluto si hay fade in
    // y se arranca en 0; el volumen base en caso contrario.
    await _applyVolume(at: initialPosition, force: true);

    // El Future de play() solo se completa cuando la canción se pausa o
    // termina. Si se espera con await, _isLoading (y _handlingCompletion)
    // se quedan en true durante toda la canción y los botones de
    // anterior/siguiente permanecen deshabilitados.
    unawaited(
      _player.play().catchError((Object error) {
        debugPrint('[PlaybackService] Error al reproducir: $error');
      }),
    );
  }

  Future<void> appendToPlaybackQueue(Song song) async {
    if (_playingSongs.any((item) => _sameSong(item, song))) {
      return;
    }

    final path = song.filePath;

    if (path == null || path.isEmpty || !await File(path).exists()) {
      debugPrint('[PlaybackService] Archivo no disponible: ${song.title}');
      return;
    }

    if (_playingSongs.isEmpty) {
      await playQueue();
      return;
    }

    _playingSongs.add(song);

    if (_shuffleEnabled) {
      if (_shuffleOrder.isEmpty) {
        _shuffleOrder = [_currentSong, song].whereType<Song>().toList();
      } else {
        final insertAt = _shuffleCursor < 0
            ? _shuffleOrder.length
            : _shuffleCursor +
                  1 +
                  _random.nextInt(_shuffleOrder.length - _shuffleCursor);

        _shuffleOrder.insert(insertAt.clamp(0, _shuffleOrder.length), song);
      }

      _shuffleCursor = _currentSong == null
          ? -1
          : _indexOfSong(_shuffleOrder, _currentSong!);
    }

    debugPrint('[PlaybackService] Añadida al final de la cola: ${song.title}');

    notifyListeners();
  }

  Future<void> reorderPlaybackQueue(int oldIndex, int newIndex) async {
    final queue = PlaybackQueue.instance;
    final queueSongs = queue.songs;

    if (oldIndex < 0 ||
        oldIndex >= queueSongs.length ||
        newIndex < 0 ||
        newIndex > queueSongs.length) {
      return;
    }

    if (newIndex > oldIndex) {
      newIndex--;
    }

    if (oldIndex == newIndex) return;

    if (!queue.move(oldIndex, newIndex)) return;

    final reorderedSongs = queue.songs;

    _playingSongs = reorderedSongs
        .where(
          (song) =>
              _playingSongs.any((playingSong) => _sameSong(playingSong, song)),
        )
        .toList();

    _currentQueueIndex = _currentSong == null
        ? -1
        : _indexOfSong(_playingSongs, _currentSong!);

    if (_shuffleEnabled) {
      _shuffleOrder.removeWhere(
        (song) => !_playingSongs.any((item) => _sameSong(item, song)),
      );

      for (final song in _playingSongs) {
        if (!_shuffleOrder.any((item) => _sameSong(item, song))) {
          _shuffleOrder.add(song);
        }
      }

      _shuffleCursor = _currentSong == null
          ? -1
          : _indexOfSong(_shuffleOrder, _currentSong!);
    }

    debugPrint('[PlaybackService] Cola reordenada');
    notifyListeners();
  }

  Future<void> removeFromPlaybackQueue(Song song) async {
    final current = _currentSong;

    if (current != null && _sameSong(current, song)) {
      debugPrint(
        '[PlaybackService] No se puede eliminar la canción actual: ${song.title}',
      );
      return;
    }

    final queue = PlaybackQueue.instance;

    if (!queue.contains(song)) return;

    queue.remove(song);

    _playingSongs.removeWhere((item) => _sameSong(item, song));
    _shuffleOrder.removeWhere((item) => _sameSong(item, song));

    _currentQueueIndex = current == null
        ? -1
        : _indexOfSong(_playingSongs, current);

    _shuffleCursor = current == null
        ? -1
        : _indexOfSong(_shuffleOrder, current);

    debugPrint('[PlaybackService] Eliminada de la cola: ${song.title}');

    notifyListeners();
  }

  Future<void> pause() async {
    await _player.pause();
    await PodcastStatisticsService.instance.flush();
  }

  Future<void> resume() async {
    if (_playingSongs.isNotEmpty && _currentSong != null) {
      if (_player.processingState == ProcessingState.completed) {
        await _loadAndPlaySong(_currentSong!);
      } else {
        // El volumen que toca en la posición actual (si se pausó a mitad de
        // un fade, continúa desde ahí).
        await _applyVolume(force: true);

        unawaited(
          _player.play().catchError((Object error) {
            debugPrint('[PlaybackService] Error al reanudar: $error');
          }),
        );
      }
    } else if (_playingSongs.isNotEmpty) {
      await playQueue();
    }
  }

  Future<void> togglePlayPause() async {
    if (_isPlaying) {
      await pause();
    } else {
      await resume();
    }
  }

  Future<void> playSongFromQueue(Song song) async {
    if (_isLoading) return;

    final index = _indexOfSong(_playingSongs, song);

    if (index < 0) {
      debugPrint('[PlaybackService] La canción no está cargada: ${song.title}');
      return;
    }

    _isLoading = true;
    notifyListeners();

    try {
      if (_shuffleEnabled &&
          !_shuffleOrder.any((item) => _sameSong(item, song))) {
        _buildShuffleOrder(keepCurrentFirst: song);
      }

      await _loadAndPlaySong(song);
    } catch (error) {
      debugPrint('[PlaybackService] Error al seleccionar canción: $error');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> playNext() async {
    if (_isLoading || _playingSongs.isEmpty || _currentSong == null) {
      return;
    }

    final nextSong = _getNextSong();

    if (nextSong == null) return;

    _isLoading = true;
    notifyListeners();

    try {
      await _loadAndPlaySong(nextSong);
    } catch (error) {
      debugPrint('[PlaybackService] Error al reproducir siguiente: $error');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> playPrevious() async {
    if (_isLoading || _playingSongs.isEmpty || _currentSong == null) {
      return;
    }

    if (_position > const Duration(seconds: 3)) {
      await seek(Duration.zero);
      return;
    }

    final previousSong = _getPreviousSong();

    if (previousSong == null) return;

    _isLoading = true;
    notifyListeners();

    try {
      await _loadAndPlaySong(previousSong);
    } catch (error) {
      debugPrint('[PlaybackService] Error al reproducir anterior: $error');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Song? _getNextSong() {
    if (_shuffleEnabled) {
      if (_shuffleCursor < 0) return null;

      if (_shuffleCursor < _shuffleOrder.length - 1) {
        return _shuffleOrder[_shuffleCursor + 1];
      }

      if (_repeatMode == LoopMode.all && _shuffleOrder.length > 1) {
        final current = _currentSong;
        _buildShuffleOrder(keepCurrentFirst: null);

        if (current != null &&
            _shuffleOrder.length > 1 &&
            _sameSong(_shuffleOrder.first, current)) {
          final nextIndex = 1 + _random.nextInt(_shuffleOrder.length - 1);
          final temp = _shuffleOrder[1];
          _shuffleOrder[1] = _shuffleOrder[nextIndex];
          _shuffleOrder[nextIndex] = temp;
        }

        _shuffleCursor = -1;
        return _shuffleOrder.firstWhere(
          (item) => current == null || !_sameSong(item, current),
          orElse: () => _shuffleOrder.first,
        );
      }

      return null;
    }

    if (_currentQueueIndex < 0) return null;

    if (_currentQueueIndex < _playingSongs.length - 1) {
      return _playingSongs[_currentQueueIndex + 1];
    }

    if (_repeatMode == LoopMode.all && _playingSongs.length > 1) {
      return _playingSongs.first;
    }

    return null;
  }

  Song? _getPreviousSong() {
    if (_shuffleEnabled) {
      if (_shuffleCursor > 0) {
        return _shuffleOrder[_shuffleCursor - 1];
      }

      if (_repeatMode == LoopMode.all && _shuffleOrder.length > 1) {
        return _shuffleOrder.last;
      }

      return null;
    }

    if (_currentQueueIndex > 0) {
      return _playingSongs[_currentQueueIndex - 1];
    }

    if (_repeatMode == LoopMode.all && _playingSongs.length > 1) {
      return _playingSongs.last;
    }

    return null;
  }

  Future<void> _handleTrackCompleted() async {
    if (_handlingCompletion || _isLoading || _currentSong == null) {
      return;
    }

    _handlingCompletion = true;

    try {
      // Garantía final: la pista termina en silencio absoluto aunque el
      // último tick del timer no haya llegado a tiempo.
      if (SettingsService.instance.fadeOutEnabled) {
        await _setVolumeRaw(0.0);
      }

      PodcastStatisticsService.instance.onTrackCompleted();

      if (_repeatMode == LoopMode.one) {
        await _loadAndPlaySong(_currentSong!);
        return;
      }

      final nextSong = _getNextSong();

      if (nextSong != null) {
        await _loadAndPlaySong(nextSong);
      } else {
        _isPlaying = false;
        _position = _duration;
        _syncFadeTimer();
        notifyListeners();
      }
    } catch (error) {
      debugPrint('[PlaybackService] Error al avanzar la reproducción: $error');
    } finally {
      _handlingCompletion = false;
    }
  }

  Future<void> seek(Duration position) async {
    _seekTarget = position;
    _seekStartedAt = DateTime.now();
    _position = position;

    StatisticsService.instance.onSeek(position);
    PodcastStatisticsService.instance.onSeek(position);

    // Volumen que toca en la posición de destino, aplicado ya (antes de que
    // el audio salte): al saltar dentro de un fade, suena en su nivel
    // correcto; al saltar fuera de uno, vuelve a volumen pleno.
    unawaited(_applyVolume(at: position));

    notifyListeners();

    await _player.seek(position);

    if (!_isPlaying) {
      _position = position;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    _fadeTimer?.cancel();
    _fadeTimer = null;
    _fadeIndex = null;
    _fadeIndexKey = null;
    _lastAppliedVolume = -1;

    await _player.stop();

    _playingSongs = [];
    _shuffleOrder = [];
    _currentSong = null;
    _currentQueueIndex = -1;
    _shuffleCursor = -1;
    _position = Duration.zero;
    _duration = Duration.zero;
    _isPlaying = false;
    _isLoading = false;
    _completionHandled = false;
    _handlingCompletion = false;
    _seekTarget = null;
    _seekStartedAt = null;

    StatisticsService.instance.onSongChanged(null);
    PodcastStatisticsService.instance.onSongChanged(null);
    await PodcastStatisticsService.instance.flush();

    notifyListeners();
  }

  @override
  void dispose() {
    _fadeTimer?.cancel();
    SettingsService.instance.removeListener(_onSettingsChanged);
    unawaited(PodcastStatisticsService.instance.flush());
    unawaited(_player.dispose());
    super.dispose();
  }
}
