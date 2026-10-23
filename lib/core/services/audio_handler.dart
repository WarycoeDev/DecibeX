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

  @override
  Future<void> play() => _playback.resume();

  @override
  Future<void> pause() => _playback.pause();

  @override
  Future<void> seek(Duration position) => _playback.seek(position);

  @override
  Future<void> skipToNext() => _playback.playNext();

  @override
  Future<void> skipToPrevious() => _playback.playPrevious();

  @override
  Future<void> stop() => _playback.stop();

  void _publishPlaybackState() {
    final song = _playback.currentSong;
    final songs = _playback.playingSongs;

    if (song != null) {
      mediaItem.add(_toMediaItem(song, _playback.duration));
    }

    // Se mantienen posiciones fijas para que androidCompactActionIndices
    // siempre apunte a controles válidos, incluso en los extremos de la cola.
    final controls = <MediaControl>[
      MediaControl.skipToPrevious,
      _playback.isPlaying ? MediaControl.pause : MediaControl.play,
      MediaControl.skipToNext,
      MediaControl.stop,
    ];

    queue.add(songs.map((item) => _toMediaItem(item)).toList());

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
        androidCompactActionIndices: const [0, 1, 2],
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
