import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart' as just_audio;

import '../models/song.dart';
import 'playback_service.dart';

/// Puente entre los controles multimedia de Android y el reproductor de DecibeX.
///
/// PlaybackService sigue siendo la única fuente de verdad: este handler solo
/// traduce los comandos del sistema y publica su estado y sus metadatos.
class DecibeXAudioHandler extends BaseAudioHandler with SeekHandler {
  DecibeXAudioHandler() {
    _playback.addListener(_publishPlaybackState);
    _publishPlaybackState();
  }

  final PlaybackService _playback = PlaybackService.instance;

  bool _isSeeking = false;
  int _seekGeneration = 0;
  List<MediaControl>? _lastControls;
  List<int>? _lastCompactActionIndices;
  String? _lastMediaItemKey;
  String? _lastQueueKey;

  @override
  Future<void> play() async {
    // resume() puede recargar la pista si la voz quedó invalidada en
    // background (audio focus perdido, Bluetooth desconectado, proceso
    // suspendido). En ese caso el estado se publica solo al terminar.
    await _playback.resume();
    _publishPlaybackState();
  }

  @override
  Future<void> pause() async {
    await _playback.pause();
    _publishPlaybackState();
  }

  @override
  Future<void> seek(Duration position) async {
    final generation = ++_seekGeneration;
    _isSeeking = true;
    _publishPlaybackState(updateControls: false, updateQueue: false);

    try {
      await _playback.seek(position);
    } finally {
      if (generation == _seekGeneration) {
        _isSeeking = false;
        _publishPlaybackState();
      }
    }
  }

  @override
  Future<void> skipToNext() {
    if (!_playback.canPlayNext) return Future<void>.value();
    return _playback.playNext();
  }

  @override
  Future<void> skipToPrevious() {
    if (!_playback.canPlayPrevious) return Future<void>.value();
    return _playback.playPrevious();
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    final songs = _playback.playingSongs;
    if (index < 0 || index >= songs.length) return;

    await _playback.playSongFromQueue(songs[index]);
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) {
    return _playback.setRepeatMode(switch (repeatMode) {
      AudioServiceRepeatMode.one => just_audio.LoopMode.one,
      AudioServiceRepeatMode.all ||
      AudioServiceRepeatMode.group => just_audio.LoopMode.all,
      AudioServiceRepeatMode.none => just_audio.LoopMode.off,
    });
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) {
    return _playback.setShuffle(shuffleMode != AudioServiceShuffleMode.none);
  }

  @override
  Future<void> stop() => _playback.stop();

  void _publishPlaybackState({
    bool updateControls = true,
    bool updateQueue = true,
  }) {
    // Android puede reconstruir la notificación al recibir cambios de
    // controles/cola. Durante un seek solo actualizamos la posición.
    if (_isSeeking) {
      updateControls = false;
      updateQueue = false;
    }

    final song = _playback.currentSong;
    final songs = _playback.playingSongs;

    if (updateQueue && !_isSeeking) {
      if (song == null) {
        // Al detener, se limpia el metadato para que no quede la pista vieja.
        if (_lastMediaItemKey != null) {
          mediaItem.add(null);
          _lastMediaItemKey = null;
        }
      } else {
        // Mientras la duración real aún no se conoce se usa la del texto.
        final liveDuration = _playback.duration > Duration.zero
            ? _playback.duration
            : null;
        final mediaItemKey = '${song.filePath}|${liveDuration?.inMilliseconds}';

        if (mediaItemKey != _lastMediaItemKey) {
          mediaItem.add(_toMediaItem(song, liveDuration));
          _lastMediaItemKey = mediaItemKey;
        }
      }

      final queueKey = songs
          .map((item) => item.filePath ?? item.title)
          .join('|');
      if (queueKey != _lastQueueKey) {
        queue.add(songs.map((item) => _toMediaItem(item)).toList());
        _lastQueueKey = queueKey;
      }
    }

    if (updateControls) {
      final controls = <MediaControl>[];
      final compactActionIndices = <int>[];

      if (_playback.canPlayPrevious) {
        compactActionIndices.add(controls.length);
        controls.add(MediaControl.skipToPrevious);
      }

      compactActionIndices.add(controls.length);
      controls.add(
        _playback.isPlaying ? MediaControl.pause : MediaControl.play,
      );

      if (_playback.canPlayNext) {
        compactActionIndices.add(controls.length);
        controls.add(MediaControl.skipToNext);
      }

      _lastControls = controls;
      _lastCompactActionIndices = compactActionIndices;
    }

    final controls = _lastControls ?? const <MediaControl>[];
    final compactActionIndices = _lastCompactActionIndices ?? const <int>[];

    final processingState = switch (_playback.processingState) {
      just_audio.ProcessingState.loading => AudioProcessingState.loading,
      just_audio.ProcessingState.buffering => AudioProcessingState.buffering,
      just_audio.ProcessingState.completed => AudioProcessingState.completed,
      just_audio.ProcessingState.ready => AudioProcessingState.ready,
      just_audio.ProcessingState.idle => AudioProcessingState.idle,
    };

    final repeatMode = switch (_playback.repeatMode) {
      just_audio.LoopMode.one => AudioServiceRepeatMode.one,
      just_audio.LoopMode.all => AudioServiceRepeatMode.all,
      just_audio.LoopMode.off => AudioServiceRepeatMode.none,
    };

    playbackState.add(
      PlaybackState(
        controls: controls,
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.skipToQueueItem,
          MediaAction.setRepeatMode,
          MediaAction.setShuffleMode,
        },
        androidCompactActionIndices: compactActionIndices,
        processingState: processingState,
        playing: _playback.isPlaying,
        updatePosition: _playback.position,
        bufferedPosition: _playback.bufferedPosition,
        speed: _playback.speed,
        queueIndex: _playback.currentIndex,
        repeatMode: repeatMode,
        shuffleMode: _playback.shuffleEnabled
            ? AudioServiceShuffleMode.all
            : AudioServiceShuffleMode.none,
      ),
    );
  }

  MediaItem _toMediaItem(Song song, [Duration? duration]) {
    final path = song.filePath;
    final artwork = song.artworkPath;

    return MediaItem(
      id: path != null && path.isNotEmpty
          ? path
          : '${song.artist}-${song.title}',
      title: song.title,
      artist: song.artist,
      album: song.album,
      duration: duration ?? _durationFromText(song.duration),
      artUri: artwork != null && artwork.isNotEmpty ? Uri.file(artwork) : null,
      playable: path != null && path.isNotEmpty,
    );
  }

  Duration? _durationFromText(String value) {
    final parts = value.split(':');
    if (parts.length != 2) return null;

    final minutes = int.tryParse(parts[0]);
    final seconds = int.tryParse(parts[1]);
    if (minutes == null || seconds == null) return null;

    return Duration(minutes: minutes, seconds: seconds);
  }

  @override
  Future<void> onTaskRemoved() async {
    // Mantener la reproducción mientras el usuario cierra la UI desde
    // recientes; Android seguirá gestionando la sesión multimedia.
  }

  void dispose() {
    _playback.removeListener(_publishPlaybackState);
  }
}
