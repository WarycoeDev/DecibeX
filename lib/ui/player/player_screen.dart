import 'dart:async';
import 'dart:io';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart' show LoopMode;

import '../app_theme.dart';
import '../../core/services/playback_service.dart';
import '../../core/services/playback_queue.dart';
import '../../core/models/song.dart';
import '../../core/services/library_scanner.dart';

enum _PlaybackMenuAction { toggleShuffle, repeatOff, repeatOne, repeatAll }

enum _LayoutSize { compact, medium, expanded }

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  Duration? _dragPosition;
  Duration? _pendingSeekPosition;
  String? _pendingSeekSongTitle;
  String? _pendingSeekSongArtist;

  @override
  void initState() {
    super.initState();
    PlaybackService.instance.addListener(_onPlaybackChanged);
  }

  @override
  void dispose() {
    PlaybackService.instance.removeListener(_onPlaybackChanged);
    super.dispose();
  }

  _LayoutSize _layoutFor(double width) {
    if (width < 400) return _LayoutSize.compact;
    if (width < 700) return _LayoutSize.medium;
    return _LayoutSize.expanded;
  }

  void _onPlaybackChanged() {
    final playback = PlaybackService.instance;
    final pendingPosition = _pendingSeekPosition;

    if (pendingPosition == null) return;

    final song = playback.currentSong;

    if (song == null ||
        song.title != _pendingSeekSongTitle ||
        song.artist != _pendingSeekSongArtist) {
      if (mounted) {
        setState(() {
          _pendingSeekPosition = null;
          _pendingSeekSongTitle = null;
          _pendingSeekSongArtist = null;
          _dragPosition = null;
        });
      }
      return;
    }

    final difference =
        (playback.position.inMilliseconds - pendingPosition.inMilliseconds)
            .abs();

    if (difference <= 1000 && mounted) {
      setState(() {
        _pendingSeekPosition = null;
        _pendingSeekSongTitle = null;
        _pendingSeekSongArtist = null;
      });
    }
  }

  String _formatDuration(Duration duration) {
    return '${duration.inMinutes}:${duration.inSeconds.remainder(60).toString().padLeft(2, '0')}';
  }

  void _closePlayer(BuildContext context) {
    PlaybackService.instance.stop();
    PlaybackQueue.instance.clear();
    Navigator.of(context).maybePop();
  }

  double _statusBarHeight(BuildContext context) {
    return MediaQueryData.fromView(View.of(context)).padding.top;
  }

  bool _isFavorite(Song? song) {
    if (song?.filePath == null || song!.filePath!.isEmpty) return false;

    return LibraryScanner.instance.songs.any(
      (item) => item.filePath == song.filePath && item.favorite,
    );
  }

  void _toggleFavorite(Song song) {
    unawaited(LibraryScanner.instance.setFavorite(song, !_isFavorite(song)));
  }

  void _setRepeatMode(LoopMode mode) {
    unawaited(PlaybackService.instance.setRepeatMode(mode));
  }

  void _handlePlaybackMenuSelection(_PlaybackMenuAction action) {
    final playback = PlaybackService.instance;

    switch (action) {
      case _PlaybackMenuAction.toggleShuffle:
        unawaited(playback.toggleShuffle());
        break;
      case _PlaybackMenuAction.repeatOff:
        _setRepeatMode(LoopMode.off);
        break;
      case _PlaybackMenuAction.repeatOne:
        _setRepeatMode(LoopMode.one);
        break;
      case _PlaybackMenuAction.repeatAll:
        _setRepeatMode(LoopMode.all);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceVariant,
      body: SafeArea(
        top: false,
        child: AnimatedBuilder(
          animation: Listenable.merge([
            PlaybackService.instance,
            PlaybackQueue.instance,
            LibraryScanner.instance,
          ]),
          builder: (context, child) {
            final playback = PlaybackService.instance;
            final song = playback.currentSong;

            if (song == null) return _buildEmptyPlayer(context);

            final layout = _layoutFor(MediaQuery.sizeOf(context).width);

            if (layout == _LayoutSize.expanded) {
              return _buildDesktopLayout(context, song, playback);
            }

            return _buildMobileLayout(context, song, playback, layout);
          },
        ),
      ),
    );
  }

  Widget _buildMobileLayout(
    BuildContext context,
    Song song,
    PlaybackService playback,
    _LayoutSize layout,
  ) {
    final screenSize = MediaQuery.sizeOf(context);
    final isCompact = layout == _LayoutSize.compact;

    final horizontalPadding = isCompact ? 18.0 : 24.0;

    // En compact reducimos el máximo del artwork para que quepan controles,
    // progreso y menú inferior sin scroll en la mayoría de Android pequeños.
    final artworkMax = isCompact ? 300.0 : 360.0;
    final artworkMin = isCompact ? 180.0 : 220.0;

    final artworkSize = (screenSize.width - horizontalPadding * 2).clamp(
      artworkMin,
      artworkMax,
    );

    final position = _dragPosition ?? _pendingSeekPosition ?? playback.position;

    return Column(
      children: [
        SizedBox(height: _statusBarHeight(context)),
        _buildHeader(context),
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: isCompact ? 8 : 12,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(height: isCompact ? 4 : 8),
                    _buildArtwork(song.artworkPath, artworkSize),
                    SizedBox(height: isCompact ? 22 : 32),
                    _buildSongInformation(
                      song.title,
                      song.artist,
                      layout: layout,
                    ),
                    SizedBox(height: isCompact ? 20 : 30),
                    _buildProgress(position, playback.duration),
                    SizedBox(height: isCompact ? 14 : 20),
                    _buildMainControls(
                      isPlaying: playback.isPlaying,
                      canPlayPrevious: playback.canPlayPrevious,
                      canPlayNext: playback.canPlayNext,
                      onPrevious: playback.playPrevious,
                      onPlayPause: playback.togglePlayPause,
                      onNext: playback.playNext,
                      layout: layout,
                    ),
                    SizedBox(height: isCompact ? 24 : 44),
                    _buildBottomMenu(
                      isFavorite: _isFavorite(song),
                      onFavoritePressed: () => _toggleFavorite(song),
                      shuffleEnabled: playback.shuffleEnabled,
                      repeatMode: playback.repeatMode,
                    ),
                    SizedBox(height: isCompact ? 12 : 24),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopLayout(
    BuildContext context,
    Song song,
    PlaybackService playback,
  ) {
    final screenSize = MediaQuery.sizeOf(context);
    final position = _dragPosition ?? _pendingSeekPosition ?? playback.position;
    final artworkSize = (screenSize.height * 0.39).clamp(220.0, 360.0);

    return Column(
      children: [
        SizedBox(height: _statusBarHeight(context)),
        _buildHeader(context),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 8, 28, 24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 6,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _buildArtwork(song.artworkPath, artworkSize),
                              const SizedBox(height: 24),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                ),
                                child: _buildSongInformation(
                                  song.title,
                                  song.artist,
                                  layout: _LayoutSize.expanded,
                                ),
                              ),
                              const SizedBox(height: 24),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 28,
                                ),
                                child: _buildProgress(
                                  position,
                                  playback.duration,
                                ),
                              ),
                              const SizedBox(height: 18),
                              _buildDesktopControls(
                                song: song,
                                playback: playback,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 28),
                Expanded(flex: 5, child: _buildDesktopQueue(playback)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopControls({
    required Song song,
    required PlaybackService playback,
  }) {
    final favorite = _isFavorite(song);
    final shuffle = playback.shuffleEnabled;
    final repeat = playback.repeatMode;
    final active = shuffle || repeat != LoopMode.off;

    final repeatIcon = switch (repeat) {
      LoopMode.one => Icons.repeat_one_rounded,
      LoopMode.all => Icons.repeat_rounded,
      LoopMode.off => Icons.repeat_rounded,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            tooltip: favorite ? 'Quitar de favoritos' : 'Añadir a favoritos',
            onPressed: () => _toggleFavorite(song),
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                favorite
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                key: ValueKey<bool>(favorite),
                size: 27,
                color: favorite ? AppTheme.accent : AppTheme.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: _buildMainControls(
              isPlaying: playback.isPlaying,
              canPlayPrevious: playback.canPlayPrevious,
              canPlayNext: playback.canPlayNext,
              onPrevious: playback.playPrevious,
              onPlayPause: playback.togglePlayPause,
              onNext: playback.playNext,
              layout: _LayoutSize.expanded,
            ),
          ),
          IconButton(
            tooltip: 'Opciones de reproducción',
            onPressed: () => _showPlaybackOptionsSheet(
              shuffleEnabled: shuffle,
              repeatMode: repeat,
            ),
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                shuffle ? Icons.shuffle_rounded : repeatIcon,
                key: ValueKey<String>('$shuffle-$repeat'),
                size: 27,
                color: active ? AppTheme.accent : AppTheme.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopQueue(PlaybackService playback) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        PlaybackQueue.instance,
        PlaybackService.instance,
      ]),
      builder: (context, _) {
        final queue = PlaybackQueue.instance.songs;
        final currentSong = playback.currentSong;

        final currentIndex = queue.indexWhere(
          (item) => _isCurrentQueueSong(currentSong, item),
        );

        final colors = Theme.of(context).colorScheme;

        return Container(
          decoration: BoxDecoration(
            color: AppTheme.surfaceVariant,
            borderRadius: BorderRadius.circular(20),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
                child: Row(
                  children: [
                    Icon(
                      Icons.queue_music_rounded,
                      color: colors.primary,
                      size: 27,
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Cola de reproducción',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Text(
                      '${queue.length} canciones',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: queue.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.queue_music_rounded,
                              size: 54,
                              color: AppTheme.textSecondary,
                            ),
                            const SizedBox(height: 12),
                            const Text('La cola está vacía'),
                          ],
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                        child: _DesktopQueueList(
                          queue: queue,
                          currentIndex: currentIndex,
                          playback: playback,
                          colors: colors,
                          isCurrentQueueSong: _isCurrentQueueSong,
                          artworkFallback: _queueArtworkFallback,
                        ),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  queue.length > 1
                      ? 'Arrastra el icono para cambiar el orden'
                      : 'Pulsa una canción para reproducirla',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    return SizedBox(
      height: 64,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Minimizar reproductor',
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
              iconSize: 30,
            ),
            const Expanded(
              child: Text(
                'REPRODUCIENDO',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Cerrar reproductor y detener música',
              onPressed: () => _closePlayer(context),
              icon: const Icon(Icons.close_rounded),
              iconSize: 25,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildArtwork(String? artworkPath, double size) {
    final path = artworkPath;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 450),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.88, end: 1.0).animate(animation),
            child: child,
          ),
        );
      },
      child: Container(
        key: ValueKey<String>(path ?? ''),
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 30,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: path != null && path.isNotEmpty
              ? Image.file(
                  File(path),
                  key: ValueKey<String>('image_$path'),
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return _buildArtworkPlaceholder();
                  },
                )
              : _buildArtworkPlaceholder(),
        ),
      ),
    );
  }

  Widget _buildArtworkPlaceholder() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.accent, AppTheme.surface],
        ),
      ),
      child: const Center(
        child: Icon(Icons.music_note_rounded, size: 100, color: Colors.white),
      ),
    );
  }

  Widget _buildSongInformation(
    String title,
    String artist, {
    required _LayoutSize layout,
  }) {
    final isCompact = layout == _LayoutSize.compact;
    final titleSize = isCompact ? 20.0 : 23.0;
    final artistSize = isCompact ? 14.0 : 16.0;

    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              final slideAnimation = Tween<Offset>(
                begin: const Offset(0, 0.25),
                end: Offset.zero,
              ).animate(animation);

              return FadeTransition(
                opacity: animation,
                child: SlideTransition(position: slideAnimation, child: child),
              );
            },
            child: SizedBox(
              key: ValueKey<String>(title),
              width: double.infinity,
              child: _ScrollingTitle(
                title: title,
                style: TextStyle(
                  fontSize: titleSize,
                  height: 1.2,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.2),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              );
            },
            child: SizedBox(
              key: ValueKey<String>(artist),
              width: double.infinity,
              child: Text(
                artist.isEmpty ? 'Artista desconocido' : artist,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: artistSize,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgress(Duration position, Duration duration) {
    final totalMilliseconds = duration.inMilliseconds;
    final safePosition = position.inMilliseconds.clamp(
      0,
      totalMilliseconds > 0 ? totalMilliseconds : 0,
    );

    final progress = totalMilliseconds > 0
        ? (safePosition / totalMilliseconds).clamp(0.0, 1.0).toDouble()
        : 0.0;

    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 5,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            activeTrackColor: AppTheme.accent,
            inactiveTrackColor: AppTheme.surface,
            thumbColor: AppTheme.accent,
            overlayColor: AppTheme.accent.withValues(alpha: 0.15),
          ),
          child: Slider(
            value: progress,
            min: 0,
            max: 1,
            onChangeStart: totalMilliseconds > 0
                ? (value) {
                    setState(() {
                      _dragPosition = Duration(
                        milliseconds: (value * totalMilliseconds).round(),
                      );
                    });
                  }
                : null,
            onChanged: totalMilliseconds > 0
                ? (value) {
                    setState(() {
                      _dragPosition = Duration(
                        milliseconds: (value * totalMilliseconds).round(),
                      );
                    });
                  }
                : null,
            onChangeEnd: totalMilliseconds > 0
                ? (value) {
                    final target = Duration(
                      milliseconds: (value * totalMilliseconds).round(),
                    );
                    final song = PlaybackService.instance.currentSong;

                    setState(() {
                      _dragPosition = null;
                      _pendingSeekPosition = target;
                      _pendingSeekSongTitle = song?.title;
                      _pendingSeekSongArtist = song?.artist;
                    });

                    PlaybackService.instance.seek(target);
                  }
                : null,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(position),
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Text(
                _formatDuration(duration),
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMainControls({
    required bool isPlaying,
    required bool canPlayPrevious,
    required bool canPlayNext,
    required VoidCallback onPrevious,
    required VoidCallback onPlayPause,
    required VoidCallback onNext,
    required _LayoutSize layout,
  }) {
    final isCompact = layout == _LayoutSize.compact;
    final sideIconSize = isCompact ? 32.0 : 36.0;
    final sidePadding = isCompact ? 6.0 : 8.0;
    final gap = isCompact ? 8.0 : 12.0;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Anterior',
          onPressed: canPlayPrevious ? onPrevious : null,
          icon: const Icon(Icons.skip_previous_rounded),
          iconSize: sideIconSize,
          padding: EdgeInsets.all(sidePadding),
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        ),
        SizedBox(width: gap),
        _AnimatedPlayPauseButton(
          isPlaying: isPlaying,
          onPressed: onPlayPause,
          size: isCompact ? 68 : 76,
        ),
        SizedBox(width: gap),
        IconButton(
          tooltip: 'Siguiente',
          onPressed: canPlayNext ? onNext : null,
          icon: const Icon(Icons.skip_next_rounded),
          iconSize: sideIconSize,
          padding: EdgeInsets.all(sidePadding),
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        ),
      ],
    );
  }

  Widget _buildBottomMenu({
    required bool isFavorite,
    required VoidCallback onFavoritePressed,
    required bool shuffleEnabled,
    required LoopMode repeatMode,
  }) {
    final repeatIcon = switch (repeatMode) {
      LoopMode.one => Icons.repeat_one_rounded,
      LoopMode.all => Icons.repeat_rounded,
      LoopMode.off => Icons.repeat_rounded,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Expanded(
            child: _buildMenuButton(
              icon: isFavorite
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              label: 'Favoritos',
              isActive: isFavorite,
              onPressed: onFavoritePressed,
            ),
          ),
          Expanded(
            child: _buildPlaybackOptionsButton(
              shuffleEnabled: shuffleEnabled,
              repeatMode: repeatMode,
              repeatIcon: repeatIcon,
            ),
          ),
          Expanded(
            child: _buildMenuButton(
              icon: Icons.queue_music_rounded,
              label: 'Cola',
              onPressed: () => _showPlaybackQueue(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaybackOptionsButton({
    required bool shuffleEnabled,
    required LoopMode repeatMode,
    required IconData repeatIcon,
  }) {
    final isActive = shuffleEnabled || repeatMode != LoopMode.off;

    return InkWell(
      onTap: () => _showPlaybackOptionsSheet(
        shuffleEnabled: shuffleEnabled,
        repeatMode: repeatMode,
      ),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              shuffleEnabled ? Icons.shuffle_rounded : repeatIcon,
              size: 22,
              color: isActive ? AppTheme.accent : AppTheme.textSecondary,
            ),
            const SizedBox(height: 5),
            Text(
              'Reproducción',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: isActive ? AppTheme.accent : AppTheme.textSecondary,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPlaybackOptionsSheet({
    required bool shuffleEnabled,
    required LoopMode repeatMode,
  }) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.surface,
      useSafeArea: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return AnimatedBuilder(
          animation: PlaybackService.instance,
          builder: (context, _) {
            final playback = PlaybackService.instance;

            Widget buildOption({
              required IconData icon,
              required String title,
              required bool selected,
              required VoidCallback onTap,
            }) {
              return ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                minLeadingWidth: 24,
                leading: Icon(
                  icon,
                  size: 21,
                  color: selected ? AppTheme.accent : AppTheme.textSecondary,
                ),
                title: Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                    color: selected ? AppTheme.accent : null,
                  ),
                ),
                trailing: selected
                    ? Icon(
                        Icons.check_rounded,
                        size: 20,
                        color: AppTheme.accent,
                      )
                    : null,
                onTap: onTap,
              );
            }

            Widget buildSectionTitle(String title) {
              return Padding(
                padding: const EdgeInsets.only(left: 8, top: 16, bottom: 4),
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                    color: AppTheme.textSecondary,
                  ),
                ),
              );
            }

            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Reproducción',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Cerrar',
                        onPressed: () => Navigator.pop(sheetContext),
                        icon: const Icon(Icons.close_rounded, size: 21),
                      ),
                    ],
                  ),
                  buildSectionTitle('ALEATORIO'),
                  buildOption(
                    icon: Icons.shuffle_rounded,
                    title: 'Reproducción aleatoria',
                    selected: playback.shuffleEnabled,
                    onTap: () => unawaited(playback.toggleShuffle()),
                  ),
                  buildSectionTitle('REPETICIÓN'),
                  buildOption(
                    icon: Icons.repeat_rounded,
                    title: 'No repetir',
                    selected: playback.repeatMode == LoopMode.off,
                    onTap: () => _setRepeatMode(LoopMode.off),
                  ),
                  buildOption(
                    icon: Icons.repeat_one_rounded,
                    title: 'Repetir canción',
                    selected: playback.repeatMode == LoopMode.one,
                    onTap: () => _setRepeatMode(LoopMode.one),
                  ),
                  buildOption(
                    icon: Icons.repeat_rounded,
                    title: 'Repetir cola',
                    selected: playback.repeatMode == LoopMode.all,
                    onTap: () => _setRepeatMode(LoopMode.all),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            );
          },
        );
      },
    );
  }

  bool _isCurrentQueueSong(dynamic currentSong, dynamic song) {
    if (currentSong == null) return false;

    final currentPath = currentSong.filePath?.replaceAll('\\', '/');
    final songPath = song.filePath?.replaceAll('\\', '/');

    if (currentPath != null &&
        currentPath.isNotEmpty &&
        songPath != null &&
        songPath.isNotEmpty) {
      return currentPath == songPath;
    }

    return song.title.trim().toLowerCase() ==
            currentSong.title.trim().toLowerCase() &&
        song.artist.trim().toLowerCase() ==
            currentSong.artist.trim().toLowerCase();
  }

  void _showPlaybackQueue(BuildContext context) {
    final initialQueue = PlaybackQueue.instance.songs;
    final initialSong = PlaybackService.instance.currentSong;
    final initialIndex = initialQueue.indexWhere(
      (item) => _isCurrentQueueSong(initialSong, item),
    );

    final screenSize = MediaQuery.sizeOf(context);
    final isCompact = screenSize.width < 400;
    final insetHorizontal = isCompact ? 12.0 : 20.0;

    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return _QueueScrollHost(
          initialIndex: initialIndex,
          builder: (dialogContext, scrollController) {
            return AnimatedBuilder(
              animation: Listenable.merge([
                PlaybackService.instance,
                PlaybackQueue.instance,
              ]),
              builder: (context, _) {
                final playback = PlaybackService.instance;
                final queue = PlaybackQueue.instance.songs;
                final colors = Theme.of(context).colorScheme;
                final size = MediaQuery.sizeOf(context);

                return Dialog(
                  backgroundColor: AppTheme.surfaceVariant,
                  insetPadding: EdgeInsets.symmetric(
                    horizontal: insetHorizontal,
                    vertical: 24,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: SizedBox(
                    width: size.width >= 700 ? 500 : size.width,
                    height: size.height * 0.72,
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
                          child: Row(
                            children: [
                              Icon(
                                Icons.queue_music_rounded,
                                color: colors.primary,
                                size: 27,
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text(
                                  'Cola de reproducción',
                                  style: TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                '${queue.length} canciones',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Cerrar',
                                onPressed: () =>
                                    Navigator.of(dialogContext).pop(),
                                icon: const Icon(Icons.close_rounded),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        Expanded(
                          child: queue.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.queue_music_rounded,
                                        size: 54,
                                        color: AppTheme.textSecondary,
                                      ),
                                      const SizedBox(height: 12),
                                      const Text('La cola está vacía'),
                                    ],
                                  ),
                                )
                              : Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    12,
                                    8,
                                    12,
                                    8,
                                  ),
                                  child: _QueueListView(
                                    queue: queue,
                                    playback: playback,
                                    colors: colors,
                                    scrollController: scrollController,
                                    isCurrentQueueSong: _isCurrentQueueSong,
                                    artworkFallback: _queueArtworkFallback,
                                  ),
                                ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            queue.length > 1
                                ? 'Arrastra el icono para cambiar el orden'
                                : 'Pulsa una canción para reproducirla',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                            ),
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
      },
    );
  }

  Widget _queueArtworkFallback(ColorScheme colors) {
    return Container(
      color: colors.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(
        Icons.music_note_rounded,
        size: 26,
        color: colors.onSurfaceVariant,
      ),
    );
  }

  Widget _buildMenuButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    bool isActive = false,
  }) {
    return Center(
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        splashColor: AppTheme.accent.withValues(alpha: 0.18),
        highlightColor: AppTheme.accent.withValues(alpha: 0.08),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, animation) {
                  return ScaleTransition(
                    scale: animation,
                    child: FadeTransition(opacity: animation, child: child),
                  );
                },
                child: Icon(
                  icon,
                  key: ValueKey<IconData>(icon),
                  size: 23,
                  color: isActive ? AppTheme.accent : AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: isActive ? AppTheme.accent : AppTheme.textSecondary,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyPlayer(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.music_off_rounded,
              size: 80,
              color: AppTheme.textSecondary,
            ),
            const SizedBox(height: 20),
            const Text(
              'No hay música reproduciéndose',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Text(
              'Selecciona una canción de tu biblioteca para comenzar.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text('Volver'),
            ),
          ],
        ),
      ),
    );
  }
}

