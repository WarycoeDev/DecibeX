import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'ui/app_theme.dart';
import 'ui/home/home_screen.dart';
import 'ui/library/library_screen.dart';
import 'ui/search/search_screen.dart';
import 'ui/settings/settings_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;
  bool _sidebarExpanded = true;

  final GlobalKey<LibraryScreenState> _libraryKey =
      GlobalKey<LibraryScreenState>();

  late final PageController _pageController = PageController(
    initialPage: _selectedIndex,
  );

  static const double _expandedWidth = 240;
  static const double _collapsedWidth = 72;

  static const Duration _sidebarAnimationDuration = Duration(milliseconds: 250);

  static const Duration _pageAnimationDuration = Duration(milliseconds: 350);

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
          child: Column(
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
        ),
      ),
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
