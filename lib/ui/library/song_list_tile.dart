import 'dart:io';

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../../core/models/song.dart';
import '../../core/services/playback_queue.dart';
import '../../core/services/playback_service.dart';

class SongListTile extends StatelessWidget {
  final Song song;
  final bool isDesktop;
  final VoidCallback? onMoreOptions;
  final ValueChanged<bool>? onFavoriteChanged;

  const SongListTile({
    super.key,
    required this.song,
    required this.isDesktop,
    this.onMoreOptions,
    this.onFavoriteChanged,
  });

  String get _displayTitle {
    final path = song.filePath;

    if (path == null || path.isEmpty) return song.title;

    final name = path.split(RegExp(r'[\\/]')).last;
    final dot = name.lastIndexOf('.');
    final baseName = dot <= 0 ? name : name.substring(0, dot);

    return baseName.isEmpty ? song.title : baseName;
  }

  Future<void> _onSongTap(BuildContext context) async {
    final queue = PlaybackQueue.instance;
    final playback = PlaybackService.instance;

    if (queue.isEmpty) {
      if (queue.add(song)) {
        await playback.playQueue();
      }
      return;
    }

    final alreadyQueued = queue.contains(song);

    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.surfaceVariant,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: Text(
                    _displayTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.playlist_remove_rounded),
                  title: const Text('Sobrescribir cola'),
                  onTap: () => Navigator.pop(context, 'replace'),
                ),
                ListTile(
                  leading: Icon(
                    alreadyQueued
                        ? Icons.remove_circle_outline_rounded
                        : Icons.playlist_add_rounded,
                  ),
                  title: Text(
                    alreadyQueued ? 'Quitar de la cola' : 'Añadir a la cola',
                  ),
                  onTap: () => Navigator.pop(context, 'toggle'),
                ),
                ListTile(
                  leading: const Icon(Icons.close_rounded),
                  title: const Text('Cancelar'),
                  onTap: () => Navigator.pop(context, 'cancel'),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!context.mounted || action == null || action == 'cancel') {
      return;
    }

    await _handleQueueAction(action);
  }

  Future<void> _handleQueueAction(String action) async {
    final queue = PlaybackQueue.instance;
    final playback = PlaybackService.instance;

    switch (action) {
      case 'replace':
        if (queue.isEmpty) return;

        queue.replace(song);
        await playback.playQueue();
        break;

      case 'toggle':
        if (queue.contains(song)) {
          if (queue.remove(song)) {
            await playback.removeFromPlaybackQueue(song);
          }
        } else {
          final queueWasEmpty = queue.isEmpty;

          if (queue.add(song)) {
            if (queueWasEmpty) {
              await playback.playQueue();
              await playback.pause();
            } else {
              await playback.appendToPlaybackQueue(song);
            }
          }
        }
        break;
    }
  }

  Future<void> _showContextMenu(BuildContext context) async {
    final queue = PlaybackQueue.instance;
    final alreadyQueued = queue.contains(song);
    final queueIsEmpty = queue.isEmpty;

    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.surfaceVariant,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: Row(
                    children: [
                      _SongArtwork(song: song, size: 44),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _displayTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(
                                sheetContext,
                              ).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              song.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(sheetContext).textTheme.bodySmall
                                  ?.copyWith(color: AppTheme.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (!queueIsEmpty)
                  ListTile(
                    leading: const Icon(Icons.playlist_remove_rounded),
                    title: const Text('Sobrescribir cola'),
                    onTap: () => Navigator.pop(sheetContext, 'replace'),
                  ),
                ListTile(
                  leading: Icon(
                    alreadyQueued
                        ? Icons.remove_circle_outline_rounded
                        : Icons.playlist_add_rounded,
                  ),
                  title: Text(
                    alreadyQueued ? 'Quitar de la cola' : 'Añadir a la cola',
                  ),
                  onTap: () => Navigator.pop(sheetContext, 'toggle'),
                ),
                if (onFavoriteChanged != null)
                  ListTile(
                    leading: Icon(
                      song.favorite
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      color: song.favorite ? AppTheme.accent : null,
                    ),
                    title: Text(
                      song.favorite
                          ? 'Quitar de favoritos'
                          : 'Agregar a favoritos',
                    ),
                    onTap: () => Navigator.pop(sheetContext, 'favorite'),
                  ),
                ListTile(
                  leading: const Icon(Icons.close_rounded),
                  title: const Text('Cancelar'),
                  onTap: () => Navigator.pop(sheetContext, 'cancel'),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!context.mounted || action == null || action == 'cancel') {
      return;
    }

    if (action == 'favorite') {
      onFavoriteChanged?.call(!song.favorite);
      return;
    }

    await _handleQueueAction(action);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final artworkSize = isDesktop ? 50.0 : 46.0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _onSongTap(context),
        onLongPress: () => _showContextMenu(context),
        borderRadius: BorderRadius.circular(12),
        hoverColor: AppTheme.surfaceVariant.withValues(alpha: 0.45),
        splashColor: AppTheme.accent.withValues(alpha: 0.12),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isDesktop ? 20 : 12,
            vertical: isDesktop ? 12 : 10,
          ),
          child: Row(
            children: [
              _SongArtwork(song: song, size: artworkSize),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      song.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 42,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    song.duration,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              ),
              IconButton(
                onPressed: () => _showContextMenu(context),
                tooltip: 'Más opciones',
                icon: const Icon(Icons.more_horiz_rounded),
                color: AppTheme.textSecondary,
                iconSize: 22,
                visualDensity: VisualDensity.compact,
                splashRadius: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SongArtwork extends StatelessWidget {
  final Song song;
  final double size;

  const _SongArtwork({required this.song, required this.size});

  @override
  Widget build(BuildContext context) {
    final artworkPath = song.artworkPath;
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final cacheSize = (size * pixelRatio).round().clamp(1, 512);

    if (artworkPath != null && artworkPath.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: Image.file(
          File(artworkPath),
          width: size,
          height: size,
          fit: BoxFit.cover,
          cacheWidth: cacheSize,
          cacheHeight: cacheSize,
          filterQuality: FilterQuality.low,
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
        borderRadius: BorderRadius.circular(11),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [song.color, Color.lerp(song.color, Colors.black, 0.72)!],
        ),
      ),
      child: Icon(
        song.icon,
        color: Colors.white.withValues(alpha: 0.92),
        size: size * 0.46,
      ),
    );
  }
}