class _QueueScrollHost extends StatefulWidget {
  final int initialIndex;
  final Widget Function(BuildContext context, ScrollController controller)
  builder;

  const _QueueScrollHost({required this.initialIndex, required this.builder});

  static const double itemHeight = 72;
  static const double listPadding = 0;
  static const double firstItemTopBorder = 0;

  @override
  State<_QueueScrollHost> createState() => _QueueScrollHostState();
}

class _QueueScrollHostState extends State<_QueueScrollHost> {
  final ScrollController _controller = ScrollController();

  @override
  void initState() {
    super.initState();

    if (widget.initialIndex > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_controller.hasClients) return;

        final position = _controller.position;
        final itemTop =
            _QueueScrollHost.listPadding +
            widget.initialIndex * _QueueScrollHost.itemHeight +
            _QueueScrollHost.firstItemTopBorder;

        final target =
            itemTop +
            _QueueScrollHost.itemHeight / 2 -
            position.viewportDimension / 2;

        _controller.jumpTo(target.clamp(0.0, position.maxScrollExtent));
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _controller);
  }
}

class _ScrollingTitle extends StatefulWidget {
  final String title;
  final TextStyle style;

  const _ScrollingTitle({super.key, required this.title, required this.style});

  @override
  State<_ScrollingTitle> createState() => _ScrollingTitleState();
}

