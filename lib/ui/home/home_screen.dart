import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../core/models/song.dart';
import '../../core/services/library_scanner.dart';
import '../../core/services/statistics_service.dart';
import '../library/song_list_tile.dart';
import '../../core/services/playback_queue.dart';
import '../../core/services/playback_service.dart';

enum _LayoutSize { compact, medium, expanded }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const String _settingsFileName = 'settings.decibex';

  final LibraryScanner _scanner = LibraryScanner.instance;
  final StatisticsService _stats = StatisticsService.instance;

  bool _hasDirectories = false;

  @override
  void initState() {
    super.initState();
    _scanner.initialize();
    _stats.init();
    _loadHasDirectories();
  }

  Future<Directory> _getSettingsDirectory() async {
    if (Platform.isAndroid) {
      final externalDirectory = await getExternalStorageDirectory();

      if (externalDirectory != null) {
        return Directory('${externalDirectory.path}/data');
      }
    }

    return getApplicationSupportDirectory();
  }

  Future<File> _getSettingsFile() async {
    final directory = await _getSettingsDirectory();

    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    return File('${directory.path}/$_settingsFileName');
  }

  Future<void> _loadHasDirectories() async {
    bool hasDirs = false;

    try {
      final file = await _getSettingsFile();

      if (await file.exists()) {
        final content = await file.readAsString();

        if (content.trim().isNotEmpty) {
          final decoded = jsonDecode(content);

          if (decoded is Map<String, dynamic>) {
            final dirs = decoded['scanDirectories'];
            if (dirs is List && dirs.whereType<String>().isNotEmpty) {
              hasDirs = true;
            }
          }
        }
      }
    } catch (_) {
      hasDirs = false;
    }

    if (!mounted) return;

    setState(() {
      _hasDirectories = hasDirs;
    });
  }

  List<Song> _buildMostPlayed() {
    if (!_hasDirectories) return const [];

    final songs = _scanner.songs;
    if (songs.isEmpty) return const [];

    final played = <MapEntry<Song, int>>[];
    for (final song in songs) {
      if (song.isPodcast) continue;
      final count = _stats.getPlayCount(song);
      if (count > 0) {
        played.add(MapEntry(song, count));
      }
    }

    if (played.isEmpty) return const [];

    played.sort((a, b) {
      final byCount = b.value.compareTo(a.value);
      if (byCount != 0) return byCount;
      return a.key.title.toLowerCase().compareTo(b.key.title.toLowerCase());
    });

    return played.take(10).map((e) => e.key).toList();
  }

  Future<void> _playMostPlayedSong(Song song) async {
    final queue = PlaybackQueue.instance;
    final playback = PlaybackService.instance;

    if (!queue.contains(song)) {
      queue.add(song);
    }

    await playback.playSongFromQueue(song);
  }

  Future<void> _playAllMostPlayed(List<Song> songs) async {
    if (songs.isEmpty) return;

    final queue = PlaybackQueue.instance;
    final playback = PlaybackService.instance;

    if (queue.isNotEmpty) {
      final action = await _confirmQueueOverwrite();
      if (!mounted || action != 'replace') return;
    }

    queue.clear();
    for (final song in songs) {
      queue.add(song);
    }

    await playback.playQueue();
  }

  Future<void> _addAllMostPlayedToQueue(List<Song> songs) async {
    if (songs.isEmpty) return;

    final queue = PlaybackQueue.instance;
    final playback = PlaybackService.instance;

    if (queue.isNotEmpty) {
      final action = await _confirmQueueOverwrite();
      if (!mounted || action != 'replace') return;
    }

    queue.clear();
    for (final song in songs) {
      queue.add(song);
    }

    await playback.playQueue();

    if (!mounted) return;
    await playback.pause();
  }

  Future<void> _playAllFavorites(List<Song> favorites) async {
    if (favorites.isEmpty) return;

    final queue = PlaybackQueue.instance;
    final playback = PlaybackService.instance;

    if (queue.isNotEmpty) {
      final action = await _confirmQueueOverwrite();
      if (!mounted || action != 'replace') return;
    }

    queue.clear();
    for (final song in favorites) {
      queue.add(song);
    }

    await playback.playQueue();
  }

  Future<void> _addAllFavoritesToQueue(List<Song> favorites) async {
    if (favorites.isEmpty) return;

    final queue = PlaybackQueue.instance;
    final playback = PlaybackService.instance;

    if (queue.isNotEmpty) {
      final action = await _confirmQueueOverwrite();
      if (!mounted || action != 'replace') return;
    }

    queue.clear();
    for (final song in favorites) {
      queue.add(song);
    }

    await playback.playQueue();

    if (!mounted) return;
    await playback.pause();
  }

  Future<String?> _confirmQueueOverwrite() {
    return showModalBottomSheet<String>(
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
                ListTile(
                  leading: const Icon(Icons.playlist_remove_rounded),
                  title: Text(context.l10n.overwriteQueue),
                  onTap: () => Navigator.pop(sheetContext, 'replace'),
                ),
                ListTile(
                  leading: const Icon(Icons.close_rounded),
                  title: Text(context.l10n.cancel),
                  onTap: () => Navigator.pop(sheetContext, 'cancel'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  _LayoutSize _layoutFor(double width) {
    if (width < 400) return _LayoutSize.compact;
    if (width < 800) return _LayoutSize.medium;
    return _LayoutSize.expanded;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_scanner, _stats]),
      builder: (context, child) {
        final favorites = _scanner.orderFavorites(
          _scanner.songs.where((song) => song.favorite),
        );
        final mostPlayed = _buildMostPlayed();

        return LayoutBuilder(
          builder: (context, constraints) {
            final layout = _layoutFor(constraints.maxWidth);
            final isCompact = layout == _LayoutSize.compact;

            final horizontal = switch (layout) {
              _LayoutSize.compact => 16.0,
              _LayoutSize.medium => 20.0,
              _LayoutSize.expanded => 36.0,
            };
            final top = switch (layout) {
              _LayoutSize.compact => 18.0,
              _LayoutSize.medium => 24.0,
              _LayoutSize.expanded => 32.0,
            };

            return SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(horizontal, top, horizontal, 32),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1440),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildWelcome(context, layout),
                        SizedBox(
                          height: isCompact
                              ? 24
                              : (layout == _LayoutSize.expanded ? 40 : 36),
                        ),
                        _buildMostPlayedHeader(context, mostPlayed, layout),
                        SizedBox(
                          height: isCompact
                              ? 16
                              : (layout == _LayoutSize.expanded ? 24 : 20),
                        ),
                        _buildPopularCarousel(context, mostPlayed, layout),
                        SizedBox(
                          height: isCompact
                              ? 28
                              : (layout == _LayoutSize.expanded ? 48 : 40),
                        ),
                        _buildFavoritesHeader(context, favorites, layout),
                        SizedBox(
                          height: isCompact
                              ? 16
                              : (layout == _LayoutSize.expanded ? 22 : 18),
                        ),
                        _buildFavoritesList(favorites, layout),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildWelcome(BuildContext context, _LayoutSize layout) {
    final theme = Theme.of(context);
    final isDesktop = layout == _LayoutSize.expanded;
    final isCompact = layout == _LayoutSize.compact;

    final headlineStyle =
        (isDesktop
                ? theme.textTheme.headlineLarge
                : theme.textTheme.headlineSmall)
            ?.copyWith(
              fontWeight: FontWeight.bold,
              letterSpacing: -0.8,
              height: 1.15,
            );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.yourMusicalSpace,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelMedium?.copyWith(
            color: AppTheme.accent,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.6,
          ),
        ),
        SizedBox(height: isCompact ? 8 : 10),
        Text(
          context.l10n.yourMusicYourWay,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: headlineStyle,
        ),
        SizedBox(height: isCompact ? 6 : 8),
        Text(
          context.l10n.everythingYouLove,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppTheme.textSecondary,
          ),
        ),
      ],
    );
  }

  /// Header genérico con icono, título, subtítulo y controles a la derecha.
  Widget _buildSectionHeader(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required List<Widget> actions,
    required _LayoutSize layout,
  }) {
    final theme = Theme.of(context);
    final isDesktop = layout == _LayoutSize.expanded;
    final isCompact = layout == _LayoutSize.compact;

    final boxSize = isDesktop ? 44.0 : (isCompact ? 36.0 : 40.0);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: boxSize,
          height: boxSize,
          decoration: BoxDecoration(
            color: AppTheme.surfaceVariant,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: AppTheme.accent, size: boxSize * 0.52),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
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
        ...actions,
      ],
    );
  }

  List<Widget> _buildCollectionActions({
    required _LayoutSize layout,
    required bool isEmpty,
    required VoidCallback? onAddAll,
    required VoidCallback? onPlayAll,
  }) {
    final isDesktop = layout == _LayoutSize.expanded;
    final isCompact = layout == _LayoutSize.compact;

    return [
      IconButton.filledTonal(
        tooltip: context.l10n.addAllToQueue,
        onPressed: isEmpty ? null : onAddAll,
        icon: const Icon(Icons.queue_music_rounded),
      ),
      const SizedBox(width: 8),
      if (isCompact)
        IconButton.filled(
          tooltip: context.l10n.playAll,
          onPressed: isEmpty ? null : onPlayAll,
          icon: const Icon(Icons.play_arrow_rounded),
        )
      else
        FilledButton.icon(
          onPressed: isEmpty ? null : onPlayAll,
          icon: const Icon(Icons.play_arrow_rounded),
          label: Text(isDesktop ? context.l10n.playAll : context.l10n.play),
        ),
    ];
  }

  Widget _buildMostPlayedHeader(
    BuildContext context,
    List<Song> songs,
    _LayoutSize layout,
  ) {
    return _buildSectionHeader(
      context,
      title: context.l10n.mostPlayed,
      subtitle: context.l10n.mostPlayedSubtitle,
      icon: Icons.trending_up_rounded,
      layout: layout,
      actions: _buildCollectionActions(
        layout: layout,
        isEmpty: songs.isEmpty,
        onAddAll: () => _addAllMostPlayedToQueue(songs),
        onPlayAll: () => _playAllMostPlayed(songs),
      ),
    );
  }

  Widget _buildFavoritesHeader(
    BuildContext context,
    List<Song> favorites,
    _LayoutSize layout,
  ) {
    return _buildSectionHeader(
      context,
      title: context.l10n.yourFavorites,
      subtitle: context.l10n.yourFavoritesSubtitle,
      icon: Icons.favorite_rounded,
      layout: layout,
      actions: _buildCollectionActions(
        layout: layout,
        isEmpty: favorites.isEmpty,
        onAddAll: () => _addAllFavoritesToQueue(favorites),
        onPlayAll: () => _playAllFavorites(favorites),
      ),
    );
  }

  Widget _buildPopularCarousel(
    BuildContext context,
    List<Song> songs,
    _LayoutSize layout,
  ) {
    if (songs.isEmpty) {
      final String title;
      final String message;
      final IconData icon;

      if (!_hasDirectories) {
        icon = Icons.folder_open_rounded;
        title = context.l10n.configureLibrary;
        message = context.l10n.configureLibrarySubtitle;
      } else if (_scanner.songs.isEmpty) {
        icon = Icons.music_off_rounded;
        title = context.l10n.noSongsYet;
        message = context.l10n.scanLibrarySubtitle;
      } else {
        icon = Icons.trending_up_rounded;
        title = context.l10n.noPlayedSongs;
        message = context.l10n.playSongToAppear;
      }

      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.surfaceVariant, width: 0.7),
        ),
        child: Column(
          children: [
            Icon(icon, size: 32, color: AppTheme.textSecondary),
            const SizedBox(height: 10),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ),
      );
    }

    final double cardWidth;
    final double gap;
    switch (layout) {
      case _LayoutSize.compact:
        final available = MediaQuery.sizeOf(context).width - 32;
        cardWidth = ((available - 12) / 2.15).clamp(108.0, 140.0);
        gap = 12;
      case _LayoutSize.medium:
        cardWidth = 152;
        gap = 16;
      case _LayoutSize.expanded:
        cardWidth = 200;
        gap = 20;
    }

    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final textBlockHeight = 10 + (22 + 3 + 18) * textScale + 4;
    final carouselHeight = cardWidth + textBlockHeight;

    return SizedBox(
      height: carouselHeight,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          dragDevices: {
            PointerDeviceKind.touch,
            PointerDeviceKind.mouse,
            PointerDeviceKind.trackpad,
            PointerDeviceKind.stylus,
            PointerDeviceKind.invertedStylus,
          },
        ),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: songs.length,
          separatorBuilder: (_, index) => SizedBox(width: gap),
          itemBuilder: (context, index) {
            final song = songs[index];
            return _PopularSongCard(
              song: song,
              rank: index + 1,
              width: cardWidth,
              playCount: _stats.getPlayCount(song),
              // [MODIFICADO] Abre el mismo bottom sheet de acciones que un
              // SongListTile normal en lugar de reproducir directamente.
              onTap: () => SongListTile.showSongActions(context, song),
            );
          },
        ),
      ),
    );
  }

  Widget _buildFavoritesList(List<Song> favorites, _LayoutSize layout) {
    if (favorites.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.surfaceVariant, width: 0.7),
        ),
        child: Column(
          children: [
            Icon(
              Icons.favorite_border_rounded,
              size: 36,
              color: AppTheme.textSecondary,
            ),
            const SizedBox(height: 12),
            Text(
              context.l10n.noFavoritesYet,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              context.l10n.markFavoritesSubtitle,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.surfaceVariant, width: 0.7),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final song in favorites)
            SongListTile(
              key: ValueKey(song.filePath),
              song: song,
              isDesktop: layout == _LayoutSize.expanded,
              onFavoriteChanged: (favorite) {
                _scanner.setFavorite(song, favorite);
              },
            ),
        ],
      ),
    );
  }
}

