import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../app_theme.dart';
import '../../core/models/song.dart';
import '../../core/services/library_scanner.dart';
import 'song_list_tile.dart';

enum _LibraryTab { songs, podcasts, playlists, favorites, artists, albums }

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  LibraryScreenState createState() => LibraryScreenState();
}

class LibraryScreenState extends State<LibraryScreen>
    with SingleTickerProviderStateMixin {
  static const Duration _entryDuration = Duration(milliseconds: 450);
  static const int _maxAnimatedItems = 16;
  static const String _settingsFileName = 'settings.decibex';

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
  final ScrollController _scrollController = ScrollController();

  late final AnimationController _entryController;

  _LibraryTab _selectedTab = _LibraryTab.songs;
  String? _openedArtist;
  String? _openedAlbum;
  String? _openedAlbumArtist;
  String? _openedPodcast;

  double _savedScrollOffset = 0;
  bool _artistsGridMode = false;
  bool _albumsGridMode = false;
  bool _podcastsGridMode = false;
  bool _reorderingFavorites = false;
  bool _viewModesLoaded = false;
  bool _savingViewModes = false;
  bool _saveViewModesAgain = false;

  bool get _isDetailView =>
      (_selectedTab == _LibraryTab.artists && _openedArtist != null) ||
      (_selectedTab == _LibraryTab.albums && _openedAlbum != null) ||
      (_selectedTab == _LibraryTab.podcasts && _openedPodcast != null);

  bool get hasOpenDetail => _isDetailView;

  bool get _isCollectionTab =>
      (_selectedTab == _LibraryTab.artists && _openedArtist == null) ||
      (_selectedTab == _LibraryTab.albums && _openedAlbum == null) ||
      (_selectedTab == _LibraryTab.podcasts && _openedPodcast == null);

  bool get _isGridMode => _selectedTab == _LibraryTab.artists
      ? _artistsGridMode
      : _selectedTab == _LibraryTab.albums
      ? _albumsGridMode
      : _selectedTab == _LibraryTab.podcasts && _podcastsGridMode;

  bool _isUnknownAlbum(String album) {
    final normalized = album.trim().toLowerCase();

    return normalized.isEmpty ||
        normalized == 'desconocido' ||
        normalized == 'unknown' ||
        normalized == 'unknown album';
  }

  @override
  void initState() {
    super.initState();

    _entryController = AnimationController(
      vsync: this,
      duration: _entryDuration,
      value: 1,
    );

    _loadViewModes();
    _scanner.initialize();
  }

  @override
  void dispose() {
    _entryController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void handleSystemBack() {
    if (_isDetailView) {
      _goBack();
    }
  }

  Future<Directory> _getSettingsDirectory() async {
    if (Platform.isAndroid) {
      final externalDirectory = await getExternalStorageDirectory();

      if (externalDirectory != null) {
        return Directory('${externalDirectory.path}/data');
      }
    }

    return getApplicationSupportDirectory();
  }

  Future<File> _getSettingsFile() async {
    final directory = await _getSettingsDirectory();

    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    return File('${directory.path}/$_settingsFileName');
  }

  Future<void> _loadViewModes() async {
    try {
      final file = await _getSettingsFile();

      if (await file.exists()) {
        final content = await file.readAsString();

        if (content.trim().isNotEmpty) {
          final decoded = jsonDecode(content);

          if (decoded is Map<String, dynamic>) {
            _artistsGridMode = decoded['artistsGridMode'] is bool
                ? decoded['artistsGridMode'] as bool
                : false;
            _albumsGridMode = decoded['albumsGridMode'] is bool
                ? decoded['albumsGridMode'] as bool
                : false;
            _podcastsGridMode = decoded['podcastsGridMode'] is bool
                ? decoded['podcastsGridMode'] as bool
                : false;
          }
        }
      }
    } catch (_) {}

    if (!mounted) return;

    setState(() {
      _viewModesLoaded = true;
    });
  }

  Future<void> _saveViewModes() async {
    if (!_viewModesLoaded) return;

    if (_savingViewModes) {
      _saveViewModesAgain = true;
      return;
    }

    _savingViewModes = true;

    try {
      do {
        _saveViewModesAgain = false;

        final file = await _getSettingsFile();
        Map<String, dynamic> settings = {};

        if (await file.exists()) {
          try {
            final content = await file.readAsString();

            if (content.trim().isNotEmpty) {
              final decoded = jsonDecode(content);

              if (decoded is Map<String, dynamic>) {
                settings = decoded;
              }
            }
          } catch (_) {}
        }

        settings['artistsGridMode'] = _artistsGridMode;
        settings['albumsGridMode'] = _albumsGridMode;
        settings['podcastsGridMode'] = _podcastsGridMode;

        await file.writeAsString(
          const JsonEncoder.withIndent('  ').convert(settings),
          flush: true,
        );
      } while (_saveViewModesAgain);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo guardar el modo de visualización.'),
          ),
        );
      }
    } finally {
      _savingViewModes = false;
    }
  }

  void _toggleGridMode() {
    if (!_isCollectionTab) return;

    setState(() {
      if (_selectedTab == _LibraryTab.artists) {
        _artistsGridMode = !_artistsGridMode;
      } else if (_selectedTab == _LibraryTab.albums) {
        _albumsGridMode = !_albumsGridMode;
      } else if (_selectedTab == _LibraryTab.podcasts) {
        _podcastsGridMode = !_podcastsGridMode;
      }
    });

    _entryController.forward(from: 0);
    _saveViewModes();
  }

  double get _currentScrollOffset =>
      _scrollController.hasClients ? _scrollController.offset : 0;

  void _navigate(VoidCallback change, {required double scrollTo}) {
    setState(change);
    _entryController.forward(from: 0);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;

      final position = _scrollController.position;
      final target = scrollTo
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();

      if ((position.pixels - target).abs() > 0.5) {
        _scrollController.jumpTo(target);
      }
    });
  }

  void _selectTab(_LibraryTab tab) {
    if (tab == _selectedTab) {
      if (_isDetailView) _goBack();
      return;
    }

    _savedScrollOffset = 0;

    _navigate(() {
      _selectedTab = tab;
      _openedArtist = null;
      _openedAlbum = null;
      _openedAlbumArtist = null;
      _openedPodcast = null;
      _reorderingFavorites = false;
    }, scrollTo: 0);
  }

  void _openArtist(String artist) {
    _savedScrollOffset = _currentScrollOffset;

    _navigate(() {
      _openedArtist = artist;
      _openedAlbum = null;
      _openedAlbumArtist = null;
    }, scrollTo: 0);
  }

  void _openAlbum(Song song) {
    _savedScrollOffset = _currentScrollOffset;

    _navigate(() {
      _openedAlbum = song.album;
      _openedAlbumArtist = _isUnknownAlbum(song.album) ? null : song.artist;
      _openedArtist = null;
    }, scrollTo: 0);
  }

  void _openPodcast(Song song) {
    _savedScrollOffset = _currentScrollOffset;

    _navigate(() {
      _openedPodcast = song.album;
      _openedArtist = null;
      _openedAlbum = null;
      _openedAlbumArtist = null;
    }, scrollTo: 0);
  }

  void _goBack() {
    if (!_isDetailView) return;

    _navigate(() {
      _openedArtist = null;
      _openedAlbum = null;
      _openedAlbumArtist = null;
      _openedPodcast = null;
    }, scrollTo: _savedScrollOffset);
  }

  Widget _entry(int index, Widget child) {
    if (index >= _maxAnimatedItems) return child;

    return _EntryTransition(
      animation: _entryController,
      index: index,
      child: child,
    );
  }

  List<Song> _getVisibleSongs() {
    final allSongs = _scanner.songs;
    final musicSongs = allSongs.where((song) => !song.isPodcast).toList();
    final podcastSongs = allSongs.where((song) => song.isPodcast).toList();

    if (_selectedTab == _LibraryTab.podcasts && _openedPodcast != null) {
      return podcastSongs.where((song) {
        if (_isUnknownAlbum(_openedPodcast!)) {
          return _isUnknownAlbum(song.album);
        }
        return song.album == _openedPodcast;
      }).toList();
    }

    if (_selectedTab == _LibraryTab.podcasts) {
      final unique = <String, Song>{};

      for (final song in podcastSongs) {
        final key = _isUnknownAlbum(song.album)
            ? '__unknown_podcast__'
            : song.album.trim();
        unique.putIfAbsent(key, () => song);
      }

      return unique.values.toList();
    }

    if (_selectedTab == _LibraryTab.artists && _openedArtist != null) {
      return musicSongs.where((song) => song.artist == _openedArtist).toList();
    }

    if (_selectedTab == _LibraryTab.albums && _openedAlbum != null) {
      return musicSongs.where((song) {
        if (_isUnknownAlbum(_openedAlbum!)) {
          return _isUnknownAlbum(song.album);
        }

        return song.album == _openedAlbum && song.artist == _openedAlbumArtist;
      }).toList();
    }

    switch (_selectedTab) {
      case _LibraryTab.songs:
        return musicSongs;
      case _LibraryTab.podcasts:
        final unique = <String, Song>{};

        for (final song in podcastSongs) {
          final key = _isUnknownAlbum(song.album)
              ? '__unknown_podcast__'
              : song.album.trim();
          unique.putIfAbsent(key, () => song);
        }

        return unique.values.toList();
      case _LibraryTab.favorites:
        return _scanner.orderFavorites(allSongs.where((song) => song.favorite));
      case _LibraryTab.artists:
        final unique = <String, Song>{};

        for (final song in musicSongs) {
          unique.putIfAbsent(song.artist, () => song);
        }

        return unique.values.toList();
      case _LibraryTab.albums:
        final unique = <String, Song>{};

        for (final song in musicSongs) {
          final key = _isUnknownAlbum(song.album)
              ? '__unknown_album__'
              : '${song.artist}\u0000${song.album}';

          unique.putIfAbsent(key, () => song);
        }

        return unique.values.toList();
      case _LibraryTab.playlists:
        return [];
    }
  }

  String get _sectionTitle {
    if (_selectedTab == _LibraryTab.artists && _openedArtist != null) {
      return _openedArtist!;
    }

    if (_selectedTab == _LibraryTab.albums && _openedAlbum != null) {
      return _isUnknownAlbum(_openedAlbum!) ? 'Desconocido' : _openedAlbum!;
    }

    if (_selectedTab == _LibraryTab.podcasts && _openedPodcast != null) {
      return _isUnknownAlbum(_openedPodcast!) ? 'Desconocido' : _openedPodcast!;
    }

    switch (_selectedTab) {
      case _LibraryTab.songs:
        return 'Todas las canciones';
      case _LibraryTab.podcasts:
        return 'Tus podcasts';
      case _LibraryTab.playlists:
        return 'Tus playlists';
      case _LibraryTab.favorites:
        return 'Tus favoritos';
      case _LibraryTab.artists:
        return 'Tus artistas';
      case _LibraryTab.albums:
        return 'Tus álbumes';
    }
  }

  String _sectionSubtitle(List<Song> songs) {
    if (_selectedTab == _LibraryTab.artists && _openedArtist != null) {
      return '${songs.length} canciones de este artista';
    }

    if (_selectedTab == _LibraryTab.albums && _openedAlbum != null) {
      return '${songs.length} canciones de este álbum';
    }

    if (_selectedTab == _LibraryTab.podcasts && _openedPodcast != null) {
      return '${songs.length} episodios de este podcast';
    }

    switch (_selectedTab) {
      case _LibraryTab.songs:
        return '${_scanner.songCount} canciones en tu colección';
      case _LibraryTab.podcasts:
        return '${songs.length} podcasts en tu colección';
      case _LibraryTab.playlists:
        return 'Tus listas de reproducción';
      case _LibraryTab.favorites:
        return '${songs.length} elementos favoritos';
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
                  controller: _scrollController,
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
                        child: _entry(0, _buildSectionHeader(context, songs)),
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
          'Toda tu música y tus podcasts, organizados en un solo lugar.',
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
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          for (int i = 0; i < _tabs.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            _LibraryTabButton(
              data: _tabs[i],
              selected: _selectedTab == _tabs[i].tab,
              onTap: () => _selectTab(_tabs[i].tab),
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
        if (_isDetailView) ...[
          Material(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: _goBack,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.surfaceVariant,
                    width: 0.7,
                  ),
                ),
                child: const Icon(Icons.arrow_back_rounded),
              ),
            ),
          ),
          const SizedBox(width: 14),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _sectionTitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
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
        if (_selectedTab == _LibraryTab.favorites && songs.isNotEmpty) ...[
          const SizedBox(width: 8),
          IconButton(
            tooltip: _reorderingFavorites
                ? 'Terminar de ordenar'
                : 'Reordenar favoritos',
            onPressed: () {
              setState(() => _reorderingFavorites = !_reorderingFavorites);
            },
            icon: Icon(
              _reorderingFavorites
                  ? Icons.check_rounded
                  : Icons.reorder_rounded,
            ),
          ),
        ],
        if (_isCollectionTab) ...[
          const SizedBox(width: 12),
          _buildViewModeButtons(),
        ],
      ],
    );
  }

  Widget _buildViewModeButtons() {
    final isGrid = _isGridMode;

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.surfaceVariant, width: 0.7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ViewModeButton(
            icon: Icons.view_list_rounded,
            selected: !isGrid,
            tooltip: 'Vista de lista',
            onTap: () {
              if (isGrid) _toggleGridMode();
            },
          ),
          _ViewModeButton(
            icon: Icons.grid_view_rounded,
            selected: isGrid,
            tooltip: 'Vista de cuadrícula',
            onTap: () {
              if (!isGrid) _toggleGridMode();
            },
          ),
        ],
      ),
    );
  }

  Widget _emptyState({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return SliverToBoxAdapter(
      child: _entry(
        0,
        _EmptyLibraryState(icon: icon, title: title, message: message),
      ),
    );
  }

  Widget _buildContent(List<Song> songs, bool isDesktop) {
    if (_selectedTab == _LibraryTab.playlists) {
      return _emptyState(
        icon: Icons.queue_music_rounded,
        title: 'Todavía no hay playlists',
        message: 'Tus listas de reproducción aparecerán aquí.',
      );
    }

    if (songs.isEmpty) {
      final favorites = _selectedTab == _LibraryTab.favorites;
      final podcasts = _selectedTab == _LibraryTab.podcasts;
      final artistDetail =
          _selectedTab == _LibraryTab.artists && _openedArtist != null;
      final albumDetail =
          _selectedTab == _LibraryTab.albums && _openedAlbum != null;
      final podcastDetail =
          _selectedTab == _LibraryTab.podcasts && _openedPodcast != null;

      return _emptyState(
        icon: podcasts
            ? Icons.podcasts_rounded
            : favorites
            ? Icons.favorite_border_rounded
            : artistDetail
            ? Icons.person_outline_rounded
            : albumDetail
            ? Icons.album_outlined
            : Icons.music_off_rounded,
        title: podcasts && !podcastDetail
            ? 'Todavía no hay podcasts'
            : podcastDetail
            ? 'No hay episodios de este podcast'
            : favorites
            ? 'Todavía no tienes favoritos'
            : artistDetail
            ? 'No hay canciones de este artista'
            : albumDetail
            ? 'No hay canciones de este álbum'
            : 'Tu biblioteca está vacía',
        message: podcasts && !podcastDetail
            ? 'Agrega directorios en Configuración > Biblioteca > Podcasts y escanea tus archivos.'
            : podcastDetail
            ? 'Los episodios aparecerán aquí cuando estén disponibles en tu biblioteca.'
            : favorites
            ? 'Marca canciones o episodios como favoritos para verlos aquí.'
            : artistDetail || albumDetail
            ? 'Las canciones aparecerán aquí cuando estén disponibles en tu biblioteca.'
            : 'Agrega directorios en Configuración > Biblioteca y escanea tus archivos.',
      );
    }

    if (_selectedTab == _LibraryTab.artists && _openedArtist == null) {
      return _artistsGridMode
          ? _buildCollectionGrid(songs, isDesktop, isArtist: true)
          : _buildCollectionList(songs, isDesktop, isArtist: true);
    }

    if (_selectedTab == _LibraryTab.albums && _openedAlbum == null) {
      return _albumsGridMode
          ? _buildCollectionGrid(songs, isDesktop, isArtist: false)
          : _buildCollectionList(songs, isDesktop, isArtist: false);
    }

    if (_selectedTab == _LibraryTab.podcasts && _openedPodcast == null) {
      return _podcastsGridMode
          ? _buildCollectionGrid(
              songs,
              isDesktop,
              isArtist: false,
              isPodcast: true,
            )
          : _buildCollectionList(
              songs,
              isDesktop,
              isArtist: false,
              isPodcast: true,
            );
    }

    return _buildSongListContainer(
      songs: songs,
      isDesktop: isDesktop,
      reordering: _selectedTab == _LibraryTab.favorites && _reorderingFavorites,
    );
  }

  Widget _buildSongListContainer({
    required List<Song> songs,
    required bool isDesktop,
    required bool reordering,
  }) {
    final Widget list;

    if (reordering) {
      list = SliverReorderableList(
        itemCount: songs.length,
        onReorder: (oldIndex, newIndex) {
          if (newIndex > oldIndex) {
            newIndex--;
          }

          if (oldIndex == newIndex) return;

          final reordered = List<Song>.from(songs);
          final song = reordered.removeAt(oldIndex);
          reordered.insert(newIndex, song);

          _scanner.setFavoriteOrder(reordered);
        },
        itemBuilder: (context, index) {
          final song = songs[index];

          return ReorderableDelayedDragStartListener(
            key: ValueKey(song.filePath ?? '${song.title}-$index'),
            index: index,
            child: _buildSongRow(
              song: song,
              isDesktop: isDesktop,
              showDragHandle: true,
            ),
          );
        },
      );
    } else {
      list = SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            return _buildSongRow(song: songs[index], isDesktop: isDesktop);
          },
          childCount: songs.length,
          addAutomaticKeepAlives: false,
          addRepaintBoundaries: true,
        ),
      );
    }

    return DecoratedSliver(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border.all(color: AppTheme.surfaceVariant, width: 0.7),
        borderRadius: BorderRadius.circular(18),
      ),
      sliver: list,
    );
  }

  Widget _buildCollectionArtwork(
    Song song,
    bool isArtist, {
    bool isPodcast = false,
  }) {
    final artworkPath = song.artworkPath;
    final fallbackIcon = isArtist
        ? Icons.person_rounded
        : isPodcast
        ? Icons.podcasts_rounded
        : Icons.album_rounded;

    Widget placeholder() {
      return Container(
        color: AppTheme.accent.withValues(alpha: 0.12),
        alignment: Alignment.center,
        child: Icon(fallbackIcon, color: AppTheme.accent, size: 28),
      );
    }

    if (artworkPath == null || artworkPath.isEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(width: 48, height: 48, child: placeholder()),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 48,
        height: 48,
        child: Image.file(
          File(artworkPath),
          fit: BoxFit.cover,
          cacheWidth: 144,
          cacheHeight: 144,
          errorBuilder: (context, error, stackTrace) => placeholder(),
        ),
      ),
    );
  }

  Widget _buildCollectionList(
    List<Song> songs,
    bool isDesktop, {
    required bool isArtist,
    bool isPodcast = false,
  }) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final song = songs[index];
          final title = isArtist
              ? (song.artist.isEmpty ? 'Desconocido' : song.artist)
              : (_isUnknownAlbum(song.album) ? 'Desconocido' : song.album);

          return _entry(
            index,
            RepaintBoundary(
              child: Container(
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  border: Border.all(
                    color: AppTheme.surfaceVariant,
                    width: 0.7,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                margin: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () {
                      if (isArtist) {
                        _openArtist(song.artist);
                      } else if (isPodcast) {
                        _openPodcast(song);
                      } else {
                        _openAlbum(song);
                      }
                    },
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: isDesktop ? 18 : 12,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          _buildCollectionArtwork(
                            song,
                            isArtist,
                            isPodcast: isPodcast,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: AppTheme.textSecondary,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
        childCount: songs.length,
        addAutomaticKeepAlives: false,
      ),
    );
  }

  Widget _buildCollectionGrid(
    List<Song> songs,
    bool isDesktop, {
    required bool isArtist,
    bool isPodcast = false,
  }) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.crossAxisExtent;
        final columns = width >= 1100
            ? 5
            : width >= 800
            ? 4
            : width >= 540
            ? 3
            : 2;

        return SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: isDesktop ? 0.88 : 0.76,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final song = songs[index];
              final title = isArtist
                  ? (song.artist.isEmpty ? 'Desconocido' : song.artist)
                  : (_isUnknownAlbum(song.album) ? 'Desconocido' : song.album);

              return _entry(
                index,
                RepaintBoundary(
                  child: Material(
                    color: AppTheme.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: AppTheme.surfaceVariant,
                        width: 0.7,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () {
                        if (isArtist) {
                          _openArtist(song.artist);
                        } else if (isPodcast) {
                          _openPodcast(song);
                        } else {
                          _openAlbum(song);
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: SizedBox(
                                width: double.infinity,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: _buildGridArtwork(
                                    song,
                                    isArtist,
                                    isPodcast: isPodcast,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
            childCount: songs.length,
            addAutomaticKeepAlives: false,
          ),
        );
      },
    );
  }

  Widget _buildGridArtwork(Song song, bool isArtist, {bool isPodcast = false}) {
    final path = song.artworkPath;
    final icon = isArtist
        ? Icons.person_rounded
        : isPodcast
        ? Icons.podcasts_rounded
        : Icons.album_rounded;

    Widget placeholder() {
      return Container(
        color: AppTheme.accent.withValues(alpha: 0.12),
        alignment: Alignment.center,
        child: Icon(icon, size: 44, color: AppTheme.accent),
      );
    }

    if (path == null || path.isEmpty) return placeholder();

    return Image.file(
      File(path),
      fit: BoxFit.cover,
      cacheWidth: 360,
      cacheHeight: 360,
      errorBuilder: (context, error, stackTrace) => placeholder(),
    );
  }

  Widget _buildSongRow({
    required Song song,
    required bool isDesktop,
    bool showDragHandle = false,
  }) {
    return RepaintBoundary(
      child: Row(
        children: [
          Expanded(
            child: SongListTile(
              key: ValueKey(song.filePath ?? song.title),
              song: song,
              isDesktop: isDesktop,
              onFavoriteChanged: (favorite) {
                _scanner.setFavorite(song, favorite);
              },
            ),
          ),
          if (showDragHandle)
            const Padding(
              padding: EdgeInsets.only(right: 14),
              child: Icon(Icons.drag_handle_rounded),
            ),
        ],
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

class _EntryTransition extends StatefulWidget {
  final Animation<double> animation;
  final int index;
  final Widget child;

  const _EntryTransition({
    required this.animation,
    required this.index,
    required this.child,
  });

  static const double stagger = 0.03;
  static const double span = 0.55;
  static const double distance = 14;

  @override
  State<_EntryTransition> createState() => _EntryTransitionState();
}

class _EntryTransitionState extends State<_EntryTransition> {
  late CurvedAnimation _curved;

  @override
  void initState() {
    super.initState();
    _curved = _createCurve();
  }

  @override
  void didUpdateWidget(covariant _EntryTransition oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.animation != widget.animation ||
        oldWidget.index != widget.index) {
      _curved.dispose();
      _curved = _createCurve();
    }
  }

  CurvedAnimation _createCurve() {
    final double begin = (widget.index * _EntryTransition.stagger)
        .clamp(0.0, 1.0)
        .toDouble();
    final double end = (begin + _EntryTransition.span)
        .clamp(begin, 1.0)
        .toDouble();

    return CurvedAnimation(
      parent: widget.animation,
      curve: Interval(begin, end, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _curved.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _curved,
      child: AnimatedBuilder(
        animation: _curved,
        child: widget.child,
        builder: (context, child) {
          return Transform.translate(
            offset: Offset(0, (1 - _curved.value) * _EntryTransition.distance),
            child: child,
          );
        },
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

class _ViewModeButton extends StatelessWidget {
  final IconData icon;
  final bool selected;
  final String tooltip;
  final VoidCallback onTap;

  const _ViewModeButton({
    required this.icon,
    required this.selected,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: selected
            ? AppTheme.accent.withValues(alpha: 0.15)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(9),
          child: SizedBox(
            width: 38,
            height: 36,
            child: Icon(
              icon,
              size: 21,
              color: selected ? AppTheme.accent : AppTheme.textSecondary,
            ),
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