class _ScrollingTitleState extends State<_ScrollingTitle> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _firstTextKey = GlobalKey();

  int _generation = 0;
  bool _scrolling = false;
  double _textWidth = 0;

  static const double _gap = 48;
  static const double _pixelsPerSecond = 35;
  static const Duration _initialDelay = Duration(milliseconds: 250);
  static const Duration _pauseDuration = Duration(seconds: 5);

  TextStyle _effectiveStyle(BuildContext context) {
    return DefaultTextStyle.of(context).style.merge(widget.style);
  }

  double? _measureCycleWidth() {
    final renderObject = _firstTextKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return null;
    return renderObject.size.width + _gap;
  }

  @override
  void didUpdateWidget(covariant _ScrollingTitle oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.title != widget.title || oldWidget.style != widget.style) {
      _generation++;
      _scrolling = false;
      _textWidth = 0;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        if (_scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }

        setState(() {});
      });
    }
  }

  void _configure(double textWidth, double availableWidth) {
    if (!mounted) return;

    final shouldScroll = textWidth > availableWidth + 1;

    if (_scrolling == shouldScroll && (_textWidth - textWidth).abs() < 0.5) {
      return;
    }

    _generation++;
    final generation = _generation;
    _textWidth = textWidth;

    setState(() {
      _scrolling = shouldScroll;
    });

    if (!shouldScroll) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _generation) return;
      if (!_scrollController.hasClients) return;

      _scrollController.jumpTo(0);
      _runMarquee(generation);
    });
  }

  Future<void> _runMarquee(int generation) async {
    await Future<void>.delayed(_initialDelay);

    while (mounted && generation == _generation && _scrolling) {
      if (!_scrollController.hasClients) return;

      final cycleWidth = _measureCycleWidth();
      if (cycleWidth == null) return;

      final maxScroll = _scrollController.position.maxScrollExtent;
      if (maxScroll < cycleWidth - 1) return;

      final duration = Duration(
        milliseconds: (cycleWidth / _pixelsPerSecond * 1000).round(),
      );

      await _scrollController.animateTo(
        cycleWidth,
        duration: duration,
        curve: Curves.linear,
      );

      if (!mounted || generation != _generation || !_scrolling) return;
      if (!_scrollController.hasClients) return;

      _scrollController.jumpTo(0);
      await Future<void>.delayed(_pauseDuration);
    }
  }

  @override
  void dispose() {
    _generation++;
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final effectiveStyle = _effectiveStyle(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.title, style: effectiveStyle),
          maxLines: 1,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();

        final textWidth = painter.width;
        final availableWidth = constraints.maxWidth;

        WidgetsBinding.instance.addPostFrameCallback((_) {
          _configure(textWidth, availableWidth);
        });

        final height =
            (widget.style.fontSize ?? 14) * (widget.style.height ?? 1.2) + 4;

        return SizedBox(
          height: height,
          width: double.infinity,
          child: ClipRect(
            child: _scrolling
                ? SingleChildScrollView(
                    controller: _scrollController,
                    scrollDirection: Axis.horizontal,
                    physics: const NeverScrollableScrollPhysics(),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.title,
                          key: _firstTextKey,
                          maxLines: 1,
                          softWrap: false,
                          style: widget.style,
                        ),
                        const SizedBox(width: _gap),
                        Text(
                          widget.title,
                          maxLines: 1,
                          softWrap: false,
                          style: widget.style,
                        ),
                        const SizedBox(width: _gap),
                      ],
                    ),
                  )
                : Center(
                    child: Text(
                      widget.title,
                      maxLines: 1,
                      softWrap: false,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: widget.style,
                    ),
                  ),
          ),
        );
      },
    );
  }
}

