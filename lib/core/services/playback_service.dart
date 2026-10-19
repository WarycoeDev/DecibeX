import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../models/song.dart';
import 'playback_queue.dart';

class PlaybackService extends ChangeNotifier {
  PlaybackService._() {
    _player.playerStateStream.listen((state) {
      final wasPlaying = _isPlaying;
      _isPlaying = state.playing;

      // Al reanudar, mantenemos el objetivo un instante más para filtrar
      // valores obsoletos; después la posición vuelve a ser la del reproductor.
      if (!wasPlaying && _isPlaying && _seekTarget != null) {
        _seekStartedAt = DateTime.now();
      }

      notifyListeners();
    });

    _player.positionStream.listen((value) {
      final target = _seekTarget;

      if (target != null) {
        final isCloseToTarget =
            (value.inMilliseconds - target.inMilliseconds).abs() <= 1000;

        if (_isPlaying) {
          // Reproduciendo: el flujo vuelve a la normalidad en cuanto llega
          // un valor cercano al objetivo, o pasado un breve margen.
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
          // En pausa: el objetivo se mantiene y cualquier valor lejano
          // (p. ej. un 0:00 obsoleto que llega tras el seek) se descarta.
          // Se limpia al reanudar, al cambiar de canción o al hacer otro seek.
          return;
        }
      }

      _position = value;
      notifyListeners();
    });

    _player.durationStream.listen((value) {
      _duration = value ?? Duration.zero;
      notifyListeners();
    });

    _player.currentIndexStream.listen((index) {
      if (index == null || index < 0 || index >= _playingSongs.length) {
        notifyListeners();
        return;
      }

      final newSong = _playingSongs[index];
      final previousSong = _currentSong;
      final songChanged =
          previousSong == null || !_sameSong(previousSong, newSong);

      _currentSong = newSong;

      // Solo reiniciamos la posición si realmente cambió la canción.
      // Antes se reiniciaba también al hacer seek, dejando la barra en 0:00.
      if (songChanged) {
        _position = Duration.zero;
        _seekTarget = null;
      }

      notifyListeners();
    });

    _player.errorStream.listen((error) {
      debugPrint('[PlaybackService] Error de audio: $error');
    });
  }

  static final PlaybackService instance = PlaybackService._();

  final AudioPlayer _player = AudioPlayer();

  List<Song> _playingSongs = [];
  Song? _currentSong;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;
  bool _isLoading = false;

  // Seek solicitado por el usuario y momento en que se pidió.
  Duration? _seekTarget;
  DateTime? _seekStartedAt;

  Song? get currentSong => _currentSong;
  Duration get position => _position;
  Duration get duration => _duration;
  bool get isPlaying => _isPlaying;
  bool get isLoading => _isLoading;

  int? get currentIndex => _player.currentIndex;

  bool get canPlayPrevious {
    if (_isLoading || _playingSongs.isEmpty || _currentSong == null) {
      return false;
    }

    final index = _player.currentIndex;

    if (index == null || index < 0 || index >= _playingSongs.length) {
      return false;
    }

    return _position > const Duration(seconds: 3) || index > 0;
  }

