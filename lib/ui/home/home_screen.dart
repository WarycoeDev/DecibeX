import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../app_theme.dart';
import '../../core/models/song.dart';
import '../../core/services/library_scanner.dart';
import '../../core/services/statistics_service.dart';
import '../library/song_list_tile.dart';
import '../../core/services/playback_queue.dart';
import '../../core/services/playback_service.dart';

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
    // Si no hay directorios configurados, no mostrar nada.
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
                  title: const Text('Sobrescribir cola'),
                  onTap: () => Navigator.pop(sheetContext, 'replace'),
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
            final isDesktop = constraints.maxWidth >= 800;

            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                isDesktop ? 36 : 20,
                isDesktop ? 32 : 24,
                isDesktop ? 36 : 20,
                36,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1440),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildWelcome(context, isDesktop),
                      SizedBox(height: isDesktop ? 40 : 36),
                      _buildSectionTitle(
                        context,
                        title: 'Más escuchadas',
                        subtitle: 'Las canciones que más suenan',
                        icon: Icons.trending_up_rounded,
                        isDesktop: isDesktop,
                      ),
                      SizedBox(height: isDesktop ? 24 : 20),
                      _buildPopularCarousel(context, mostPlayed, isDesktop),
                      SizedBox(height: isDesktop ? 48 : 40),
                      Row(
                        children: [
                          Expanded(
                            child: _buildSectionTitle(
                              context,
                              title: 'Tus favoritos',
                              subtitle: 'Tu colección personal',
                              icon: Icons.favorite_rounded,
                              isDesktop: isDesktop,
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filledTonal(
                            tooltip: 'Agregar todos a la cola',
                            onPressed: favorites.isEmpty
                                ? null
                                : () => _addAllFavoritesToQueue(favorites),
                            icon: const Icon(Icons.queue_music_rounded),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            onPressed: favorites.isEmpty
                                ? null
                                : () => _playAllFavorites(favorites),
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: Text(
                              isDesktop ? 'Reproducir todo' : 'Reproducir',
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: isDesktop ? 22 : 18),
                      _buildFavoritesList(favorites, isDesktop),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildWelcome(BuildContext context, bool isDesktop) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'TU ESPACIO MUSICAL',
          style: theme.textTheme.labelMedium?.copyWith(
            color: AppTheme.accent,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.6,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Tu música, a tu manera.',
          style:
              (isDesktop
                      ? theme.textTheme.headlineLarge
                      : theme.textTheme.headlineSmall)
                  ?.copyWith(fontWeight: FontWeight.bold, letterSpacing: -0.8),
        ),
        const SizedBox(height: 8),
        Text(
          'Todo lo que te gusta escuchar, en un solo lugar.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppTheme.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isDesktop,
  }) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Container(
          width: isDesktop ? 44 : 40,
          height: isDesktop ? 44 : 40,
          decoration: BoxDecoration(
            color: AppTheme.surfaceVariant,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: AppTheme.accent, size: isDesktop ? 23 : 21),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPopularCarousel(
    BuildContext context,
    List<Song> songs,
    bool isDesktop,
  ) {
    if (songs.isEmpty) {
      final String title;
      final String message;
      final IconData icon;

      if (!_hasDirectories) {
        icon = Icons.folder_open_rounded;
        title = 'Configura tu biblioteca';
        message =
            'Agrega una carpeta en Configuración > Biblioteca para empezar.';
      } else if (_scanner.songs.isEmpty) {
        icon = Icons.music_off_rounded;
        title = 'Aún no hay canciones';
        message = 'Escanea tu biblioteca para empezar a escuchar música.';
      } else {
        icon = Icons.trending_up_rounded;
        title = 'Aún no hay canciones escuchadas';
        message =
            'Reproduce una canción al menos 5 segundos para que aparezca aquí.';
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

    final cardWidth = isDesktop ? 200.0 : 152.0;
    final carouselHeight = cardWidth + 10 + 22 + 3 + 18 + 4;

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
          separatorBuilder: (_, index) => SizedBox(width: isDesktop ? 20 : 16),
          itemBuilder: (context, index) {
            final song = songs[index];
            return _PopularSongCard(
              song: song,
              rank: index + 1,
              width: cardWidth,
              playCount: _stats.getPlayCount(song),
              onTap: () => _playMostPlayedSong(song),
            );
          },
        ),
      ),
    );
  }

  Widget _buildFavoritesList(List<Song> favorites, bool isDesktop) {
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
              'Todavía no tienes favoritos',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              'Marca canciones como favoritas para verlas aquí.',
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
      child: Column(
        children: [
          for (final song in favorites)
            SongListTile(
              key: ValueKey(song.filePath),
              song: song,
              isDesktop: isDesktop,
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
                    right: 8,
                    bottom: 8,
                    child: _PlayButton(onTap: onTap),
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
                  const SizedBox(width: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
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

  const _PlayButton({required this.onTap});

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
          width: 38,
          height: 38,
          child: Icon(
            Icons.play_arrow_rounded,
            color: colorScheme.onPrimary,
            size: 25,
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
