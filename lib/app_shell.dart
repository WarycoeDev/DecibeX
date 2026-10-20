import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'ui/app_theme.dart';
import 'ui/home/home_screen.dart';
import 'ui/library/library_screen.dart';
import 'ui/player/mini_player.dart';
import 'ui/player/player_screen.dart';
import 'ui/search/search_screen.dart';
import 'ui/settings/settings_screen.dart';
import 'core/services/playback_service.dart';
import 'core/services/playback_queue.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;
  bool _sidebarExpanded = true;
  bool _desktopPlayerExpanded = false;

  // Estado del miniplayer móvil minimizado (oculto detrás de la barra).
  bool _miniPlayerMinimized = false;

  // true cuando el gesto ya llevó el miniplayer fuera de pantalla y el padre
  // solo debe fijar el estado final, sin volver a animar.
  bool _miniPlayerMinimizeInstant = false;

  final GlobalKey<LibraryScreenState> _libraryKey =
      GlobalKey<LibraryScreenState>();

  late final PageController _pageController = PageController(
    initialPage: _selectedIndex,
  );

  static const double _expandedWidth = 240;
  static const double _collapsedWidth = 72;

  // Distancia desde abajo a la que flota el miniplayer móvil
  // (justo encima de la barra de navegación).
  static const double _mobileMiniPlayerBottom = 80;

  static const Duration _sidebarAnimationDuration = Duration(milliseconds: 250);

  static const Duration _pageAnimationDuration = Duration(milliseconds: 350);

  static const Duration _miniPlayerEnterDuration = Duration(milliseconds: 320);

  static const Duration _miniPlayerExitDuration = Duration(milliseconds: 260);

  static const Duration _miniPlayerMinimizeDuration = Duration(
    milliseconds: 320,
  );

  static const List<String> _titles = [
    'Inicio',
    'Biblioteca',
    'Buscar',
    'Configuración',
  ];

  static const List<IconData> _icons = [
    Icons.home_outlined,
    Icons.library_music_outlined,
    Icons.search_rounded,
    Icons.settings_outlined,
  ];

  static const List<IconData> _selectedIcons = [
    Icons.home_rounded,
    Icons.library_music_rounded,
    Icons.search_rounded,
    Icons.settings_rounded,
  ];

  late final List<Widget> _screens = [
    const HomeScreen(),
    LibraryScreen(key: _libraryKey),
    const SearchScreen(),
    const SettingsScreen(),
  ];

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool _isDesktop(BuildContext context) {
    return MediaQuery.sizeOf(context).width >= 700;
  }

  Future<void> _openPlayerScreen() async {
    if (!mounted) return;

    final isDesktop = _isDesktop(context);

    if (isDesktop) {
      setState(() {
        _desktopPlayerExpanded = true;
      });

      await showGeneralDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierLabel: MaterialLocalizations.of(
          context,
        ).modalBarrierDismissLabel,
        barrierColor: Colors.black54,
        transitionDuration: const Duration(milliseconds: 320),
        pageBuilder: (dialogContext, animation, secondaryAnimation) {
          final screenSize = MediaQuery.sizeOf(dialogContext);
          final panelWidth = screenSize.width > 932
              ? 900.0
              : screenSize.width - 32;

          return Align(
            alignment: Alignment.bottomCenter,
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: panelWidth,
                height: screenSize.height * 0.94,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceVariant,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                ),
                child: const PlayerScreen(),
              ),
            ),
          );
        },
        transitionBuilder: (context, animation, secondaryAnimation, child) {
          final curvedAnimation = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );

          return FadeTransition(
            opacity: curvedAnimation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 1),
                end: Offset.zero,
              ).animate(curvedAnimation),
              child: child,
            ),
          );
        },
      );

      if (mounted) {
        setState(() {
          _desktopPlayerExpanded = false;
        });
      }

      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: false, // el PlayerScreen ya gestiona su propio SafeArea
      backgroundColor: AppTheme.surfaceVariant,
      barrierColor: Colors.black54,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius
            .zero, // sin esquinas para que quede a ras del borde superior
      ),
      clipBehavior: Clip.antiAlias,
      builder: (context) {
        return SizedBox(
          height: MediaQuery.sizeOf(context).height, // pantalla completa
          child: const PlayerScreen(),
        );
      },
    );
  }

  void _selectPage(int index) {
    if (_selectedIndex == index) return;

    setState(() {
      _selectedIndex = index;
    });

    if (_isAndroid) {
      _pageController.animateToPage(
        index,
        duration: _pageAnimationDuration,
        curve: Curves.easeInOutCubic,
      );
    } else {
      _pageController.jumpToPage(index);
    }
  }

  void _handleBack() {
    if (_selectedIndex == 1) {
      final libraryState = _libraryKey.currentState;

      if (libraryState != null && libraryState.hasOpenDetail) {
        libraryState.handleSystemBack();
        return;
      }
    }

    if (_selectedIndex != 0) {
      _selectPage(0);
    }
  }

  void _setMiniPlayerMinimized(bool value, {bool instant = false}) {
    if (_miniPlayerMinimized == value) return;

    setState(() {
      _miniPlayerMinimized = value;
      _miniPlayerMinimizeInstant = value && instant;
    });
  }

  /// Detiene la música, limpia la cola y cierra el miniplayer.
  /// Se usa tanto con el botón X como con el gesto de deslizar lateralmente.
  void _closeMiniPlayer() {
    PlaybackService.instance.stop();
    PlaybackQueue.instance.clear();

    // La próxima canción vuelve a mostrarse expandida.
    _setMiniPlayerMinimized(false);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = _isDesktop(context);

    return PopScope<Object?>(
      canPop: _selectedIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _handleBack();
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  _buildTitleBar(context),
                  Expanded(
                    child: Row(
                      children: [
                        if (isDesktop) _buildSidebar(),
                        Expanded(
                          child: PageView(
                            controller: _pageController,
                            physics: const NeverScrollableScrollPhysics(),
                            onPageChanged: (index) {
                              if (_selectedIndex != index) {
                                setState(() {
                                  _selectedIndex = index;
                                });
                              }
                            },
                            children: _screens,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!isDesktop) _buildBottomNavigation(),
                ],
              ),

              // MiniPlayer móvil flotante.
              // No ocupa espacio en el layout y el contenido pasa por debajo.
              // En Android responde a gestos:
              //  - deslizar a los lados: cierra y detiene la música
              //  - deslizar hacia abajo: se esconde detrás de la barra de
              //    navegación sin detener la música
              if (!isDesktop)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: _mobileMiniPlayerBottom,
                  child: _buildMobileMiniPlayer(),
                ),

              // Botón (chevron hacia arriba) para reabrir el miniplayer minimizado.
              // Sin `bottom` extra: el recorte y el margen los maneja el propio botón.
              if (!isDesktop && _isAndroid)
                Positioned(
                  left: 0,
                  bottom: _mobileMiniPlayerBottom,
                  child: _buildRestoreMiniPlayerButton(),
                ),

              // MiniPlayer de escritorio sin cambios.
              if (isDesktop)
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: _buildMiniPlayer(true),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Envuelve el miniplayer móvil con:
  ///  - un recorte en su borde inferior (justo donde empieza la barra de
  ///    navegación), de modo que al deslizarse hacia abajo parezca ir detrás
  ///  - el gesto de deslizar (solo Android)
  Widget _buildMobileMiniPlayer() {
    return ClipRect(
      child: IgnorePointer(
        ignoring: _miniPlayerMinimized,
        child: AnimatedSlide(
          // 1.1 = un poco más que su propia altura, para que quede
          // completamente oculto detrás de la barra.
          offset: _miniPlayerMinimized ? const Offset(0, 1.1) : Offset.zero,
          duration: _miniPlayerMinimizeInstant
              ? Duration.zero
              : _miniPlayerMinimizeDuration,
          curve: _miniPlayerMinimized
              ? Curves.easeInCubic
              : Curves.easeOutCubic,
          child: _MiniPlayerSwipe(
            enabled: _isAndroid,
            onDismiss: _closeMiniPlayer,
            onMinimize: () => _setMiniPlayerMinimized(true, instant: true),
            child: _buildMiniPlayer(false),
          ),
        ),
      ),
    );
  }

  /// Botón circular con flecha sin palito apuntando hacia arriba.
  /// Solo es visible cuando hay canción y el miniplayer está minimizado.
  /// Sale desde detrás de la barra de navegación.
  Widget _buildRestoreMiniPlayerButton() {
    return AnimatedBuilder(
      animation: PlaybackService.instance,
      builder: (context, child) {
        final visible =
            _miniPlayerMinimized &&
            PlaybackService.instance.currentSong != null;

        return ClipRect(
          child: IgnorePointer(
            ignoring: !visible,
            child: AnimatedSlide(
              offset: visible ? Offset.zero : const Offset(0, 1.2),
              duration: _miniPlayerMinimizeDuration,
              curve: visible ? Curves.easeOutCubic : Curves.easeInCubic,
              // El padding da espacio a la sombra para que el recorte no la corte.
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 14, 16, 6),
                child: Material(
                  color: AppTheme.surfaceVariant.withValues(alpha: 0.92),
                  shape: CircleBorder(
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.10),
                    ),
                  ),
                  elevation: 6,
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => _setMiniPlayerMinimized(false),
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: Tooltip(
                        message: 'Mostrar reproductor',
                        child: Icon(
                          Icons.keyboard_arrow_up_rounded,
                          size: 28,
                          color: AppTheme.accent,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMiniPlayer(bool isDesktop) {
    return AnimatedBuilder(
      animation: PlaybackService.instance,
      builder: (context, child) {
        final playback = PlaybackService.instance;
        final song = playback.currentSong;

        return AnimatedSwitcher(
          duration: _miniPlayerEnterDuration,
          reverseDuration: _miniPlayerExitDuration,
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            final slideAnimation =
                Tween<Offset>(
                  begin: const Offset(0, 0.22),
                  end: Offset.zero,
                ).animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  ),
                );

            return FadeTransition(
              opacity: animation,
              child: SlideTransition(position: slideAnimation, child: child),
            );
          },
          child: song == null || (isDesktop && _desktopPlayerExpanded)
              ? const SizedBox.shrink(
                  key: ValueKey<String>('mini-player-hidden'),
                )
              : MiniPlayer(
                  key: const ValueKey<String>('mini-player-visible'),
                  title: song.title,
                  artist: song.artist,
                  artworkPath: song.artworkPath,
                  position: playback.position,
                  duration: playback.duration,
                  isDesktop: isDesktop,
                  isPlaying: playback.isPlaying,
                  canPlayPrevious: playback.canPlayPrevious,
                  canPlayNext: playback.canPlayNext,
                  onExpand: _openPlayerScreen,
                  onPlayPause: playback.togglePlayPause,
                  onPrevious: playback.playPrevious,
                  onNext: playback.playNext,
                  onClose: _closeMiniPlayer,
                ),
        );
      },
    );
  }

  Widget _buildTitleBar(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border(
          bottom: BorderSide(color: AppTheme.surfaceVariant, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.graphic_eq_rounded, color: AppTheme.accent, size: 27),
          const SizedBox(width: 10),
          const Text(
            'DecibeX',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
          ),
          Container(
            height: 24,
            width: 1,
            margin: const EdgeInsets.symmetric(horizontal: 10),
            color: AppTheme.surfaceVariant,
          ),
          Expanded(
            child: Text(
              _titles[_selectedIndex],
              style: Theme.of(context).textTheme.titleMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    return AnimatedContainer(
      duration: _sidebarAnimationDuration,
      curve: Curves.easeInOutCubic,
      width: _sidebarExpanded ? _expandedWidth : _collapsedWidth,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border(
          right: BorderSide(color: AppTheme.surfaceVariant, width: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 72,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned(
                  left: 20,
                  right: 52,
                  top: 0,
                  bottom: 0,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: AnimatedOpacity(
                      duration: _sidebarAnimationDuration,
                      opacity: _sidebarExpanded ? 1 : 0,
                      child: Text(
                        'MENÚ PRINCIPAL',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ),
                AnimatedPositioned(
                  duration: _sidebarAnimationDuration,
                  curve: Curves.easeInOutCubic,
                  top: 16,
                  right: _sidebarExpanded ? 12 : 16,
                  width: 40,
                  height: 40,
                  child: IconButton(
                    tooltip: _sidebarExpanded
                        ? 'Contraer menú'
                        : 'Expandir menú',
                    padding: EdgeInsets.zero,
                    onPressed: () {
                      setState(() {
                        _sidebarExpanded = !_sidebarExpanded;
                      });
                    },
                    icon: Icon(
                      _sidebarExpanded
                          ? Icons.menu_open_rounded
                          : Icons.menu_rounded,
                      color: AppTheme.accent,
                    ),
                  ),
                ),
              ],
            ),
          ),
          for (int i = 0; i < _titles.length; i++) _buildSidebarItem(i),
          const Spacer(),
          SizedBox(
            height: 28,
            child: ClipRect(
              child: Padding(
                padding: const EdgeInsets.only(left: 16),
                child: AnimatedOpacity(
                  duration: _sidebarAnimationDuration,
                  opacity: _sidebarExpanded ? 1 : 0,
                  child: Text(
                    'DecibeX',
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildSidebarItem(int index) {
    final selected = _selectedIndex == index;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Material(
        color: selected ? AppTheme.surfaceVariant : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _selectPage(index),
          child: SizedBox(
            height: 48,
            child: Row(
              children: [
                SizedBox(
                  width: 44,
                  child: Center(
                    child: Icon(
                      selected ? _selectedIcons[index] : _icons[index],
                      color: selected
                          ? AppTheme.accent
                          : AppTheme.textSecondary,
                      size: 22,
                    ),
                  ),
                ),
                Expanded(
                  child: AnimatedOpacity(
                    duration: _sidebarAnimationDuration,
                    opacity: _sidebarExpanded ? 1 : 0,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        _titles[index],
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.clip,
                        style: TextStyle(
                          color: selected ? AppTheme.accent : Colors.white,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNavigation() {
    return NavigationBar(
      selectedIndex: _selectedIndex,
      onDestinationSelected: _selectPage,
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home_rounded),
          label: 'Inicio',
          tooltip: '',
        ),
        NavigationDestination(
          icon: Icon(Icons.library_music_outlined),
          selectedIcon: Icon(Icons.library_music_rounded),
          label: 'Biblioteca',
          tooltip: '',
        ),
        NavigationDestination(
          icon: Icon(Icons.search_rounded),
          label: 'Buscar',
          tooltip: '',
        ),
        NavigationDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings_rounded),
          label: 'Ajustes',
          tooltip: '',
        ),
      ],
    );
  }
}

/// Gestos del miniplayer móvil (solo se activan si [enabled] es true):
///  - deslizar a izquierda o derecha -> [onDismiss] (cerrar y detener música)
///  - deslizar hacia abajo           -> [onMinimize] (ocultar sin detener)
///
/// El miniplayer sigue al dedo mientras se arrastra y, si no se supera el
/// umbral, regresa a su posición con una animación.
class _MiniPlayerSwipe extends StatefulWidget {
  const _MiniPlayerSwipe({
    required this.enabled,
    required this.onDismiss,
    required this.onMinimize,
    required this.child,
  });

  final bool enabled;
  final VoidCallback onDismiss;
  final VoidCallback onMinimize;
  final Widget child;

  @override
  State<_MiniPlayerSwipe> createState() => _MiniPlayerSwipeState();
}

class _MiniPlayerSwipeState extends State<_MiniPlayerSwipe>
    with SingleTickerProviderStateMixin {
  static const Duration _settleDuration = Duration(milliseconds: 220);
  static const Duration _dismissDuration = Duration(milliseconds: 200);

  // Tiempo que se espera antes de devolver el offset a cero, para que el
  // miniplayer ya no sea visible cuando vuelva a su posición original.
  static const Duration _dismissResetDelay = Duration(milliseconds: 320);

  // Duración del recorrido final hacia abajo (detrás de la barra).
  static const Duration _minimizeDuration = Duration(milliseconds: 180);

  // Umbrales.
  static const double _dismissDistanceFactor = 0.35; // % del ancho de pantalla
  static const double _dismissVelocity = 700; // px/s
  static const double _minimizeDistance = 36; // px
  static const double _minimizeVelocity = 500; // px/s

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _settleDuration,
  )..addListener(_onTick);

  Offset _offset = Offset.zero;
  Offset _from = Offset.zero;
  Offset _to = Offset.zero;

  // Mientras hay una animación de salida/regreso se ignoran nuevos gestos.
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTick() {
    final t = Curves.easeOutCubic.transform(_controller.value);

    setState(() {
      _offset = Offset.lerp(_from, _to, t)!;
    });
  }

  Future<void> _animateTo(Offset target, {Duration? duration}) {
    _from = _offset;
    _to = target;
    _controller.duration = duration ?? _settleDuration;

    return _controller.forward(from: 0);
  }

  Future<void> _resetAfter(Duration delay) async {
    await Future<void>.delayed(delay);

    if (!mounted) return;

    setState(() {
      _offset = Offset.zero;
      _busy = false;
    });
  }

  Future<void> _settleBack() async {
    if (_busy || _offset == Offset.zero) return;

    _busy = true;
    await _animateTo(Offset.zero);

    if (!mounted) return;
    _busy = false;
  }

  // ---------- Horizontal: cerrar ----------

  void _onHorizontalUpdate(DragUpdateDetails details) {
    if (_busy) return;

    setState(() {
      _offset = Offset(_offset.dx + details.delta.dx, 0);
    });
  }

  Future<void> _onHorizontalEnd(DragEndDetails details) async {
    if (_busy) return;

    final width = MediaQuery.sizeOf(context).width;
    final velocity = details.primaryVelocity ?? 0;
    final flung = velocity.abs() > _dismissVelocity;
    final farEnough = _offset.dx.abs() > width * _dismissDistanceFactor;

    if (!flung && !farEnough) {
      await _settleBack();
      return;
    }

    final direction = flung ? velocity.sign : _offset.dx.sign;

    _busy = true;
    await _animateTo(Offset(direction * width, 0), duration: _dismissDuration);

    if (!mounted) return;

    widget.onDismiss();
    _resetAfter(_dismissResetDelay);
  }

  // ---------- Vertical: minimizar ----------

  void _onVerticalUpdate(DragUpdateDetails details) {
    if (_busy) return;

    // Solo se permite arrastrar hacia abajo.
    final dy = _offset.dy + details.delta.dy;

    setState(() {
      _offset = Offset(0, dy < 0 ? 0 : dy);
    });
  }

  Future<void> _onVerticalEnd(DragEndDetails details) async {
    if (_busy) return;

    final velocity = details.primaryVelocity ?? 0;

    if (_offset.dy > _minimizeDistance || velocity > _minimizeVelocity) {
      _busy = true;

      // Continúa el movimiento desde donde se soltó el dedo, sin pausa,
      // hasta que el miniplayer queda fuera de pantalla (detrás de la barra).
      final height = context.size?.height ?? 120;
      await _animateTo(Offset(0, height), duration: _minimizeDuration);

      if (!mounted) return;

      // El padre fija el estado minimizado sin animar (ya está oculto) y el
      // offset se reinicia en el mismo frame, así que no hay parpadeo.
      widget.onMinimize();

      setState(() {
        _offset = Offset.zero;
        _busy = false;
      });
      return;
    }

    await _settleBack();
  }

  // La opacidad solo cambia en el deslizamiento lateral; al arrastrar hacia
  // abajo el miniplayer se mantiene sólido mientras se esconde.
  double _opacityFor(double width) {
    final horizontal = (_offset.dx.abs() / (width * 0.7))
        .clamp(0.0, 1.0)
        .toDouble();

    return 1.0 - horizontal;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    final width = MediaQuery.sizeOf(context).width;

    return GestureDetector(
      onHorizontalDragUpdate: _onHorizontalUpdate,
      onHorizontalDragEnd: _onHorizontalEnd,
      onHorizontalDragCancel: _settleBack,
      onVerticalDragUpdate: _onVerticalUpdate,
      onVerticalDragEnd: _onVerticalEnd,
      onVerticalDragCancel: _settleBack,
      child: Opacity(
        opacity: _opacityFor(width),
        child: Transform.translate(offset: _offset, child: widget.child),
      ),
    );
  }
}
