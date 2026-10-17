import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../../core/models/song.dart';
import '../../core/services/library_scanner.dart';
import 'song_list_tile.dart';

enum _LibraryTab { songs, podcasts, playlists, favorites, artists, albums }

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  static const List<_LibraryTabData> _tabs = [
    _LibraryTabData(_LibraryTab.songs, 'Canciones', Icons.music_note_rounded),
    _LibraryTabData(_LibraryTab.podcasts, 'Podcasts', Icons.podcasts_rounded),
    _LibraryTabData(
      _LibraryTab.playlists,
      'Playlists',
      Icons.queue_music_rounded,
    ),
    _LibraryTabData(_LibraryTab.favorites, 'Favoritos', Icons.favorite_rounded),
    _LibraryTabData(_LibraryTab.artists, 'Artistas', Icons.person_rounded),
    _LibraryTabData(_LibraryTab.albums, 'Álbumes', Icons.album_rounded),
  ];

  final LibraryScanner _scanner = LibraryScanner.instance;

  _LibraryTab _selectedTab = _LibraryTab.songs;

  @override
  void initState() {
    super.initState();
    _scanner.initialize();
  }

  List<Song> _getVisibleSongs() {
    final songs = _scanner.songs;

    switch (_selectedTab) {
      case _LibraryTab.songs:
        return songs;
      case _LibraryTab.favorites:
        return songs.where((song) => song.favorite).toList();
      case _LibraryTab.artists:
        final unique = <String, Song>{};

        for (final song in songs) {
          unique.putIfAbsent(song.artist, () => song);
        }

        return unique.values.toList();
      case _LibraryTab.albums:
        final unique = <String, Song>{};

        for (final song in songs) {
          unique.putIfAbsent('${song.artist}_${song.album}', () => song);
        }

        return unique.values.toList();
      case _LibraryTab.podcasts:
      case _LibraryTab.playlists:
        return [];
    }
  }

  String get _sectionTitle {
    switch (_selectedTab) {
      case _LibraryTab.songs:
        return 'Todas las canciones';
      case _LibraryTab.podcasts:
        return 'Tus podcasts';
      case _LibraryTab.playlists:
        return 'Tus playlists';
      case _LibraryTab.favorites:
        return 'Canciones favoritas';
      case _LibraryTab.artists:
        return 'Tus artistas';
      case _LibraryTab.albums:
        return 'Tus álbumes';
    }
  }

  String _sectionSubtitle(List<Song> songs) {
    switch (_selectedTab) {
      case _LibraryTab.songs:
        return '${_scanner.songCount} canciones en tu colección';
      case _LibraryTab.podcasts:
        return 'Tus programas y episodios';
      case _LibraryTab.playlists:
        return 'Tus listas de reproducción';
      case _LibraryTab.favorites:
        return '${songs.length} canciones favoritas';
      case _LibraryTab.artists:
        return '${songs.length} artistas en tu colección';
      case _LibraryTab.albums:
        return '${songs.length} álbumes en tu colección';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scanner,
      builder: (context, child) {
        final songs = _getVisibleSongs();

        return LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth >= 800;

            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1440),
                child: CustomScrollView(
                  cacheExtent: 600,
                  slivers: [
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        isDesktop ? 36 : 20,
                        isDesktop ? 32 : 24,
                        isDesktop ? 36 : 20,
                        0,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: _buildHeader(context, isDesktop),
                      ),
                    ),
                    SliverPadding(
                      padding: EdgeInsets.only(top: isDesktop ? 32 : 24),
                      sliver: SliverToBoxAdapter(child: _buildTabs()),
                    ),
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        isDesktop ? 36 : 20,
                        isDesktop ? 36 : 28,
                        isDesktop ? 36 : 20,
                        0,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: _buildSectionHeader(context, songs),
                      ),
                    ),
                    if (_scanner.isScanning)
                      const SliverPadding(
                        padding: EdgeInsets.symmetric(horizontal: 20),
                        sliver: SliverToBoxAdapter(
                          child: LinearProgressIndicator(),
                        ),
                      ),
                    if (_scanner.error != null)
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                        sliver: SliverToBoxAdapter(child: _buildError()),
                      ),
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        isDesktop ? 36 : 20,
                        16,
                        isDesktop ? 36 : 20,
                        36,
                      ),
                      sliver: _buildContent(songs, isDesktop),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, bool isDesktop) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'TU COLECCIÓN',
          style: theme.textTheme.labelMedium?.copyWith(
            color: AppTheme.accent,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.6,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Tu biblioteca',
          style:
              (isDesktop
                      ? theme.textTheme.headlineLarge
                      : theme.textTheme.headlineSmall)
                  ?.copyWith(fontWeight: FontWeight.bold, letterSpacing: -0.8),
        ),
        const SizedBox(height: 8),
        Text(
          'Toda tu música, organizada en un solo lugar.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              _scanner.lastScan == null
                  ? 'Escaneo pendiente'
                  : 'Último escaneo: ${_formatLastScan(_scanner.lastScan!)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
            OutlinedButton.icon(
              onPressed: _scanner.isScanning ? null : _scanner.scan,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Escanear ahora'),
            ),
          ],
        ),
      ],
    );
  }

  String _formatLastScan(DateTime date) {
    final local = date.toLocal();
    final datePart =
        '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/'
        '${local.year}';
    final timePart =
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';

    return '$datePart $timePart';
  }

  Widget _buildTabs() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (int i = 0; i < _tabs.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            _LibraryTabButton(
              data: _tabs[i],
              selected: _selectedTab == _tabs[i].tab,
              onTap: () {
                setState(() {
                  _selectedTab = _tabs[i].tab;
                });
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, List<Song> songs) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _sectionTitle,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _sectionSubtitle(songs),
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

  Widget _buildContent(List<Song> songs, bool isDesktop) {
    if (_selectedTab == _LibraryTab.podcasts) {
      return const SliverToBoxAdapter(
        child: _EmptyLibraryState(
          icon: Icons.podcasts_rounded,
          title: 'Todavía no hay podcasts',
          message: 'Tus programas y episodios aparecerán aquí.',
        ),
      );
    }

    if (_selectedTab == _LibraryTab.playlists) {
      return const SliverToBoxAdapter(
        child: _EmptyLibraryState(
          icon: Icons.queue_music_rounded,
          title: 'Todavía no hay playlists',
          message: 'Tus listas de reproducción aparecerán aquí.',
        ),
      );
    }

    if (songs.isEmpty) {
      final favorites = _selectedTab == _LibraryTab.favorites;

      return SliverToBoxAdapter(
        child: _EmptyLibraryState(
          icon: favorites
              ? Icons.favorite_border_rounded
              : Icons.music_off_rounded,
          title: favorites
              ? 'Todavía no tienes favoritos'
              : 'Tu biblioteca está vacía',
          message: favorites
              ? 'Marca canciones como favoritas para verlas aquí.'
              : 'Agrega directorios en Configuración > Biblioteca y escanea tus archivos.',
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final song = songs[index];
          final isFirst = index == 0;
          final isLast = index == songs.length - 1;

          return RepaintBoundary(
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.surface,
                border: Border(
                  left: BorderSide(color: AppTheme.surfaceVariant, width: 0.7),
                  right: BorderSide(color: AppTheme.surfaceVariant, width: 0.7),
                  top: isFirst
                      ? BorderSide(color: AppTheme.surfaceVariant, width: 0.7)
                      : BorderSide.none,
                  bottom: BorderSide(
                    color: AppTheme.surfaceVariant,
                    width: 0.7,
                  ),
                ),
                borderRadius: BorderRadius.vertical(
                  top: isFirst ? const Radius.circular(18) : Radius.zero,
                  bottom: isLast ? const Radius.circular(18) : Radius.zero,
                ),
              ),
              child: SongListTile(
                key: ValueKey(song.filePath),
                song: song,
                isDesktop: isDesktop,
                onFavoriteChanged: (favorite) {
                  _scanner.setFavorite(song, favorite);
                },
              ),
            ),
          );
        },
        childCount: songs.length,
        addAutomaticKeepAlives: false,
        addRepaintBoundaries: false,
      ),
    );
  }

  Widget _buildError() {
    return Material(
      color: Theme.of(context).colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _scanner.error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LibraryTabData {
  final _LibraryTab tab;
  final String title;
  final IconData icon;

  const _LibraryTabData(this.tab, this.title, this.icon);
}

class _LibraryTabButton extends StatelessWidget {
  final _LibraryTabData data;
  final bool selected;
  final VoidCallback onTap;

  const _LibraryTabButton({
    super.key,
    required this.data,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: selected
          ? AppTheme.accent.withValues(alpha: 0.14)
          : AppTheme.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppTheme.accent : AppTheme.surfaceVariant,
              width: selected ? 1.2 : 0.7,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                data.icon,
                size: 18,
                color: selected ? AppTheme.accent : AppTheme.textSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                data.title,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: selected
                      ? AppTheme.accent
                      : theme.colorScheme.onSurface,
                  fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyLibraryState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _EmptyLibraryState({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.surfaceVariant, width: 0.7),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(icon, size: 30, color: AppTheme.accent),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppTheme.textSecondary,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
