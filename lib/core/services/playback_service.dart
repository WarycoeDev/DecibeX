import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../models/song.dart';
import 'playback_queue.dart';

class PlaybackService extends ChangeNotifier {
  PlaybackService._() {
    _player.playerStateStream.listen((state) {
      _isPlaying = state.playing;
      notifyListeners();
    });

    _player.positionStream.listen((value) {
      _position = value;
      notifyListeners();
    });

    _player.durationStream.listen((value) {
      _duration = value ?? Duration.zero;
      notifyListeners();
    });

    _player.currentIndexStream.listen((index) {
      if (index == null || index < 0 || index >= _playingSongs.length) {
        return;
      }

      _currentSong = _playingSongs[index];
      _position = Duration.zero;
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

  Song? get currentSong => _currentSong;
  Duration get position => _position;
  Duration get duration => _duration;
  bool get isPlaying => _isPlaying;
  bool get isLoading => _isLoading;

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

  Future<void> playNext() async {
    await _player.seekToNext();
  }

  Future<void> playPrevious() async {
    if (_position > const Duration(seconds: 3)) {
      await _player.seek(Duration.zero);
    } else {
      await _player.seekToPrevious();
    }
  }

  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  Future<void> stop() async {
    await _player.stop();

    _playingSongs = [];
    _currentSong = null;
    _position = Duration.zero;
    _duration = Duration.zero;
    _isPlaying = false;

    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_player.dispose());
    super.dispose();
  }
}
