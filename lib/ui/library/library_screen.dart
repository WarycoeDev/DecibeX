import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../../core/models/song.dart';
import 'song_list_tile.dart';

enum _LibraryTab { songs, podcasts, playlists, favorites, artists, albums }

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  static const List<_LibraryTabData> _tabs = [
    _LibraryTabData(
      tab: _LibraryTab.songs,
      title: 'Canciones',
      icon: Icons.music_note_rounded,
    ),
    _LibraryTabData(
      tab: _LibraryTab.podcasts,
      title: 'Podcasts',
      icon: Icons.podcasts_rounded,
    ),
    _LibraryTabData(
      tab: _LibraryTab.playlists,
      title: 'Playlists',
      icon: Icons.queue_music_rounded,
    ),
    _LibraryTabData(
      tab: _LibraryTab.favorites,
      title: 'Favoritos',
      icon: Icons.favorite_rounded,
    ),
    _LibraryTabData(
      tab: _LibraryTab.artists,
      title: 'Artistas',
      icon: Icons.person_rounded,
    ),
    _LibraryTabData(
      tab: _LibraryTab.albums,
      title: 'Álbumes',
      icon: Icons.album_rounded,
    ),
  ];

  static const List<Song> _songs = [
    Song(
      title: 'Midnight City',
      artist: 'M83',
      album: 'Hurry Up, We’re Dreaming',
      duration: '4:03',
      icon: Icons.nightlight_round,
      color: Color(0xFF6750A4),
    ),
    Song(
      title: 'After Dark',
      artist: 'Mr.Kitty',
      album: 'Time',
      duration: '4:17',
      icon: Icons.dark_mode_rounded,
      color: Color(0xFF344B70),
      favorite: true,
    ),
    Song(
      title: 'Resonance',
      artist: 'HOME',
      album: 'Odyssey',
      duration: '3:32',
      icon: Icons.waves_rounded,
      color: Color(0xFF357F91),
      favorite: true,
    ),
    Song(
      title: 'Memory Reboot',
      artist: 'VØJ, Narvent',
      album: 'Memory Reboot',
      duration: '3:00',
      icon: Icons.blur_on_rounded,
      color: Color(0xFF8C476C),
    ),
    Song(
      title: 'Snowfall',
      artist: 'Øneheart',
      album: 'Snowfall',
      duration: '2:03',
      icon: Icons.ac_unit_rounded,
      color: Color(0xFF526B99),
      favorite: true,
    ),
    Song(
      title: 'Space Song',
      artist: 'Beach House',
      album: 'Depression Cherry',
      duration: '5:20',
      icon: Icons.nights_stay_rounded,
      color: Color(0xFF53668E),
    ),
    Song(
      title: 'The Less I Know the Better',
      artist: 'Tame Impala',
      album: 'Currents',
      duration: '3:36',
      icon: Icons.graphic_eq_rounded,
      color: Color(0xFF9A654E),
    ),
    Song(
      title: 'A Real Hero',
      artist: 'College, Electric Youth',
      album: 'Drive',
      duration: '4:27',
      icon: Icons.directions_car_rounded,
      color: Color(0xFF426D7C),
    ),
  ];

  _LibraryTab _selectedTab = _LibraryTab.songs;

  List<Song> get _visibleSongs {
    switch (_selectedTab) {
      case _LibraryTab.songs:
        return _songs;

      case _LibraryTab.favorites:
        return _songs.where((song) => song.favorite).toList();

      case _LibraryTab.podcasts:
      case _LibraryTab.playlists:
      case _LibraryTab.artists:
      case _LibraryTab.albums:
        return const [];
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

  String get _sectionSubtitle {
    switch (_selectedTab) {
      case _LibraryTab.songs:
        return '${_visibleSongs.length} canciones en tu colección';
      case _LibraryTab.podcasts:
        return 'Tus programas y episodios';
      case _LibraryTab.playlists:
        return 'Tus listas de reproducción';
      case _LibraryTab.favorites:
        return '${_visibleSongs.length} canciones favoritas';
      case _LibraryTab.artists:
        return 'Artistas de tu colección';
      case _LibraryTab.albums:
        return 'Álbumes de tu colección';
    }
  }

  @override
  Widget build(BuildContext context) {
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
                  _buildHeader(context, isDesktop),
                  SizedBox(height: isDesktop ? 32 : 24),
                  _buildTabs(),
                  SizedBox(height: isDesktop ? 36 : 28),
                  _buildSectionHeader(context, isDesktop),
                  const SizedBox(height: 16),
                  _buildContent(isDesktop),
                ],
              ),
            ),
          ),
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
      ],
    );
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
                if (_selectedTab == _tabs[i].tab) return;

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

  Widget _buildSectionHeader(BuildContext context, bool isDesktop) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
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
                _sectionSubtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
        if (isDesktop &&
            (_selectedTab == _LibraryTab.songs ||
                _selectedTab == _LibraryTab.favorites))
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.surfaceVariant, width: 0.7),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.music_note_rounded,
                  size: 17,
                  color: AppTheme.accent,
                ),
                const SizedBox(width: 8),
                Text(
                  _selectedTab == _LibraryTab.songs
                      ? 'Biblioteca completa'
                      : 'Tus favoritos',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildContent(bool isDesktop) {
    switch (_selectedTab) {
      case _LibraryTab.songs:
      case _LibraryTab.favorites:
        if (_visibleSongs.isEmpty) {
          return _EmptyLibraryState(
            icon: _selectedTab == _LibraryTab.favorites
                ? Icons.favorite_border_rounded
                : Icons.music_off_rounded,
            title: _selectedTab == _LibraryTab.favorites
                ? 'Todavía no tienes favoritos'
                : 'Tu biblioteca está vacía',
            message: _selectedTab == _LibraryTab.favorites
                ? 'Las canciones que marques como favoritas aparecerán aquí.'
                : 'Cuando tengas canciones disponibles, aparecerán aquí.',
          );
        }

        return _buildSongList(isDesktop);

      case _LibraryTab.podcasts:
        return const _EmptyLibraryState(
          icon: Icons.podcasts_rounded,
          title: 'Todavía no hay podcasts',
          message: 'Tus programas y episodios aparecerán aquí.',
        );

      case _LibraryTab.playlists:
        return const _EmptyLibraryState(
          icon: Icons.queue_music_rounded,
          title: 'Todavía no hay playlists',
          message: 'Tus listas de reproducción aparecerán aquí.',
        );

      case _LibraryTab.artists:
        return const _EmptyLibraryState(
          icon: Icons.person_outline_rounded,
          title: 'Todavía no hay artistas',
          message: 'Los artistas de tu colección aparecerán aquí.',
        );

      case _LibraryTab.albums:
        return const _EmptyLibraryState(
          icon: Icons.album_rounded,
          title: 'Todavía no hay álbumes',
          message: 'Los álbumes de tu colección aparecerán aquí.',
        );
    }
  }

  Widget _buildSongList(bool isDesktop) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.surfaceVariant, width: 0.7),
      ),
      child: Column(
        children: [
          for (final song in _visibleSongs)
            SongListTile(
              key: ValueKey(
                '${song.title}_${song.artist}_${_selectedTab.name}',
              ),
              song: song,
              isDesktop: isDesktop,
            ),
        ],
      ),
    );
  }
}

class _LibraryTabData {
  final _LibraryTab tab;
  final String title;
  final IconData icon;

  const _LibraryTabData({
    required this.tab,
    required this.title,
    required this.icon,
  });
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
          curve: Curves.easeOut,
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