class _AnimatedPlayPauseButton extends StatefulWidget {
  final bool isPlaying;
  final VoidCallback onPressed;
  final double size;

  const _AnimatedPlayPauseButton({
    required this.isPlaying,
    required this.onPressed,
    this.size = 76,
  });

  @override
  State<_AnimatedPlayPauseButton> createState() =>
      _AnimatedPlayPauseButtonState();
}

class _AnimatedPlayPauseButtonState extends State<_AnimatedPlayPauseButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );

    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: 0.86,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 45,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 0.86,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 55,
      ),
    ]).animate(_controller);
  }

  void _handlePress() {
    _controller.forward(from: 0);
    widget.onPressed();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;

    return ScaleTransition(
      scale: _scaleAnimation,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOutCubic,
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppTheme.accent,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppTheme.accent.withValues(
                alpha: widget.isPlaying ? 0.35 : 0.18,
              ),
              blurRadius: widget.isPlaying ? 24 : 12,
              spreadRadius: widget.isPlaying ? 3 : 0,
            ),
          ],
        ),
        child: IconButton(
          tooltip: widget.isPlaying ? 'Pausar' : 'Reproducir',
          onPressed: _handlePress,
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutBack,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: ScaleTransition(scale: animation, child: child),
              );
            },
            child: Icon(
              widget.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              key: ValueKey<bool>(widget.isPlaying),
              color: Colors.white,
              size: size * 0.57,
            ),
          ),
        ),
      ),
    );
  }
}

