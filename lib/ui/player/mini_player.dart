import 'dart:io';

import 'package:flutter/material.dart';

import '../app_theme.dart';

class MiniPlayer extends StatelessWidget {
  final String title;
  final String artist;
  final String? artworkPath;
  final Duration position;
  final Duration duration;
  final bool isPlaying;
  final bool isDesktop;
  final VoidCallback? onClose;
  final VoidCallback? onExpand;
  final VoidCallback? onPlayPause;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  const MiniPlayer({
    super.key,
    this.title = 'Ninguna canción seleccionada',
    this.artist = '',
    this.artworkPath,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.isPlaying = false,
    this.isDesktop = false,
    this.onClose,
    this.onExpand,
    this.onPlayPause,
    this.onPrevious,
    this.onNext,
  });

  String _formatDuration(Duration value) {
    final minutes = value.inMinutes;
    final seconds = value.inSeconds.remainder(60);
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalMilliseconds = duration.inMilliseconds;
    final currentMilliseconds = position.inMilliseconds.clamp(
      0,
      totalMilliseconds > 0 ? totalMilliseconds : 0,
    );

    final progress = totalMilliseconds > 0
        ? currentMilliseconds / totalMilliseconds
        : 0.0;

    return Material(
      color: Colors.transparent,
      child: Container(
        margin: EdgeInsets.fromLTRB(
          isDesktop ? 16 : 12,
          4,
          isDesktop ? 16 : 12,
          8,
        ),
        decoration: BoxDecoration(
          color: AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppTheme.textSecondary.withValues(alpha: 0.12),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: onExpand,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
                child: Row(
                  children: [
                    _MiniPlayerArtwork(artworkPath: artworkPath, size: 48),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            artist.isEmpty ? 'Artista desconocido' : artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Canción anterior',
                      onPressed: onPrevious,
                      icon: const Icon(Icons.skip_previous_rounded),
                      visualDensity: VisualDensity.compact,
                    ),
                    IconButton(
                      tooltip: isPlaying ? 'Pausar' : 'Reproducir',
                      onPressed: onPlayPause,
                      icon: Icon(
                        isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
                      iconSize: 30,
                      visualDensity: VisualDensity.compact,
                    ),
                    IconButton(
                      tooltip: 'Siguiente canción',
                      onPressed: onNext,
                      icon: const Icon(Icons.skip_next_rounded),
                      visualDensity: VisualDensity.compact,
                    ),
                    IconButton(
                      tooltip: 'Cerrar reproductor',
                      onPressed: onClose,
                      icon: const Icon(Icons.close_rounded),
                      iconSize: 20,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(
                children: [
                  Text(
                    _formatDuration(position),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 3,
                        backgroundColor: AppTheme.textSecondary.withValues(
                          alpha: 0.2,
                        ),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          AppTheme.accent,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _formatDuration(duration),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniPlayerArtwork extends StatelessWidget {
  final String? artworkPath;
  final double size;

  const _MiniPlayerArtwork({required this.artworkPath, required this.size});

  @override
  Widget build(BuildContext context) {
    if (artworkPath != null && artworkPath!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.file(
          File(artworkPath!),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _placeholder(),
        ),
      );
    }

    return _placeholder();
  }

  Widget _placeholder() {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.accent,
            Color.lerp(AppTheme.accent, Colors.black, 0.65)!,
          ],
        ),
      ),
      child: const Icon(
        Icons.music_note_rounded,
        color: Colors.white,
        size: 27,
      ),
    );
  }
}
