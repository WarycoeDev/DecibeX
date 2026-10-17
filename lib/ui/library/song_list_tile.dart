import 'dart:io';

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../../core/models/song.dart';

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

  /// Nombre del archivo sin extensión. Si no hay ruta, usa el título.
  String get _displayTitle {
    final path = song.filePath;

    if (path == null || path.isEmpty) return song.title;

    final name = path.split(RegExp(r'[\\/]')).last;
    final dot = name.lastIndexOf('.');
    final baseName = dot <= 0 ? name : name.substring(0, dot);

    return baseName.isEmpty ? song.title : baseName;
  }

  void _onSongTap() {
    debugPrint('Canción seleccionada: ${song.filePath ?? song.title}');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final artworkSize = isDesktop ? 50.0 : 46.0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _onSongTap,
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
              if (onFavoriteChanged != null)
                IconButton(
                  tooltip: song.favorite
                      ? 'Quitar de favoritos'
                      : 'Agregar a favoritos',
                  onPressed: () => onFavoriteChanged!(!song.favorite),
                  icon: Icon(
                    song.favorite
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                  ),
                  color: song.favorite
                      ? AppTheme.accent
                      : AppTheme.textSecondary,
                  visualDensity: VisualDensity.compact,
                ),
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
                onPressed: onMoreOptions ?? () {},
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