class _QueueListView extends StatelessWidget {
  final List<Song> queue;
  final PlaybackService playback;
  final ColorScheme colors;
  final ScrollController scrollController;
  final bool Function(dynamic, dynamic) isCurrentQueueSong;
  final Widget Function(ColorScheme) artworkFallback;
  final VoidCallback? onReordered;

  const _QueueListView({
    required this.queue,
    required this.playback,
    required this.colors,
    required this.scrollController,
    required this.isCurrentQueueSong,
    required this.artworkFallback,
    this.onReordered,
  });

  @override
  Widget build(BuildContext context) {
    final currentSong = playback.currentSong;

    return _QueueListContainer(
      child: ReorderableListView.builder(
        key: const PageStorageKey<String>('playback_queue_table'),
        scrollController: scrollController,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: queue.length,
        buildDefaultDragHandles: false,
        onReorder: (oldIndex, newIndex) {
          if (queue.length < 2 || oldIndex == newIndex) return;

          playback.reorderPlaybackQueue(oldIndex, newIndex);
          onReordered?.call();
        },
        proxyDecorator: (child, index, animation) {
          return AnimatedBuilder(
            animation: animation,
            child: child,
            builder: (context, child) {
              final progress = Curves.easeOutCubic.transform(
                animation.value.clamp(0.0, 1.0),
              );

              return Material(
                color: AppTheme.surface,
                elevation: 4 * progress,
                shadowColor: Colors.black.withValues(alpha: 0.18 * progress),
                borderRadius: BorderRadius.circular(14),
                clipBehavior: Clip.antiAlias,
                child: child,
              );
            },
          );
        },
        itemBuilder: (context, index) {
          final item = queue[index];
          final selected = isCurrentQueueSong(currentSong, item);
          final artworkPath = item.artworkPath;
          final itemKey = item.filePath ?? '${item.title}_${item.artist}';

          return Dismissible(
            key: ValueKey<String>('dismiss_$itemKey'),
            direction: selected
                ? DismissDirection.none
                : DismissDirection.startToEnd,
            dismissThresholds: const {DismissDirection.startToEnd: 0.3},
            background: Container(
              alignment: Alignment.centerLeft,
              margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
              padding: const EdgeInsets.only(left: 18),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.delete_outline_rounded,
                color: Colors.red,
                size: 28,
              ),
            ),
            onDismissed: (_) {
              unawaited(playback.removeFromPlaybackQueue(item));
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Material(
                key: ValueKey<String>('row_$itemKey'),
                type: MaterialType.card,
                color: selected
                    ? colors.primary.withValues(alpha: 0.10)
                    : AppTheme.surface,
                elevation: selected ? 2 : 0,
                shadowColor: Colors.black.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: selected
                      ? null
                      : () async {
                          await playback.playSongFromQueue(item);
                        },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: SizedBox(
                            width: 48,
                            height: 48,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                if (artworkPath != null &&
                                    artworkPath.isNotEmpty)
                                  Image.file(
                                    File(artworkPath),
                                    fit: BoxFit.cover,
                                    cacheWidth: 144,
                                    cacheHeight: 144,
                                    errorBuilder: (context, error, stackTrace) {
                                      return artworkFallback(colors);
                                    },
                                  )
                                else
                                  artworkFallback(colors),
                                if (selected && playback.isPlaying)
                                  Container(
                                    color: Colors.black.withValues(alpha: 0.45),
                                    alignment: Alignment.center,
                                    child: Icon(
                                      Icons.equalizer_rounded,
                                      color: colors.primary,
                                      size: 26,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: selected
                                      ? FontWeight.bold
                                      : FontWeight.w600,
                                  color: selected ? colors.primary : null,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                item.artist.isEmpty
                                    ? 'Artista desconocido'
                                    : item.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        ReorderableDragStartListener(
                          index: index,
                          child: Padding(
                            padding: const EdgeInsets.only(
                              left: 8,
                              top: 8,
                              bottom: 8,
                            ),
                            child: Icon(
                              Icons.drag_handle_rounded,
                              color: AppTheme.textSecondary.withValues(
                                alpha: 0.7,
                              ),
                              size: 23,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DesktopQueueList extends StatefulWidget {
  final List<Song> queue;
  final int currentIndex;
  final PlaybackService playback;
  final ColorScheme colors;
  final bool Function(dynamic, dynamic) isCurrentQueueSong;
  final Widget Function(ColorScheme) artworkFallback;

  const _DesktopQueueList({
    required this.queue,
    required this.currentIndex,
    required this.playback,
    required this.colors,
    required this.isCurrentQueueSong,
    required this.artworkFallback,
  });

  @override
  State<_DesktopQueueList> createState() => _DesktopQueueListState();
}

class _DesktopQueueListState extends State<_DesktopQueueList> {
  final ScrollController _controller = ScrollController();

  static const double _itemExtent = 72;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _followCurrentSong(animated: false);
    });
  }

  @override
  void didUpdateWidget(covariant _DesktopQueueList oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.currentIndex != widget.currentIndex ||
        oldWidget.queue.length != widget.queue.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _followCurrentSong();
      });
    }
  }

  void _followCurrentSong({bool animated = true}) {
    if (!mounted ||
        !_controller.hasClients ||
        widget.currentIndex < 0 ||
        widget.currentIndex >= widget.queue.length) {
      return;
    }

    final position = _controller.position;
    final target =
        (widget.currentIndex * _itemExtent -
                position.viewportDimension / 2 +
                _itemExtent / 2)
            .clamp(0.0, position.maxScrollExtent);

    if ((position.pixels - target).abs() < 12) return;

    if (animated) {
      _controller.animateTo(
        target,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOutCubic,
      );
    } else {
      _controller.jumpTo(target);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _QueueListView(
      queue: widget.queue,
      playback: widget.playback,
      colors: widget.colors,
      scrollController: _controller,
      isCurrentQueueSong: widget.isCurrentQueueSong,
      artworkFallback: widget.artworkFallback,
      onReordered: () {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _followCurrentSong(animated: false);
        });
      },
    );
  }
}

class _QueueListContainer extends StatelessWidget {
  final Widget child;

  const _QueueListContainer({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.surfaceVariant, width: 0.7),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}