  bool get canPlayNext {
    if (_isLoading || _playingSongs.isEmpty || _currentSong == null) {
      return false;
    }

    final index = _player.currentIndex;

    if (index == null || index < 0 || index >= _playingSongs.length) {
      return false;
    }

    return index < _playingSongs.length - 1;
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

    _isLoading = true;
    _playingSongs = availableSongs;
    _currentSong = availableSongs.first;
    _position = Duration.zero;
    _duration = Duration.zero;
    _seekTarget = null;
    _seekStartedAt = null;
    notifyListeners();

    try {
      final sources = availableSongs
          .map((song) => AudioSource.file(song.filePath!, tag: song))
          .toList();

      await _player.setAudioSources(
        sources,
        initialIndex: 0,
        initialPosition: Duration.zero,
      );

      unawaited(
        _player.play().catchError((Object error) {
          debugPrint('[PlaybackService] Error al reproducir: $error');
        }),
      );

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

  Future<void> appendToPlaybackQueue(Song song) async {
    if (_playingSongs.any((item) => _sameSong(item, song))) {
      return;
    }

    final path = song.filePath;

    if (path == null || path.isEmpty || !await File(path).exists()) {
      debugPrint('[PlaybackService] Archivo no disponible: ${song.title}');
      return;
    }

    if (_playingSongs.isEmpty || _player.audioSources.isEmpty) {
      await playQueue();
      return;
    }

    try {
      await _player.addAudioSource(AudioSource.file(path, tag: song));

      _playingSongs.add(song);

      debugPrint(
        '[PlaybackService] Añadida al final de la cola: ${song.title}',
      );

      notifyListeners();
    } catch (error) {
      debugPrint('[PlaybackService] No se pudo añadir la canción: $error');
    }
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

    final movedSong = queueSongs[oldIndex];
    final playingIndex = _playingSongs.indexWhere(
      (song) => _sameSong(song, movedSong),
    );

    final currentSongBeforeMove = _currentSong;
    final positionBeforeMove = _position;

    if (!queue.move(oldIndex, newIndex)) return;

    if (playingIndex == -1 || _player.audioSources.isEmpty) {
      return;
    }

    final reorderedSongs = queue.songs;
    final desiredPlayingSongs = reorderedSongs
        .where(
          (song) =>
              _playingSongs.any((playingSong) => _sameSong(playingSong, song)),
        )
        .toList();

    final targetPlayingIndex = desiredPlayingSongs.indexWhere(
      (song) => _sameSong(song, movedSong),
    );

    if (targetPlayingIndex == -1 ||
        targetPlayingIndex >= _player.audioSources.length) {
      return;
    }

    if (playingIndex != targetPlayingIndex) {
      try {
        await _player.moveAudioSource(playingIndex, targetPlayingIndex);

        _playingSongs = desiredPlayingSongs;
        _currentSong = currentSongBeforeMove;
        _position = positionBeforeMove;

        final currentIndex = _player.currentIndex;

        if (currentIndex != null &&
            currentIndex >= 0 &&
            currentIndex < _playingSongs.length) {
          _currentSong = currentSongBeforeMove ?? _playingSongs[currentIndex];
        }

        notifyListeners();

        debugPrint(
          '[PlaybackService] Cola reordenada sin reiniciar la reproducción',
        );
      } catch (error) {
        debugPrint('[PlaybackService] Error al reordenar la cola: $error');
      }
    }
  }

  Future<void> removeFromPlaybackQueue(Song song) async {
    final index = _playingSongs.indexWhere((item) => _sameSong(item, song));

    if (index == -1 || index >= _player.audioSources.length) {
      return;
    }

    final wasCurrentSong = _player.currentIndex == index;

    _playingSongs.removeAt(index);

    try {
      await _player.removeAudioSourceAt(index);

      if (_playingSongs.isEmpty) {
        _currentSong = null;
        _position = Duration.zero;
        _duration = Duration.zero;
        _isPlaying = false;
        _seekTarget = null;
        _seekStartedAt = null;
      } else {
        final currentIndex = _player.currentIndex;

        if (currentIndex != null &&
            currentIndex >= 0 &&
            currentIndex < _playingSongs.length) {
          _currentSong = _playingSongs[currentIndex];
        } else if (wasCurrentSong) {
          _currentSong = null;
        }
      }

      debugPrint('[PlaybackService] Eliminada de la cola: ${song.title}');

      notifyListeners();
    } catch (error) {
      debugPrint('[PlaybackService] No se pudo quitar la canción: $error');
    }
  }

  Future<void> pause() async {
    await _player.pause();
  }

  Future<void> resume() async {
    if (_playingSongs.isNotEmpty) {
      await _player.play();
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

    final index = _playingSongs.indexWhere((item) => _sameSong(item, song));

    if (index < 0 || index >= _player.audioSources.length) {
      debugPrint(
        '[PlaybackService] La canción no está cargada '
        'en el reproductor: ${song.title}',
      );
      return;
    }

    try {
      _seekTarget = null;
      _seekStartedAt = null;

      await _player.seek(Duration.zero, index: index);
      await _player.play();
    } catch (error) {
      debugPrint('[PlaybackService] Error al seleccionar canción: $error');
    }
  }

  Future<void> playNext() async {
    if (!canPlayNext) return;

    await _player.seekToNext();
  }

  Future<void> playPrevious() async {
    if (!canPlayPrevious) return;

    if (_position > const Duration(seconds: 3)) {
      await seek(Duration.zero);
    } else {
      await _player.seekToPrevious();
    }
  }

  Future<void> seek(Duration position) async {
    // Actualizamos la posición de inmediato para que la barra no salte.
    _seekTarget = position;
    _seekStartedAt = DateTime.now();
    _position = position;
    notifyListeners();

    await _player.seek(position);

    // Si está en pausa, nos aseguramos de conservar la posición elegida.
    if (!_isPlaying) {
      _position = position;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    await _player.stop();

    _playingSongs = [];
    _currentSong = null;
    _position = Duration.zero;
    _duration = Duration.zero;
    _isPlaying = false;
    _isLoading = false;
    _seekTarget = null;
    _seekStartedAt = null;

    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_player.dispose());
    super.dispose();
  }
}
