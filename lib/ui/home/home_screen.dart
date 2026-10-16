import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import '../app_theme.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static const List<_Song> _mostPlayed = [
    _Song(
      title: 'Midnight City',
      artist: 'M83',
      icon: Icons.nightlight_round,
      color: Color(0xFF6750A4),
      plays: '128 reproducciones',
    ),
    _Song(
      title: 'After Dark',
      artist: 'Mr.Kitty',
      icon: Icons.dark_mode_rounded,
      color: Color(0xFF344B70),
      plays: '96 reproducciones',
    ),
    _Song(
      title: 'Resonance',
      artist: 'HOME',
      icon: Icons.waves_rounded,
      color: Color(0xFF357F91),
      plays: '84 reproducciones',
    ),
    _Song(
      title: 'Memory Reboot',
      artist: 'VØJ, Narvent',
      icon: Icons.blur_on_rounded,
      color: Color(0xFF8C476C),
      plays: '72 reproducciones',
    ),
    _Song(
      title: 'Snowfall',
      artist: 'Øneheart',
      icon: Icons.ac_unit_rounded,
      color: Color(0xFF526B99),
      plays: '61 reproducciones',
    ),
  ];

  static const List<_Song> _favorites = [
    _Song(
      title: 'After Dark',
      artist: 'Mr.Kitty',
      icon: Icons.dark_mode_rounded,
      color: Color(0xFF344B70),
    ),
    _Song(
      title: 'Resonance',
      artist: 'HOME',
      icon: Icons.waves_rounded,
      color: Color(0xFF357F91),
    ),
    _Song(
      title: 'Snowfall',
      artist: 'Øneheart',
      icon: Icons.ac_unit_rounded,
      color: Color(0xFF526B99),
    ),
    _Song(
      title: 'Memory Reboot',
      artist: 'VØJ, Narvent',
      icon: Icons.blur_on_rounded,
      color: Color(0xFF8C476C),
    ),
  ];

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
                  _buildPopularCarousel(context, isDesktop),
                  SizedBox(height: isDesktop ? 48 : 40),
                  _buildSectionTitle(
                    context,
                    title: 'Tus favoritos',
                    subtitle: 'Tu colección personal',
                    icon: Icons.favorite_rounded,
                    isDesktop: isDesktop,
                  ),
                  SizedBox(height: isDesktop ? 22 : 18),
                  _buildFavoritesList(),
                ],
              ),
            ),
          ),
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

  Widget _buildPopularCarousel(BuildContext context, bool isDesktop) {
    final cardWidth = isDesktop ? 200.0 : 152.0;
    final carouselHeight = isDesktop ? 272.0 : 224.0;

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
          itemCount: _mostPlayed.length,
          separatorBuilder: (_, __) => SizedBox(width: isDesktop ? 20 : 16),
          itemBuilder: (context, index) {
            return _PopularSongCard(
              song: _mostPlayed[index],
              rank: index + 1,
              width: cardWidth,
            );
          },
        ),
      ),
    );
  }

  Widget _buildFavoritesList() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.surfaceVariant, width: 0.7),
      ),
      child: Column(
        children: [
          for (int i = 0; i < _favorites.length; i++) ...[
            _FavoriteSongTile(song: _favorites[i]),
            if (i < _favorites.length - 1)
              Divider(
                height: 1,
                indent: 68,
                endIndent: 16,
                color: AppTheme.surfaceVariant,
              ),
          ],
        ],
      ),
    );
  }
}

class _Song {
  final String title;
  final String artist;
  final IconData icon;
  final Color color;
  final String? plays;

  const _Song({
    required this.title,
    required this.artist,
    required this.icon,
    required this.color,
    this.plays,
  });
}

class _AlbumArtwork extends StatelessWidget {
  final _Song song;
  final double size;
  final double radius;

  const _AlbumArtwork({
    super.key,
    required this.song,
    required this.size,
    this.radius = 14,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [song.color, Color.lerp(song.color, Colors.black, 0.75)!],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -size * 0.15,
            top: -size * 0.15,
            child: Container(
              width: size * 0.65,
              height: size * 0.65,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.07),
              ),
            ),
          ),
          Center(
            child: Icon(
              song.icon,
              color: Colors.white.withValues(alpha: 0.92),
              size: size * 0.38,
            ),
          ),
        ],
      ),
    );
  }
}

class _PopularSongCard extends StatelessWidget {
  final _Song song;
  final int rank;
  final double width;

  const _PopularSongCard({
    required this.song,
    required this.rank,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: _AlbumArtwork(song: song, size: width, radius: 16),
                ),
                Positioned(left: 9, top: 9, child: _RankBadge(rank: rank)),
                const Positioned(right: 8, bottom: 8, child: _PlayButton()),
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
  const _PlayButton();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.accent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () {},
        child: const SizedBox(
          width: 38,
          height: 38,
          child: Icon(Icons.play_arrow_rounded, color: Colors.black, size: 25),
        ),
      ),
    );
  }
}

class _FavoriteSongTile extends StatelessWidget {
  final _Song song;

  const _FavoriteSongTile({required this.song});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: () {},
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            _AlbumArtwork(song: song, size: 46, radius: 10),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
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
            const SizedBox(width: 8),
            const Icon(
              Icons.favorite_rounded,
              color: AppTheme.accent,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
