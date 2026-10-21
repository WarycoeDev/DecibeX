import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../../core/models/song.dart';
import '../../core/models/playlist.dart';
import '../../core/services/playback_queue.dart';
import '../../core/services/playback_service.dart';
import '../../core/services/playlist_service.dart';
import '../../features/library/playlist_name_dialog.dart';

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

    // [NUEVO] Aseguramos que las playlists estén cargadas antes de decidir
    // si mostramos "Añadir a playlist" o "Crear playlist".
    final playlistService = PlaylistService.instance;
    try {
      await playlistService.initialize();
    } catch (_) {}
    final hasPlaylists = playlistService.playlists.isNotEmpty;

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
                  child: ScrollingTitle(
                    title: _displayTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                    textAlign: TextAlign.center,
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
                // [MODIFICADO] Etiqueta y acción condicionales.
                ListTile(
                  leading: const Icon(Icons.library_music_rounded),
                  title: Text(
                    hasPlaylists ? 'Añadir a playlist' : 'Crear playlist',
                  ),
                  onTap: () => Navigator.pop(
                    context,
                    hasPlaylists ? 'playlist' : 'create_playlist',
                  ),
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

    if (action == 'create_playlist') {
      await _createPlaylistThenAddSong(context);
      return;
    }

    if (action == 'playlist') {
      await _showAddToPlaylistDialog(context);
      return;
    }

    await _handleQueueAction(action);
  }

  /// [NUEVO] Crea una playlist con el diálogo compartido y, al terminar,
  /// abre el selector de playlists para añadir la canción.
  Future<void> _createPlaylistThenAddSong(BuildContext context) async {
    final service = PlaylistService.instance;

    // 1) Diálogo de creación (reutiliza el de LibraryScreen).
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const PlaylistNameDialog(
        icon: Icons.queue_music_rounded,
        title: 'Nueva playlist',
        subtitle: 'Ponle un nombre para empezar a organizar tu música.',
        confirmLabel: 'Crear',
      ),
    );

    if (name == null || !context.mounted) return;

    // 2) Crear la playlist.
    try {
      await service.create(name);
    } catch (_) {
      return;
    }

    if (!context.mounted) return;

    // 3) Abrir el diálogo de selección de playlists para añadir la canción.
    await _showAddToPlaylistDialog(context);
  }

  Future<void> _handleQueueAction(String action) async {
    final queue = PlaybackQueue.instance;
    final playback = PlaybackService.instance;

    switch (action) {
      case 'replace':
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

  Future<void> _showAddToPlaylistDialog(BuildContext context) async {
    final service = PlaylistService.instance;

    if (song.filePath == null || song.filePath!.isEmpty) return;

    try {
      await service.initialize();

      if (!context.mounted) return;

      final playlists = service.playlists;

      if (playlists.isEmpty) return;

      final songPath = song.filePath!;

      // Playlists que ya contenían esta canción al abrir el diálogo.
      final initiallyContaining = <String>{
        for (final playlist in playlists)
          if (playlist.songPaths.contains(songPath)) playlist.id,
      };

      // Estado seleccionado actual (arranca igual que el inicial).
      final selectedIds = <String>{...initiallyContaining};

      final selectedPlaylists = await showDialog<List<Playlist>>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              final theme = Theme.of(context);
              final colorScheme = theme.colorScheme;

              final hasChanges =
                  selectedIds.length != initiallyContaining.length ||
                  !selectedIds.containsAll(initiallyContaining);

              return Dialog(
                backgroundColor: AppTheme.surfaceVariant,
                surfaceTintColor: Colors.transparent,
                insetPadding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 24,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 430,
                    maxHeight: 560,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 24, 16, 20),
                        child: Row(
                          children: [
                            _SongArtwork(song: song, size: 56),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Añadir a playlist',
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _displayTitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                  const SizedBox(height: 2),
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
                            IconButton(
                              onPressed: () => Navigator.pop(dialogContext),
                              icon: const Icon(Icons.close_rounded),
                              tooltip: 'Cerrar',
                            ),
                          ],
                        ),
                      ),
                      Divider(
                        height: 1,
                        color: AppTheme.textSecondary.withValues(alpha: 0.16),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Listas de reproducción',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: selectedIds.isEmpty
                                    ? AppTheme.accent.withValues(alpha: 0.07)
                                    : AppTheme.accent.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(50),
                              ),
                              child: Text(
                                '${selectedIds.length} seleccionadas',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: AppTheme.accent,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          itemCount: playlists.length,
                          itemBuilder: (context, index) {
                            final playlist = playlists[index];
                            final selected = selectedIds.contains(playlist.id);
                            final songs = service.resolveSongs(playlist);
                            final firstSong = songs.isEmpty
                                ? null
                                : songs.first;

                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Material(
                                color: selected
                                    ? AppTheme.accent.withValues(alpha: 0.14)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(16),
                                clipBehavior: Clip.antiAlias,
                                child: CheckboxListTile(
                                  value: selected,
                                  onChanged: (value) {
                                    setDialogState(() {
                                      if (value == true) {
                                        selectedIds.add(playlist.id);
                                      } else {
                                        selectedIds.remove(playlist.id);
                                      }
                                    });
                                  },
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  controlAffinity:
                                      ListTileControlAffinity.trailing,
                                  activeColor: AppTheme.accent,
                                  checkColor: colorScheme.onPrimary,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 4,
                                  ),
                                  secondary: _PlaylistArtwork(
                                    playlist: playlist,
                                    firstSong: firstSong,
                                  ),
                                  title: Text(
                                    playlist.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      fontWeight: FontWeight.w500,
                                      color: selected
                                          ? AppTheme.accent
                                          : colorScheme.onSurface,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${playlist.songPaths.length} canciones',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      Divider(
                        height: 1,
                        color: AppTheme.textSecondary.withValues(alpha: 0.16),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () => Navigator.pop(dialogContext),
                              style: TextButton.styleFrom(
                                foregroundColor: AppTheme.textSecondary,
                              ),
                              child: const Text('Cancelar'),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.icon(
                              onPressed: hasChanges
                                  ? () {
                                      Navigator.pop(
                                        dialogContext,
                                        playlists
                                            .where(
                                              (playlist) => selectedIds
                                                  .contains(playlist.id),
                                            )
                                            .toList(),
                                      );
                                    }
                                  : null,
                              style: FilledButton.styleFrom(
                                backgroundColor: AppTheme.accent,
                                foregroundColor: Colors.white,
                                disabledBackgroundColor: AppTheme.accent
                                    .withValues(alpha: 0.3),
                                disabledForegroundColor: Colors.white70,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                              ),
                              icon: const Icon(Icons.check_rounded),
                              label: const Text('Guardar'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );

      if (!context.mounted || selectedPlaylists == null) return;

      // Aplicar cambios: añadir a las nuevas, quitar de las deseleccionadas.
      final toAdd = selectedPlaylists
          .where((p) => !initiallyContaining.contains(p.id))
          .toList();
      final toRemove = playlists
          .where(
            (p) =>
                initiallyContaining.contains(p.id) &&
                !selectedIds.contains(p.id),
          )
          .toList();

      for (final playlist in toAdd) {
        await service.addSongs(playlist, [song]);
      }

      for (final playlist in toRemove) {
        final updatedPaths = List<String>.from(playlist.songPaths)
          ..remove(songPath);
        await service.updateSongs(playlist, updatedPaths);
      }
    } catch (_) {
      return;
    }
  }

  Future<void> _showContextMenu(BuildContext context) async {
    final queue = PlaybackQueue.instance;
    final alreadyQueued = queue.contains(song);
    final queueIsEmpty = queue.isEmpty;

    // [NUEVO] Mismo chequeo que en _onSongTap para el long-press.
    final playlistService = PlaylistService.instance;
    try {
      await playlistService.initialize();
    } catch (_) {}
    final hasPlaylists = playlistService.playlists.isNotEmpty;

    if (!context.mounted) return;

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
                            ScrollingTitle(
                              title: _displayTitle,
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
                // [MODIFICADO] Etiqueta y acción condicionales.
                ListTile(
                  leading: const Icon(Icons.library_music_rounded),
                  title: Text(
                    hasPlaylists ? 'Añadir a playlist' : 'Crear playlist',
                  ),
                  onTap: () => Navigator.pop(
                    sheetContext,
                    hasPlaylists ? 'playlist' : 'create_playlist',
                  ),
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

    if (action == 'create_playlist') {
      await _createPlaylistThenAddSong(context);
      return;
    }

    if (action == 'playlist') {
      await _showAddToPlaylistDialog(context);
      return;
    }

    await _handleQueueAction(action);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final artworkSize = isDesktop ? 50.0 : 46.0;

    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
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
                    ScrollingTitle(
                      title: _displayTitle,
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

class ScrollingTitle extends StatefulWidget {
  final String title;
  final TextStyle? style;
  final TextAlign textAlign;

  const ScrollingTitle({
    super.key,
    required this.title,
    this.style,
    this.textAlign = TextAlign.start,
  });

  @override
  State<ScrollingTitle> createState() => _ScrollingTitleState();
}

class _ScrollingTitleState extends State<ScrollingTitle> {
  final ScrollController _controller = ScrollController();

  Timer? _timer;
  bool _scrolling = false;
  bool _initialized = false;
  double _cycleWidth = 0;

  static const Duration _pauseDuration = Duration(seconds: 5);
  static const double _pixelsPerSecond = 35;
  static const double _gap = 48;

  @override
  void didUpdateWidget(covariant ScrollingTitle oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.title != widget.title || oldWidget.style != widget.style) {
      _timer?.cancel();
      _scrolling = false;
      _initialized = false;
      _cycleWidth = 0;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        if (_controller.hasClients) {
          _controller.jumpTo(0);
        }

        setState(() {});
      });
    }
  }

  void _configure(double textWidth, double availableWidth) {
    if (!mounted || !_controller.hasClients) return;

    final shouldScroll = textWidth > availableWidth + 1;

    if (!shouldScroll) {
      _timer?.cancel();
      _initialized = true;

      if (_scrolling) {
        setState(() {
          _scrolling = false;
        });
      }

      return;
    }

    final newCycleWidth = textWidth + _gap;

    if (_initialized && _scrolling && (_cycleWidth - newCycleWidth).abs() < 1) {
      return;
    }

    _timer?.cancel();
    _cycleWidth = newCycleWidth;
    _initialized = true;

    setState(() {
      _scrolling = true;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;

      _controller.jumpTo(0);
      _startScrolling();
    });
  }

  void _startScrolling() {
    _timer?.cancel();

    if (!mounted || !_controller.hasClients || _cycleWidth <= 0) {
      return;
    }

    Future<void>(() async {
      await Future<void>.delayed(const Duration(milliseconds: 250));

      while (mounted && _controller.hasClients && _scrolling) {
        final duration = Duration(
          milliseconds: (_cycleWidth / _pixelsPerSecond * 1000).round(),
        );

        await _controller.animateTo(
          _controller.offset + _cycleWidth,
          duration: duration,
          curve: Curves.linear,
        );

        if (!mounted || !_controller.hasClients || !_scrolling) return;

        await Future<void>.delayed(_pauseDuration);

        if (!mounted || !_controller.hasClients || !_scrolling) return;

        _controller.jumpTo(0);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textPainter = TextPainter(
          text: TextSpan(text: widget.title, style: widget.style),
          maxLines: 1,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();

        final textWidth = textPainter.width;
        final availableWidth = constraints.maxWidth;

        WidgetsBinding.instance.addPostFrameCallback((_) {
          _configure(textWidth, availableWidth);
        });

        return SizedBox(
          height: (widget.style?.fontSize ?? 14) * 1.7,
          width: double.infinity,
          child: ClipRect(
            child: SingleChildScrollView(
              controller: _controller,
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.title,
                    softWrap: false,
                    maxLines: 1,
                    style: widget.style,
                  ),
                  if (_scrolling) ...[
                    SizedBox(width: _gap),
                    Text(
                      widget.title,
                      softWrap: false,
                      maxLines: 1,
                      style: widget.style,
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PlaylistArtwork extends StatelessWidget {
  final Playlist playlist;
  final Song? firstSong;

  const _PlaylistArtwork({required this.playlist, required this.firstSong});

  @override
  Widget build(BuildContext context) {
    final size = 52.0;
    final artworkPath = firstSong?.artworkPath;

    if (artworkPath != null && artworkPath.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: Image.file(
          File(artworkPath),
          width: size,
          height: size,
          fit: BoxFit.cover,
          cacheWidth: 120,
          cacheHeight: 120,
          errorBuilder: (_, _, _) => _placeholder(),
        ),
      );
    }

    return _placeholder();
  }

  Widget _placeholder() {
    final seed = playlist.name.hashCode;
    final colors = [
      const Color(0xFF6750A4),
      const Color(0xFF4285F4),
      const Color(0xFF40916C),
      const Color(0xFFD65D91),
      const Color(0xFFE58A35),
    ];
    final color = colors[seed.abs() % colors.length];

    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(13),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, Color.lerp(color, Colors.black, 0.65)!],
        ),
      ),
      child: const Icon(
        Icons.queue_music_rounded,
        color: Colors.white,
        size: 27,
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