class _PopularSongCard extends StatelessWidget {
  final Song song;
  final int rank;
  final double width;
  final int playCount;
  final VoidCallback onTap;

  const _PopularSongCard({
    required this.song,
    required this.rank,
    required this.width,
    required this.playCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: SizedBox(
        width: width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: width,
              height: width,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: _SongArtwork(song: song, size: width),
                  ),
                  Positioned(left: 9, top: 9, child: _RankBadge(rank: rank)),
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: _PlayButton(
                      onTap: onTap,
                      size: width < 130 ? 34 : 38,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              song.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 3),
            Row(
              children: [
                Expanded(
                  child: Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
                if (playCount > 0) ...[
                  const SizedBox(width: 4),
                  Text(
                    '$playCount',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.play_arrow_rounded,
                    size: 12,
                    color: AppTheme.textSecondary,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RankBadge extends StatelessWidget {
  final int rank;

  const _RankBadge({required this.rank});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '#$rank',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  final VoidCallback onTap;
  final double size;

  const _PlayButton({required this.onTap, this.size = 38});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.primary,
      shape: const CircleBorder(),
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.3),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            Icons.play_arrow_rounded,
            color: colorScheme.onPrimary,
            size: size * 0.66,
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
        child: SizedBox(
          width: size,
          height: size,
          child: Image.file(
            File(artworkPath),
            fit: BoxFit.cover,
            alignment: Alignment.center,
            // Solo limitamos el ancho; el alto se calcula
            // proporcionalmente para no deformar la imagen.
            cacheWidth: cacheSize,
            filterQuality: FilterQuality.low,
            errorBuilder: (context, error, stackTrace) => _placeholder(),
          ),
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
