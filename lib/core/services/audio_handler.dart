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
  Future<void> play() => _playback.resume();

  @override
  Future<void> pause() => _playback.pause();

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
      final mediaItemKey = song == null
          ? null
          : '${song.filePath}|${_playback.duration.inMilliseconds}';

      if (mediaItemKey != _lastMediaItemKey && song != null) {
        mediaItem.add(_toMediaItem(song, _playback.duration));
        _lastMediaItemKey = mediaItemKey;
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

    playbackState.add(
      PlaybackState(
        controls: controls,
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: compactActionIndices,
        processingState: processingState,
        playing: _playback.isPlaying,
        updatePosition: _playback.position,
        bufferedPosition: _playback.bufferedPosition,
        speed: _playback.speed,
        queueIndex: _playback.currentIndex,
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
