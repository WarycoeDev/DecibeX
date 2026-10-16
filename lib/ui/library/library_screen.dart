import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../../core/models/song.dart';
import 'song_list_tile.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  static const List<_LibraryCategory> _categories = [
    _LibraryCategory(
      title: 'Podcasts',
      subtitle: 'Tus programas',
      icon: Icons.podcasts_rounded,
      color: Color(0xFF6750A4),
    ),
    _LibraryCategory(
      title: 'Playlists',
      subtitle: 'Listas personales',
      icon: Icons.queue_music_rounded,
      color: Color(0xFF357F91),
    ),
    _LibraryCategory(
      title: 'Favoritos',
      subtitle: 'Canciones favoritas',
      icon: Icons.favorite_rounded,
      color: Color(0xFFB94F73),
    ),
    _LibraryCategory(
      title: 'Artistas',
      subtitle: 'Tu colección de artistas',
      icon: Icons.person_rounded,
      color: Color(0xFF8C7047),
    ),
    _LibraryCategory(
      title: 'Álbumes',
      subtitle: 'Álbumes guardados',
      icon: Icons.album_rounded,
      color: Color(0xFF526B99),
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

  int _selectedCategory = -1;

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
                  SizedBox(height: isDesktop ? 32 : 26),
                  _buildCategories(context, isDesktop),
                  SizedBox(height: isDesktop ? 40 : 32),
                  _buildSongsHeader(context, isDesktop),
                  const SizedBox(height: 16),
                  _buildSongList(isDesktop),
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

  Widget _buildCategories(BuildContext context, bool isDesktop) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = isDesktop
            ? (constraints.maxWidth / 210).floor().clamp(3, 5).toInt()
            : constraints.maxWidth >= 500
            ? 3
            : 2;

        const spacing = 12.0;
        final cardWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (int i = 0; i < _categories.length; i++)
              SizedBox(
                width: cardWidth,
                child: _CategoryCard(
                  category: _categories[i],
                  selected: _selectedCategory == i,
                  compact: !isDesktop,
                  onTap: () {
                    setState(() {
                      _selectedCategory = _selectedCategory == i ? -1 : i;
                    });
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildSongsHeader(BuildContext context, bool isDesktop) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Todas las canciones',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${_songs.length} canciones en tu colección',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
        if (isDesktop)
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
                  'Biblioteca completa',
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

  Widget _buildSongList(bool isDesktop) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.surfaceVariant, width: 0.7),
      ),
      child: Column(
        children: [
          for (int i = 0; i < _songs.length; i++)
            SongListTile(song: _songs[i], isDesktop: isDesktop),
        ],
      ),
    );
  }
}

class _LibraryCategory {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;

  const _LibraryCategory({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
  });
}

class _CategoryCard extends StatelessWidget {
  final _LibraryCategory category;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  const _CategoryCard({
    required this.category,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: selected
          ? category.color.withValues(alpha: 0.16)
          : AppTheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: EdgeInsets.all(compact ? 14 : 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? category.color : AppTheme.surfaceVariant,
              width: selected ? 1.2 : 0.7,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: compact ? 42 : 48,
                height: compact ? 42 : 48,
                decoration: BoxDecoration(
                  color: category.color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  category.icon,
                  color: category.color,
                  size: compact ? 22 : 25,
                ),
              ),
              SizedBox(height: compact ? 12 : 16),
              Text(
                category.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                category.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppTheme.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LibrarySongTile extends StatelessWidget {
  final Song song;
  final int index;
  final bool isDesktop;

  const _LibrarySongTile({
    required this.song,
    required this.index,
    required this.isDesktop,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {},
        hoverColor: AppTheme.surfaceVariant.withValues(alpha: 0.45),
        splashColor: AppTheme.accent.withValues(alpha: 0.12),
        highlightColor: AppTheme.accent.withValues(alpha: 0.08),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isDesktop ? 20 : 12,
            vertical: isDesktop ? 12 : 10,
          ),
          child: Row(
            children: [
              _SongArtwork(song: song, size: isDesktop ? 50 : 46),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.title,
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
              const SizedBox(width: 12),
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
              const SizedBox(width: 8),
              IconButton(
                onPressed: () {},
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
