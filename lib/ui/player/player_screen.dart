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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceVariant,
      body: SafeArea(
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

    return Container(
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
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return _buildArtworkPlaceholder();
                },
              )
            : _buildArtworkPlaceholder(),
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
              _ScrollingTitle(
                key: ValueKey<String>(title),
                title: title,
                style: const TextStyle(
                  fontSize: 23,
                  height: 1.2,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
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
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            color: AppTheme.accent,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppTheme.accent.withValues(alpha: 0.25),
                blurRadius: 18,
                spreadRadius: 2,
              ),
            ],
          ),
          child: IconButton(
            tooltip: isPlaying ? 'Pausar' : 'Reproducir',
            onPressed: onPlayPause,
            icon: Icon(
              isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: Colors.white,
              size: 43,
            ),
          ),
        ),
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
              onPressed: () {},
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
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

class _ScrollingTitleState extends State<_ScrollingTitle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _startTimer;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );

    _scheduleAnimation();
  }

  void _scheduleAnimation() {
    _startTimer?.cancel();
    _controller.stop();
    _controller.reset();

    // Deja que el usuario lea el título antes de iniciar el carrusel.
    _startTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) {
        _controller.repeat(reverse: true);
      }
    });
  }

  @override
  void didUpdateWidget(covariant _ScrollingTitle oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.title != widget.title) {
      _scheduleAnimation();
    }
  }

  @override
  void dispose() {
    _startTimer?.cancel();
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
        )..layout();

        final textWidth = textPainter.width;
        final availableWidth = constraints.maxWidth;
        final overflow = (textWidth - availableWidth).clamp(
          0.0,
          double.infinity,
        );

        // Si el título cabe, no se anima ni se recorta innecesariamente.
        if (overflow <= 1) {
          return SizedBox(
            height: widget.style.fontSize! * widget.style.height! + 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: widget.style,
              ),
            ),
          );
        }

        return SizedBox(
          height: widget.style.fontSize! * widget.style.height! + 2,
          width: availableWidth,
          child: ClipRect(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Transform.translate(
                  offset: Offset(-overflow * _controller.value, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    widthFactor: 1,
                    child: SizedBox(
                      width: textWidth,
                      child: Text(
                        widget.title,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.visible,
                        style: widget.style,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
