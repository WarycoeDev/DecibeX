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

  static const double _expandedWidth = 240;
  static const double _collapsedWidth = 72;

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

  static const List<Widget> _screens = [
    HomeScreen(),
    LibraryScreen(),
    SearchScreen(),
    SettingsScreen(),
  ];

  bool _isDesktop(BuildContext context) {
    return MediaQuery.sizeOf(context).width >= 700;
  }

  void _selectPage(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = _isDesktop(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildTitleBar(context),
            Expanded(
              child: Row(
                children: [
                  if (isDesktop) _buildSidebar(),
                  Expanded(
                    child: IndexedStack(
                      index: _selectedIndex,
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
          const Icon(
            Icons.graphic_eq_rounded,
            color: AppTheme.accent,
            size: 27,
          ),
          const SizedBox(width: 10),
          const Text(
            'DecibeX',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
          ),
          Container(
            height: 24,
            width: 1,
            margin: const EdgeInsets.symmetric(horizontal: 18),
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
    final width = _sidebarExpanded ? _expandedWidth : _collapsedWidth;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      width: width,
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
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: _sidebarExpanded ? 12 : 8,
                vertical: 16,
              ),
              child: _sidebarExpanded
                  ? Row(
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(left: 8),
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
                        SizedBox(
                          width: 40,
                          height: 40,
                          child: IconButton(
                            tooltip: null,
                            padding: EdgeInsets.zero,
                            onPressed: () {
                              setState(() {
                                _sidebarExpanded = false;
                              });
                            },
                            icon: const Icon(
                              Icons.menu_open_rounded,
                              color: AppTheme.accent,
                            ),
                          ),
                        ),
                      ],
                    )
                  : Center(
                      child: SizedBox(
                        width: 40,
                        height: 40,
                        child: IconButton(
                          tooltip: null,
                          padding: EdgeInsets.zero,
                          onPressed: () {
                            setState(() {
                              _sidebarExpanded = true;
                            });
                          },
                          icon: const Icon(
                            Icons.menu_rounded,
                            color: AppTheme.accent,
                          ),
                        ),
                      ),
                    ),
            ),
          ),
          for (int i = 0; i < _titles.length; i++) _buildSidebarItem(i),
          const Spacer(),
          SizedBox(
            height: 28,
            child: ClipRect(
              child: Align(
                alignment: Alignment.topLeft,
                heightFactor: 1,
                child: Transform.translate(
                  offset: const Offset(0, 12),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 150),
                      opacity: _sidebarExpanded ? 1 : 0,
                      child: Text(
                        'DecibeX',
                        maxLines: 1,
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
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
      padding: EdgeInsets.symmetric(
        horizontal: _sidebarExpanded ? 12 : 8,
        vertical: 3,
      ),
      child: Material(
        color: selected ? AppTheme.surfaceVariant : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _selectPage(index),
          child: SizedBox(
            height: 48,
            child: _sidebarExpanded
                ? Row(
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
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Text(
                            _titles[index],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: selected
                                  ? AppTheme.accent
                                  : Theme.of(context).colorScheme.onSurface,
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                : Center(
                    child: Icon(
                      selected ? _selectedIcons[index] : _icons[index],
                      color: selected
                          ? AppTheme.accent
                          : AppTheme.textSecondary,
                      size: 22,
                    ),
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
