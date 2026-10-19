import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../../core/services/playback_service.dart';
import '../../core/services/playback_queue.dart';

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

  void _onPlaybackChanged() {
    final playback = PlaybackService.instance;
    final pendingPosition = _pendingSeekPosition;

    if (pendingPosition == null) return;

    final song = playback.currentSong;

    // Si cambia la canción, ya no debemos conservar el seek anterior.
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

    // Conservamos visualmente la posición elegida hasta que el reproductor
    // confirme que ha llegado aproximadamente a ella.
    final difference =
        (playback.position.inMilliseconds - pendingPosition.inMilliseconds)
            .abs();

    if (difference <= 1000) {
      if (mounted) {
        setState(() {
          _pendingSeekPosition = null;
          _pendingSeekSongTitle = null;
          _pendingSeekSongArtist = null;
        });
      }
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  void _closePlayer(BuildContext context) {
    PlaybackService.instance.stop();
    PlaybackQueue.instance.clear();
    Navigator.of(context).maybePop();
  }

  /// Altura real de la barra de estado / cámara.
  ///
  /// Se lee directamente de la vista porque el bottom sheet elimina el
  /// padding superior del MediaQuery heredado (y viewPadding puede quedar
  /// en 0 también).
  double _statusBarHeight(BuildContext context) {
    return MediaQueryData.fromView(View.of(context)).padding.top;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceVariant,
      body: SafeArea(
        // El espacio superior lo ponemos manualmente con un spacer.
        top: false,
        child: AnimatedBuilder(
          animation: PlaybackService.instance,
          builder: (context, child) {
            final playback = PlaybackService.instance;
            final song = playback.currentSong;

            if (song == null) {
              return _buildEmptyPlayer(context);
            }

            final screenWidth = MediaQuery.sizeOf(context).width;
            final isDesktop = screenWidth >= 700;
            final artworkSize = isDesktop
                ? 320.0
                : (screenWidth - 48).clamp(220.0, 360.0);

            // Prioridad visual:
            // 1. Posición mientras se arrastra el slider.
            // 2. Posición solicitada por el último seek.
            // 3. Posición reportada por el reproductor.
            final displayPosition =
                _dragPosition ?? _pendingSeekPosition ?? playback.position;

            return Column(
              children: [
                // Spacer para librar la cámara, la hora y los iconos de Android.
                SizedBox(height: _statusBarHeight(context)),
                _buildHeader(context),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: EdgeInsets.symmetric(
                      horizontal: isDesktop ? 40 : 24,
                      vertical: 12,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(height: isDesktop ? 20 : 8),
                            _buildArtwork(song.artworkPath, artworkSize),
                            const SizedBox(height: 32),
                            _buildSongInformation(song.title, song.artist),
                            const SizedBox(height: 30),
                            _buildProgress(displayPosition, playback.duration),
                            const SizedBox(height: 20),
                            _buildMainControls(
                              isPlaying: playback.isPlaying,
                              canPlayPrevious: playback.canPlayPrevious,
                              canPlayNext: playback.canPlayNext,
                              onPrevious: playback.playPrevious,
                              onPlayPause: playback.togglePlayPause,
                              onNext: playback.playNext,
                            ),
                            const SizedBox(height: 44),
                            _buildBottomMenu(),
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
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

  Widget _buildSongInformation(String title, String artist) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                    child: SlideTransition(
                      position: slideAnimation,
                      child: child,
                    ),
                  );
                },
                child: SizedBox(
                  key: ValueKey<String>(title),
                  width: double.infinity,
                  child: _ScrollingTitle(
                    title: title,
                    style: const TextStyle(
                      fontSize: 23,
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
                child: Text(
                  artist.isEmpty ? 'Artista desconocido' : artist,
                  key: ValueKey<String>(artist),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 16),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        IconButton(
          tooltip: 'Añadir a favoritos',
          onPressed: () {},
          icon: const Icon(Icons.favorite_border_rounded),
          color: AppTheme.textSecondary,
          iconSize: 27,
        ),
      ],
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

                    // Ejecutamos el seek una sola vez al soltar el slider.
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
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          tooltip: 'Anterior',
          onPressed: canPlayPrevious ? onPrevious : null,
          icon: const Icon(Icons.skip_previous_rounded),
          iconSize: 36,
          padding: const EdgeInsets.all(8),
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        ),
        const SizedBox(width: 24),
        _AnimatedPlayPauseButton(isPlaying: isPlaying, onPressed: onPlayPause),
        const SizedBox(width: 24),
        IconButton(
          tooltip: 'Siguiente',
          onPressed: canPlayNext ? onNext : null,
          icon: const Icon(Icons.skip_next_rounded),
          iconSize: 36,
          padding: const EdgeInsets.all(8),
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        ),
      ],
    );
  }

  Widget _buildBottomMenu() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Expanded(
            child: _buildMenuButton(
              icon: Icons.shuffle_rounded,
              label: 'Aleatorio',
              onPressed: () {},
            ),
          ),
          Expanded(
            child: _buildMenuButton(
              icon: Icons.repeat_rounded,
              label: 'Repetir',
              onPressed: () {},
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

  void _showPlaybackQueue(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return AnimatedBuilder(
          animation: Listenable.merge([
            PlaybackService.instance,
            PlaybackQueue.instance,
          ]),
          builder: (context, _) {
            final playback = PlaybackService.instance;
            final queue = PlaybackQueue.instance.songs;
            final currentSong = playback.currentSong;
            final colors = Theme.of(context).colorScheme;
            final size = MediaQuery.sizeOf(context);

            bool isCurrentSong(dynamic song) {
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

            return Dialog(
              backgroundColor: AppTheme.surfaceVariant,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 20,
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
                            onPressed: () => Navigator.of(dialogContext).pop(),
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
                          : ReorderableListView.builder(
                              key: const PageStorageKey<String>(
                                'playback_queue_table',
                              ),
                              padding: const EdgeInsets.all(12),
                              itemCount: queue.length,
                              buildDefaultDragHandles: false,
                              onReorder: (oldIndex, newIndex) {
                                if (queue.length < 2 || oldIndex == newIndex) {
                                  return;
                                }

                                playback.reorderPlaybackQueue(
                                  oldIndex,
                                  newIndex,
                                );
                              },
                              proxyDecorator: (child, index, animation) {
                                final draggedSong = queue[index];

                                return AnimatedBuilder(
                                  animation: animation,
                                  child: child,
                                  builder: (context, child) {
                                    final progress = Curves.easeOutCubic
                                        .transform(
                                          animation.value.clamp(0.0, 1.0),
                                        );

                                    final radius = 18.0 * progress;

                                    final isFirst = index == 0;
                                    final isLast = index == queue.length - 1;

                                    final targetRadius = BorderRadius.only(
                                      topLeft: Radius.circular(
                                        isFirst ? radius : 0,
                                      ),
                                      topRight: Radius.circular(
                                        isFirst ? radius : 0,
                                      ),
                                      bottomLeft: Radius.circular(
                                        isLast ? radius : 0,
                                      ),
                                      bottomRight: Radius.circular(
                                        isLast ? radius : 0,
                                      ),
                                    );

                                    return Material(
                                      color: Colors.transparent,
                                      elevation: 6 * progress,
                                      shadowColor: Colors.black.withValues(
                                        alpha: 0.22 * progress,
                                      ),
                                      borderRadius: targetRadius,
                                      clipBehavior: Clip.antiAlias,
                                      child: child,
                                    );
                                  },
                                );
                              },
                              itemBuilder: (context, index) {
                                final song = queue[index];
                                final selected = isCurrentSong(song);
                                final artworkPath = song.artworkPath;
                                final isFirst = index == 0;
                                final isLast = index == queue.length - 1;

                                final targetRadius = BorderRadius.vertical(
                                  top: isFirst
                                      ? const Radius.circular(18)
                                      : Radius.zero,
                                  bottom: isLast
                                      ? const Radius.circular(18)
                                      : Radius.zero,
                                );

                                final songKey = ValueKey<String>(
                                  song.filePath ??
                                      '${song.title}_${song.artist}',
                                );

                                return AnimatedContainer(
                                  key: songKey,
                                  duration: const Duration(milliseconds: 280),
                                  curve: Curves.easeInOutCubic,
                                  clipBehavior: Clip.antiAlias,
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? colors.primary.withValues(alpha: 0.10)
                                        : AppTheme.surface,
                                    borderRadius: targetRadius,
                                    border: Border(
                                      left: BorderSide(
                                        color: AppTheme.surfaceVariant,
                                        width: 0.7,
                                      ),
                                      right: BorderSide(
                                        color: AppTheme.surfaceVariant,
                                        width: 0.7,
                                      ),
                                      top: isFirst
                                          ? BorderSide(
                                              color: AppTheme.surfaceVariant,
                                              width: 0.7,
                                            )
                                          : BorderSide.none,
                                      bottom: BorderSide(
                                        color: AppTheme.surfaceVariant,
                                        width: 0.7,
                                      ),
                                    ),
                                  ),
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: selected
                                          ? null
                                          : () async {
                                              await playback.playSongFromQueue(
                                                song,
                                              );
                                            },
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 12,
                                        ),
                                        child: Row(
                                          children: [
                                            ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(12),
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
                                                        errorBuilder:
                                                            (
                                                              context,
                                                              error,
                                                              stackTrace,
                                                            ) {
                                                              return _queueArtworkFallback(
                                                                colors,
                                                              );
                                                            },
                                                      )
                                                    else
                                                      _queueArtworkFallback(
                                                        colors,
                                                      ),
                                                    if (selected &&
                                                        playback.isPlaying)
                                                      Container(
                                                        color: Colors.black
                                                            .withValues(
                                                              alpha: 0.45,
                                                            ),
                                                        alignment:
                                                            Alignment.center,
                                                        child: Icon(
                                                          Icons
                                                              .equalizer_rounded,
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
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    song.title,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      fontWeight: selected
                                                          ? FontWeight.bold
                                                          : FontWeight.w600,
                                                      color: selected
                                                          ? colors.primary
                                                          : null,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    song.artist.isEmpty
                                                        ? 'Artista desconocido'
                                                        : song.artist,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: AppTheme
                                                          .textSecondary,
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
                                                  color: AppTheme.textSecondary
                                                      .withValues(alpha: 0.7),
                                                  size: 23,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
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
  }) {
    return Center(
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        splashColor: AppTheme.accent.withValues(alpha: 0.18),
        highlightColor: AppTheme.accent.withValues(alpha: 0.08),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 23, color: AppTheme.textSecondary),
              const SizedBox(height: 5),
              Text(
                label,
                style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
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

  /// Estilo realmente usado al pintar el texto (incluye DefaultTextStyle).
  TextStyle _effectiveStyle(BuildContext context) {
    return DefaultTextStyle.of(context).style.merge(widget.style);
  }

  /// Distancia exacta de un ciclo, medida sobre el texto ya renderizado.
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

      // Medimos el ancho real en cada ciclo para que la segunda copia
      // quede exactamente sobre el punto de inicio.
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

      // En este punto la segunda copia coincide con el origen, así que
      // volver a 0 es visualmente imperceptible. La pausa ocurre ya en 0.
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
            child: SingleChildScrollView(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              child: _scrolling
                  ? Row(
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
                    )
                  : SizedBox(
                      width: availableWidth,
                      child: Text(
                        widget.title,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: widget.style,
                      ),
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

  const _AnimatedPlayPauseButton({
    required this.isPlaying,
    required this.onPressed,
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
    return ScaleTransition(
      scale: _scaleAnimation,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOutCubic,
        width: 76,
        height: 76,
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
              size: 43,
            ),
          ),
        ),
      ),
    );
  }
}

class _QueueEntryTransition extends StatefulWidget {
  final int index;
  final Widget child;

  const _QueueEntryTransition({
    super.key,
    required this.index,
    required this.child,
  });

  static const double stagger = 0.025;
  static const double span = 0.55;
  static const double distance = 12;

  @override
  State<_QueueEntryTransition> createState() => _QueueEntryTransitionState();
}

class _QueueEntryTransitionState extends State<_QueueEntryTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );

    final begin = (widget.index * _QueueEntryTransition.stagger).clamp(
      0.0,
      1.0,
    );
    final end = (begin + _QueueEntryTransition.span).clamp(begin, 1.0);

    _animation = CurvedAnimation(
      parent: _controller,
      curve: Interval(begin, end, curve: Curves.easeOutCubic),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _animation,
      child: AnimatedBuilder(
        animation: _animation,
        child: widget.child,
        builder: (context, child) {
          return Transform.translate(
            offset: Offset(
              0,
              (1 - _animation.value) * _QueueEntryTransition.distance,
            ),
            child: child,
          );
        },
      ),
    );
  }
}
