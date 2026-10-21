import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../app_theme.dart';

import '../../core/models/song.dart';

import '../../core/services/library_scanner.dart';

import 'song_list_tile.dart';
import '../../core/services/playback_queue.dart';
import '../../core/services/playback_service.dart';
import '../../core/models/playlist.dart';
import '../../core/services/playlist_service.dart';
import '../../core/services/podcast_statistics_service.dart'; // [PODCAST]

import '../../features/library/playlist_name_sheet.dart';
import '../../features/library/playlist_name_dialog.dart';

enum _LibraryTab { songs, podcasts, playlists, favorites, artists, albums }

enum _LayoutSize { compact, medium, expanded }

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
  String? _openedPlaylistId;
  bool _playlistsGridMode = false;
  final PlaylistService _playlistService = PlaylistService.instance;

  double _savedScrollOffset = 0;

  bool _artistsGridMode = false;

  bool _albumsGridMode = false;

  bool _podcastsGridMode = false;

  bool _reorderingFavorites = false;
  bool _reorderingPlaylist = false;

  bool _viewModesLoaded = false;

  bool _savingViewModes = false;

  bool _saveViewModesAgain = false;

  bool get _isDetailView =>
      (_selectedTab == _LibraryTab.artists && _openedArtist != null) ||
      (_selectedTab == _LibraryTab.albums && _openedAlbum != null) ||
      (_selectedTab == _LibraryTab.podcasts && _openedPodcast != null) ||
      (_selectedTab == _LibraryTab.playlists && _openedPlaylistId != null);

  bool get hasOpenDetail => _isDetailView;

  bool get _isCollectionTab =>
      (_selectedTab == _LibraryTab.artists && _openedArtist == null) ||
      (_selectedTab == _LibraryTab.albums && _openedAlbum == null) ||
      (_selectedTab == _LibraryTab.podcasts && _openedPodcast == null) ||
      (_selectedTab == _LibraryTab.playlists && _openedPlaylistId == null);

  bool get _isGridMode => _selectedTab == _LibraryTab.artists
      ? _artistsGridMode
      : _selectedTab == _LibraryTab.albums
      ? _albumsGridMode
      : _selectedTab == _LibraryTab.podcasts
      ? _podcastsGridMode
      : _selectedTab == _LibraryTab.playlists && _playlistsGridMode;

  bool _isUnknownAlbum(String album) {
    final normalized = album.trim().toLowerCase();

    return normalized.isEmpty ||
        normalized == 'desconocido' ||
        normalized == 'unknown' ||
        normalized == 'unknown album';
  }

  _LayoutSize _layoutFor(double width) {
    if (width < 400) return _LayoutSize.compact;
    if (width < 800) return _LayoutSize.medium;
    return _LayoutSize.expanded;
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
    _playlistService.initialize();
    PodcastStatisticsService.instance.init(); // [PODCAST]
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

  /// [CONECTADO] Abre directamente el detalle de un artista/álbum/podcast
  /// desde fuera de la biblioteca (p. ej. desde Buscar).
  void openDetailFromExternal({
    required String title,
    required String? artist,
    required String? album,
    required bool isPodcast,
  }) {
    _savedScrollOffset = 0;

    _navigate(() {
      if (isPodcast) {
        _selectedTab = _LibraryTab.podcasts;
        _openedPodcast = title;
        _openedArtist = null;
        _openedAlbum = null;
        _openedAlbumArtist = null;
        _openedPlaylistId = null;
        _reorderingPlaylist = false;
        _reorderingFavorites = false;
      } else if (album != null) {
        _selectedTab = _LibraryTab.albums;
        _openedAlbum = album;
        _openedAlbumArtist = _isUnknownAlbum(album) ? null : artist;
        _openedArtist = null;
        _openedPodcast = null;
        _openedPlaylistId = null;
        _reorderingPlaylist = false;
        _reorderingFavorites = false;
      } else {
        _selectedTab = _LibraryTab.artists;
        _openedArtist = title;
        _openedAlbum = null;
        _openedAlbumArtist = null;
        _openedPodcast = null;
        _openedPlaylistId = null;
        _reorderingPlaylist = false;
        _reorderingFavorites = false;
      }
    }, scrollTo: 0);
  }

  Future<void> _addSongsToQueue(List<Song> songs) async {
    if (songs.isEmpty) return;

    final queue = PlaybackQueue.instance;

    final playback = PlaybackService.instance;

    if (!queue.isEmpty) {
      final confirmed = await _confirmOverwriteQueue();

      if (!mounted || !confirmed) return;
    }

    queue.clear();

    for (final song in songs) {
      queue.add(song);
    }

    await playback.playQueue();

    await playback.pause();
  }

  Future<void> _playSongs(List<Song> songs) async {
    if (songs.isEmpty) return;

    final queue = PlaybackQueue.instance;

    final playback = PlaybackService.instance;

    if (!queue.isEmpty) {
      final confirmed = await _confirmOverwriteQueue();

      if (!mounted || !confirmed) return;
    }

    queue.clear();

    for (final song in songs) {
      queue.add(song);
    }

    await playback.playQueue();
  }

  Future<bool> _confirmOverwriteQueue() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppTheme.surfaceVariant,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.playlist_remove_rounded),
                  title: const Text('Sobrescribir cola'),
                  onTap: () => Navigator.pop(sheetContext, true),
                ),
                ListTile(
                  leading: const Icon(Icons.close_rounded),
                  title: const Text('Cancelar'),
                  onTap: () => Navigator.pop(sheetContext, false),
                ),
              ],
            ),
          ),
        );
      },
    );

    return result ?? false;
  }

  Future<void> _addAllFavoritesToQueue(List<Song> favorites) async {
    if (favorites.isEmpty) return;

    final queue = PlaybackQueue.instance;

    final playback = PlaybackService.instance;

    if (!queue.isEmpty) {
      final confirmed = await _confirmOverwriteQueue();

      if (!mounted || !confirmed) return;
    }

    queue.clear();

    for (final song in favorites) {
      queue.add(song);
    }

    await playback.playQueue();

    await playback.pause();
  }

  Future<void> _playAllFavorites(List<Song> favorites) async {
    if (favorites.isEmpty) return;

    final queue = PlaybackQueue.instance;

    final playback = PlaybackService.instance;

    if (!queue.isEmpty) {
      final confirmed = await _confirmOverwriteQueue();

      if (!mounted || !confirmed) return;
    }

    queue.clear();

    for (final song in favorites) {
      queue.add(song);
    }

    await playback.playQueue();
  }

  /// Devuelve el episodio en el que debe reanudarse.
  Song? _resumeEpisode(List<Song> episodes) {
    if (episodes.isEmpty) return null;

    final stats = PodcastStatisticsService.instance;

    Song? best;
    DateTime? bestAt;

    for (final ep in episodes) {
      final s = stats.statsFor(ep);
      if (s == null) continue;
      if (s.completed) continue;
      if (s.lastPosition <= const Duration(seconds: 3)) continue;

      final at = s.lastPlayedAt;
      if (at != null && (bestAt == null || at.isAfter(bestAt))) {
        best = ep;
        bestAt = at;
      } else if (best == null) {
        best = ep;
      }
    }

    if (best != null) return best;

    int lastCompletedIndex = -1;

    for (int i = 0; i < episodes.length; i++) {
      if (stats.statsFor(episodes[i])?.completed == true) {
        lastCompletedIndex = i;
      }
    }

    if (lastCompletedIndex < 0) return null;

    final nextIndex = lastCompletedIndex + 1;
    if (nextIndex >= episodes.length) return null;

    return episodes[nextIndex];
  }

  Future<void> _resumePodcastEpisode(Song episode, List<Song> episodes) async {
    final queue = PlaybackQueue.instance;
    final playback = PlaybackService.instance;

    if (episodes.isEmpty) return;

    if (!queue.isEmpty) {
      final confirmed = await _confirmOverwriteQueue();
      if (!mounted || !confirmed) return;
    }

    queue.clear();
    for (final ep in episodes) {
      queue.add(ep);
    }

    await playback.playQueue();

    if (!mounted) return;

    final current = playback.currentSong;
    final sameCurrent =
        current != null &&
        current.filePath?.replaceAll('\\', '/') ==
            episode.filePath?.replaceAll('\\', '/');

    if (!sameCurrent) {
      await playback.playSongFromQueue(episode);
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
            _playlistsGridMode = decoded['playlistsGridMode'] is bool
                ? decoded['playlistsGridMode'] as bool
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
        settings['playlistsGridMode'] = _playlistsGridMode;

        await file.writeAsString(
          const JsonEncoder.withIndent('  ').convert(settings),
          flush: true,
        );
      } while (_saveViewModesAgain);
    } catch (_) {
      // Silencioso: no mostramos SnackBar.
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
      } else if (_selectedTab == _LibraryTab.playlists) {
        _playlistsGridMode = !_playlistsGridMode;
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
      _openedPlaylistId = null;

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
      _openedPlaylistId = null;
      _reorderingPlaylist = false;
    }, scrollTo: _savedScrollOffset);
  }

  Widget _entry(
    int index,
    Widget child, [
    _LayoutSize layout = _LayoutSize.medium,
  ]) {
    final maxItems = layout == _LayoutSize.compact ? 10 : _maxAnimatedItems;

    if (index >= maxItems) return child;

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
        final playlist = _openedPlaylistId == null
            ? null
            : _playlistService.findById(_openedPlaylistId!);
        return playlist == null
            ? <Song>[]
            : _playlistService.resolveSongs(playlist);
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
        return _openedPlaylistId == null
            ? 'Tus playlists'
            : (_playlistService.findById(_openedPlaylistId!)?.name ??
                  'Playlist');

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
        return _openedPlaylistId == null
            ? '${_playlistService.playlists.length} playlists en tu colección'
            : '${songs.length} canciones disponibles';

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
      animation: Listenable.merge([
        _scanner,
        _playlistService,
        PodcastStatisticsService.instance,
      ]),
      builder: (context, child) {
        final songs = _getVisibleSongs();

        return LayoutBuilder(
          builder: (context, constraints) {
            final layout = _layoutFor(constraints.maxWidth);
            final isDesktop = layout == _LayoutSize.expanded;
            final isCompact = layout == _LayoutSize.compact;

            final horizontal = switch (layout) {
              _LayoutSize.compact => 16.0,
              _LayoutSize.medium => 20.0,
              _LayoutSize.expanded => 36.0,
            };
            final top = switch (layout) {
              _LayoutSize.compact => 18.0,
              _LayoutSize.medium => 24.0,
              _LayoutSize.expanded => 32.0,
            };

            return SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1440),
                  child: CustomScrollView(
                    controller: _scrollController,
                    cacheExtent: 600,
                    slivers: [
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          horizontal,
                          top,
                          horizontal,
                          0,
                        ),
                        sliver: SliverToBoxAdapter(
                          child: _buildHeader(context, layout),
                        ),
                      ),
                      SliverPadding(
                        padding: EdgeInsets.only(
                          top: isCompact ? 20 : (isDesktop ? 32 : 24),
                        ),
                        sliver: SliverToBoxAdapter(child: _buildTabs(layout)),
                      ),
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          horizontal,
                          isCompact ? 24 : (isDesktop ? 36 : 28),
                          horizontal,
                          0,
                        ),
                        sliver: SliverToBoxAdapter(
                          child: _entry(
                            0,
                            _buildSectionHeader(context, songs, layout),
                            layout,
                          ),
                        ),
                      ),
                      if (_scanner.isScanning)
                        SliverPadding(
                          padding: EdgeInsets.symmetric(horizontal: horizontal),
                          sliver: const SliverToBoxAdapter(
                            child: LinearProgressIndicator(),
                          ),
                        ),
                      if (_scanner.error != null)
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(
                            horizontal,
                            12,
                            horizontal,
                            0,
                          ),
                          sliver: SliverToBoxAdapter(child: _buildError()),
                        ),
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          horizontal,
                          isCompact ? 12 : 16,
                          horizontal,
                          isCompact ? 24 : 36,
                        ),
                        sliver: _buildContent(songs, isDesktop, layout),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, _LayoutSize layout) {
    final theme = Theme.of(context);
    final isDesktop = layout == _LayoutSize.expanded;
    final isCompact = layout == _LayoutSize.compact;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'TU COLECCIÓN',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelMedium?.copyWith(
            color: AppTheme.accent,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.6,
          ),
        ),
        SizedBox(height: isCompact ? 8 : 10),
        Text(
          'Tu biblioteca',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style:
              (isDesktop
                      ? theme.textTheme.headlineLarge
                      : theme.textTheme.headlineSmall)
                  ?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.8,
                    height: 1.15,
                  ),
        ),
        SizedBox(height: isCompact ? 6 : 8),
        Text(
          'Toda tu música y tus podcasts, organizados en un solo lugar.',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppTheme.textSecondary,
          ),
        ),
        SizedBox(height: isCompact ? 10 : 12),
        Wrap(
          spacing: isCompact ? 8 : 10,
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
              style: OutlinedButton.styleFrom(
                visualDensity: isCompact ? VisualDensity.compact : null,
                padding: isCompact
                    ? const EdgeInsets.symmetric(horizontal: 12, vertical: 8)
                    : null,
              ),
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

  Widget _buildTabs(_LayoutSize layout) {
    final horizontal = switch (layout) {
      _LayoutSize.compact => 16.0,
      _LayoutSize.medium => 20.0,
      _LayoutSize.expanded => 36.0,
    };

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.symmetric(horizontal: horizontal),
      physics: const BouncingScrollPhysics(),
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

  Widget _buildSectionHeader(
    BuildContext context,
    List<Song> songs,
    _LayoutSize layout,
  ) {
    final theme = Theme.of(context);
    final isCompact = layout == _LayoutSize.compact;

    final showPlaybackButtons =
        songs.isNotEmpty &&
        (_selectedTab == _LibraryTab.favorites ||
            (_selectedTab == _LibraryTab.artists && _openedArtist != null) ||
            (_selectedTab == _LibraryTab.albums && _openedAlbum != null) ||
            (_selectedTab == _LibraryTab.podcasts && _openedPodcast != null) ||
            (_selectedTab == _LibraryTab.playlists &&
                _openedPlaylistId != null));

    final showReorder =
        _selectedTab == _LibraryTab.favorites && songs.isNotEmpty;

    const buttonStyle = ButtonStyle(
      fixedSize: WidgetStatePropertyAll(Size(44, 44)),
      padding: WidgetStatePropertyAll(EdgeInsets.zero),
    );

    final actions = <Widget>[
      if (showReorder)
        IconButton(
          style: buttonStyle,
          tooltip: _reorderingFavorites
              ? 'Terminar de ordenar'
              : 'Reordenar favoritos',
          onPressed: () {
            setState(() => _reorderingFavorites = !_reorderingFavorites);
          },
          icon: Icon(
            _reorderingFavorites ? Icons.check_rounded : Icons.reorder_rounded,
          ),
        ),
      if (_selectedTab == _LibraryTab.playlists && _openedPlaylistId != null)
        IconButton(
          style: buttonStyle,
          tooltip: 'Terminar de ordenar',
          onPressed: () =>
              setState(() => _reorderingPlaylist = !_reorderingPlaylist),
          icon: Icon(
            _reorderingPlaylist ? Icons.check_rounded : Icons.reorder_rounded,
          ),
        ),
      if (_selectedTab == _LibraryTab.podcasts && _openedPodcast != null)
        Builder(
          builder: (context) {
            final episode = _resumeEpisode(songs);
            if (episode == null) return const SizedBox.shrink();

            if (isCompact) {
              return Padding(
                padding: const EdgeInsets.only(left: 6),
                child: IconButton.filled(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(44, 44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  tooltip: 'Reanudar',
                  onPressed: () => _resumePodcastEpisode(episode, songs),
                  icon: const Icon(Icons.play_arrow_rounded, size: 22),
                ),
              );
            }

            return Padding(
              padding: const EdgeInsets.only(left: 8),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  minimumSize: const Size(0, 44),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => _resumePodcastEpisode(episode, songs),
                icon: const Icon(Icons.play_arrow_rounded, size: 20),
                label: const Text('Reanudar'),
              ),
            );
          },
        ),
      if (showPlaybackButtons) ...[
        IconButton.filledTonal(
          style: buttonStyle,
          tooltip: 'Agregar a la cola',
          onPressed: () => _addSongsToQueue(songs),
          icon: const Icon(Icons.queue_music_rounded),
        ),
        IconButton.filled(
          style: buttonStyle,
          tooltip: 'Reproducir todo',
          onPressed: () => _playSongs(songs),
          icon: const Icon(Icons.play_arrow_rounded),
        ),
      ],
      if (_selectedTab == _LibraryTab.playlists && _openedPlaylistId == null)
        IconButton(
          style: buttonStyle,
          tooltip: 'Añadir playlist',
          onPressed: _showPlaylistAddMenu,
          icon: const Icon(Icons.add_rounded),
        ),
      if (_isCollectionTab) _buildViewModeButtons(layout),
    ];

    // Fila del título: [atrás] + [título / subtítulo] + [acciones].
    // El título y los controles SIEMPRE comparten la misma línea; solo el
    // subtítulo queda debajo del título dentro de su columna.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
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
          const SizedBox(width: 12),
        ],
        // Título + subtítulo (el subtítulo queda debajo del título).
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              ScrollingTitle(
                title: _sectionTitle,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _sectionSubtitle(songs),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
        // Controles a la derecha, en la MISMA línea que el título.
        if (actions.isNotEmpty) ...[const SizedBox(width: 8), ...actions],
      ],
    );
  }

  Widget _buildViewModeButtons([_LayoutSize layout = _LayoutSize.medium]) {
    final isGrid = _isGridMode;
    final isCompact = layout == _LayoutSize.compact;
    final size = isCompact ? 34.0 : 38.0;

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
            size: size,
            onTap: () {
              if (isGrid) _toggleGridMode();
            },
          ),
          _ViewModeButton(
            icon: Icons.grid_view_rounded,
            selected: isGrid,
            tooltip: 'Vista de cuadrícula',
            size: size,
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

  Future<void> _showPlaylistAddMenu() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.surfaceVariant,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.playlist_add_rounded),
                  title: const Text('Crear playlist'),
                  onTap: () => Navigator.pop(sheetContext, 'create'),
                ),
                ListTile(
                  leading: const Icon(Icons.file_open_rounded),
                  title: const Text('Importar playlist'),
                  onTap: () => Navigator.pop(sheetContext, 'import'),
                ),
                ListTile(
                  leading: const Icon(Icons.close_rounded),
                  title: const Text('Cancelar'),
                  onTap: () => Navigator.pop(sheetContext, 'cancel'),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || action == null || action == 'cancel') return;

    if (action == 'create') {
      await _createPlaylist();
    } else if (action == 'import') {
      await _importPlaylist();
    }
  }

  Future<void> _createPlaylist() async {
    final name = await showPlaylistNameSheet(
      context,
      icon: Icons.queue_music_rounded,
      title: 'Nueva playlist',
      subtitle: 'Ponle un nombre para empezar a organizar tu música.',
      confirmLabel: 'Crear',
      badgeIcon: Icons.add_rounded,
    );

    if (name == null || !mounted) return;

    try {
      await _playlistService.create(name);

      if (!mounted) return;

      setState(() {
        _openedPlaylistId = null;
        _reorderingPlaylist = false;
      });
    } catch (_) {
      // Silencioso.
    }
  }

  Future<void> _importPlaylist() async {
    try {
      final result = await FilePicker.pickFiles(
        dialogTitle: 'Importar playlist',
        type: FileType.custom,
        allowedExtensions: [PlaylistService.extension.replaceFirst('.', '')],
      );

      if (result == null || result.isEmpty) return;

      final picked = result.first;
      final nameLower = picked.name.toLowerCase();

      if (!nameLower.endsWith(PlaylistService.extension.toLowerCase())) {
        return;
      }

      final bytes = await picked.readAsBytes();
      final content = utf8.decode(bytes);

      if (content.trim().isEmpty) return;

      await _playlistService.importFromContent(content);

      if (!mounted) return;

      setState(() {
        _openedPlaylistId = null;
        _reorderingPlaylist = false;
      });
    } catch (_) {
      // Silencioso.
    }
  }

  Future<void> _renamePlaylist(Playlist playlist) async {
    final songs = _playlistService.resolveSongs(playlist);

    final name = await showPlaylistNameSheet(
      context,
      icon: Icons.queue_music_rounded,
      title: 'Renombrar playlist',
      subtitle: 'Elige un nuevo nombre para "${playlist.name}".',
      confirmLabel: 'Guardar',
      initialName: playlist.name,
      songs: songs,
      badgeIcon: Icons.edit_rounded,
    );

    if (name == null || !mounted) return;

    try {
      await _playlistService.rename(playlist, name);
    } catch (_) {
      // Silencioso.
    }
  }

  Future<void> _exportPlaylist(Playlist playlist) async {
    try {
      final content = _playlistService.exportContent(playlist);
      final fileName = _playlistService.exportFileName(playlist);
      final bytes = Uint8List.fromList(utf8.encode(content));

      final output = await FilePicker.saveFile(
        dialogTitle: 'Exportar playlist',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: [PlaylistService.extension.replaceFirst('.', '')],
        bytes: bytes,
      );

      if (output == null) return;

      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        final String path;
        if (output is Uri) {
          path = output.toFilePath();
        } else {
          path = output.toString();
        }
        await File(path).writeAsBytes(bytes, flush: true);
      }
    } catch (_) {
      // Silencioso.
    }
  }

  Future<void> _deletePlaylist(Playlist playlist) async {
    final songs = _playlistService.resolveSongs(playlist);

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);

        return SafeArea(
          top: false,
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppTheme.surfaceVariant, width: 0.7),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Handle superior
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Carátula con badge de advertencia
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: AppTheme.surfaceVariant,
                            width: 0.7,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: _playlistArtwork(songs),
                      ),
                      Positioned(
                        right: -6,
                        bottom: -6,
                        child: Container(
                          width: 32,
                          height: 32,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: const Color(0xFFB3261E),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppTheme.surface,
                              width: 3,
                            ),
                          ),
                          child: const Icon(
                            Icons.delete_outline_rounded,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // Título
                  Text(
                    'Eliminar playlist',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Nombre de la playlist
                  Text(
                    '“${playlist.name}”',
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: AppTheme.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Metadata
                  Text(
                    '${playlist.songCount} ${playlist.songCount == 1 ? "canción" : "canciones"}',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Mensaje de advertencia
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppTheme.surfaceVariant,
                        width: 0.7,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 18,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Los archivos de música no se eliminarán, '
                            'solo la playlist. Esta acción no se puede deshacer.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppTheme.textSecondary,
                              height: 1.45,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Botones
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(sheetContext, false),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            side: BorderSide(
                              color: AppTheme.surfaceVariant,
                              width: 0.9,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text('Cancelar'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => Navigator.pop(sheetContext, true),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFB3261E),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            size: 18,
                          ),
                          label: const Text('Eliminar'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (confirmed != true) return;

    await _playlistService.delete(playlist);

    if (!mounted) return;
    if (_openedPlaylistId == playlist.id) _goBack();
  }

  Future<void> _showAddSongsDialog(Playlist playlist) async {
    final selected = <String>{};
    final librarySongs = _scanner.songs
        .where(
          (song) =>
              !song.isPodcast &&
              song.filePath != null &&
              song.filePath!.isNotEmpty,
        )
        .toList();
    final chosen = await showDialog<List<Song>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Añadir canciones a ${playlist.name}'),
          content: LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 420;
              final height = isCompact
                  ? (MediaQuery.sizeOf(context).height * 0.55).clamp(
                      260.0,
                      420.0,
                    )
                  : 420.0;
              final width = isCompact ? double.infinity : 520.0;

              return SizedBox(
                width: width,
                height: height,
                child: librarySongs.isEmpty
                    ? const Center(
                        child: Text(
                          'No hay canciones disponibles en la biblioteca.',
                        ),
                      )
                    : ListView.builder(
                        itemCount: librarySongs.length,
                        itemBuilder: (context, index) {
                          final song = librarySongs[index];
                          final path = song.filePath!;
                          final alreadyAdded = playlist.songPaths.contains(
                            path,
                          );
                          return CheckboxListTile(
                            value: selected.contains(path) || alreadyAdded,
                            onChanged: alreadyAdded
                                ? null
                                : (value) => setDialogState(() {
                                    if (value == true) {
                                      selected.add(path);
                                    } else {
                                      selected.remove(path);
                                    }
                                  }),
                            title: Text(
                              song.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              song.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            controlAffinity: ListTileControlAffinity.leading,
                          );
                        },
                      ),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                librarySongs
                    .where((song) => selected.contains(song.filePath))
                    .toList(),
              ),
              child: const Text('Añadir seleccionadas'),
            ),
          ],
        ),
      ),
    );
    if (chosen == null || chosen.isEmpty) return;
    await _playlistService.addSongs(playlist, chosen);
  }

  Widget _buildAddSongsButton(Playlist playlist) => Center(
    child: FilledButton.icon(
      onPressed: () => _showAddSongsDialog(playlist),
      icon: const Icon(Icons.playlist_add_rounded),
      label: const Text('Añadir canciones'),
    ),
  );

  void _openPlaylist(Playlist playlist) {
    _savedScrollOffset = _currentScrollOffset;
    _navigate(() {
      _openedPlaylistId = playlist.id;
      _reorderingPlaylist = false;
    }, scrollTo: 0);
  }

  double _gridAspectRatio({
    required double crossAxisExtent,
    required int columns,
    required double crossAxisSpacing,
    required double textHeight,
  }) {
    const double horizontalPadding = 12 * 2;
    const double verticalPadding = 12 * 2;
    const double gap = 10;

    final double cellWidth =
        (crossAxisExtent - crossAxisSpacing * (columns - 1)) / columns;

    final double artworkSize = cellWidth - horizontalPadding;

    final double scaledText =
        MediaQuery.textScalerOf(context).scale(1.0) * textHeight;

    final double cellHeight = verticalPadding + artworkSize + gap + scaledText;

    return cellWidth / cellHeight;
  }

  Widget _buildPlaylistsCollection(bool isDesktop, _LayoutSize layout) {
    final playlists = _playlistService.playlists;
    final isCompact = layout == _LayoutSize.compact;

    if (_playlistsGridMode) {
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

          const double spacing = 12;

          final ratio = _gridAspectRatio(
            crossAxisExtent: width,
            columns: columns,
            crossAxisSpacing: spacing,
            textHeight: 58,
          );

          return SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: spacing,
              mainAxisSpacing: spacing,
              childAspectRatio: ratio,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final playlist = playlists[index];
                final songs = _playlistService.resolveSongs(playlist);

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
                        onTap: () => _openPlaylist(playlist),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              LayoutBuilder(
                                builder: (context, box) {
                                  final size = box.maxWidth;
                                  return SizedBox(
                                    width: size,
                                    height: size,
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: _playlistArtwork(songs),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      playlist.name,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ),
                                  _playlistMenu(playlist),
                                ],
                              ),
                              Text(
                                '${playlist.songCount} canciones',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: AppTheme.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  layout,
                );
              },
              childCount: playlists.length,
              addAutomaticKeepAlives: false,
            ),
          );
        },
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final playlist = playlists[index];
          final songs = _playlistService.resolveSongs(playlist);

          return _entry(
            index,
            RepaintBoundary(
              child: Container(
                margin: EdgeInsets.only(bottom: isCompact ? 6 : 8),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  border: Border.all(
                    color: AppTheme.surfaceVariant,
                    width: 0.7,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => _openPlaylist(playlist),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: isDesktop ? 18 : 12,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 48,
                            height: 48,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: _playlistArtwork(songs),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  playlist.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${playlist.songCount} canciones',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: AppTheme.textSecondary),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 4),
                          _playlistMenu(playlist),
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
            layout,
          );
        },
        childCount: playlists.length,
        addAutomaticKeepAlives: false,
      ),
    );
  }

  Widget _playlistArtwork(List<Song> songs) {
    final path = songs.isNotEmpty ? songs.first.artworkPath : null;

    if (path == null || path.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppTheme.accent.withValues(alpha: 0.25),
              AppTheme.accent.withValues(alpha: 0.08),
            ],
          ),
        ),
        child: Center(
          child: Icon(
            Icons.queue_music_rounded,
            color: AppTheme.accent,
            size: 44,
          ),
        ),
      );
    }

    return Image.file(
      File(path),
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => Center(
        child: Icon(
          Icons.queue_music_rounded,
          color: AppTheme.accent,
          size: 44,
        ),
      ),
    );
  }

  Widget _playlistMenu(Playlist playlist) {
    return IconButton(
      tooltip: 'Opciones de playlist',
      icon: const Icon(Icons.more_horiz_rounded),
      color: AppTheme.textSecondary,
      iconSize: 22,
      visualDensity: VisualDensity.compact,
      splashRadius: 20,
      onPressed: () {
        showModalBottomSheet<String>(
          context: context,
          backgroundColor: AppTheme.surfaceVariant,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (sheetContext) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      leading: const Icon(Icons.edit_outlined),
                      title: const Text('Renombrar'),
                      onTap: () => Navigator.pop(sheetContext, 'rename'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.ios_share_rounded),
                      title: const Text('Exportar'),
                      onTap: () => Navigator.pop(sheetContext, 'export'),
                    ),
                    ListTile(
                      leading: Icon(
                        Icons.delete_outline_rounded,
                        color: Theme.of(sheetContext).colorScheme.error,
                      ),
                      title: Text(
                        'Eliminar',
                        style: TextStyle(
                          color: Theme.of(sheetContext).colorScheme.error,
                        ),
                      ),
                      onTap: () => Navigator.pop(sheetContext, 'delete'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.close_rounded),
                      title: const Text('Cancelar'),
                      onTap: () => Navigator.pop(sheetContext, 'cancel'),
                    ),
                  ],
                ),
              ),
            );
          },
        ).then((action) {
          if (!mounted || action == null || action == 'cancel') return;

          if (action == 'rename') {
            _renamePlaylist(playlist);
          } else if (action == 'export') {
            _exportPlaylist(playlist);
          } else if (action == 'delete') {
            _deletePlaylist(playlist);
          }
        });
      },
    );
  }

  Widget _buildPlaylistSongList(
    Playlist playlist,
    List<Song> songs,
    bool isDesktop,
    _LayoutSize layout,
  ) {
    final songByPath = {
      for (final song in songs)
        if (song.filePath != null) song.filePath!: song,
    };
    final availablePaths = playlist.songPaths
        .where(songByPath.containsKey)
        .toList();
    final missingCount = playlist.songPaths.length - availablePaths.length;

    Future<void> removeSongFromPlaylist(String path) async {
      final paths = List<String>.from(playlist.songPaths)..remove(path);
      await _playlistService.updateSongs(playlist, paths);
      if (mounted) setState(() {});
    }

    final list = _reorderingPlaylist
        ? SliverReorderableList(
            itemCount: availablePaths.length,
            onReorder: (oldIndex, newIndex) async {
              if (newIndex > oldIndex) newIndex--;
              if (oldIndex == newIndex ||
                  newIndex < 0 ||
                  newIndex >= availablePaths.length)
                return;
              final paths = List<String>.from(playlist.songPaths);
              final oldPath = availablePaths[oldIndex];
              final targetPath = availablePaths[newIndex];
              final from = paths.indexOf(oldPath);
              final to = paths.indexOf(targetPath);
              if (from < 0 || to < 0) return;
              final moved = paths.removeAt(from);
              paths.insert(to, moved);
              await _playlistService.updateSongs(playlist, paths);
              if (mounted) setState(() {});
            },
            itemBuilder: (context, index) {
              final path = availablePaths[index];
              final song = songByPath[path]!;
              return ReorderableDelayedDragStartListener(
                key: ValueKey(path),
                index: index,
                child: Row(
                  children: [
                    Expanded(
                      child: _buildSongRow(song: song, isDesktop: isDesktop),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(right: 14),
                      child: Icon(Icons.drag_handle_rounded),
                    ),
                  ],
                ),
              );
            },
          )
        : SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final path = availablePaths[index];
                final song = songByPath[path]!;

                return Dismissible(
                  key: ValueKey<String>('playlist_remove_$path'),
                  direction: DismissDirection.startToEnd,
                  dismissThresholds: const {DismissDirection.startToEnd: 0.3},
                  background: Container(
                    alignment: Alignment.centerLeft,
                    margin: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 4,
                    ),
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
                    unawaited(removeSongFromPlaylist(path));
                  },
                  child: _buildSongRow(song: song, isDesktop: isDesktop),
                );
              },
              childCount: availablePaths.length,
              addAutomaticKeepAlives: false,
            ),
          );
    return SliverMainAxisGroup(
      slivers: [
        if (missingCount > 0)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                '$missingCount canciones no disponibles en la biblioteca. Sus rutas se conservarán en la playlist.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppTheme.textSecondary),
              ),
            ),
          ),
        DecoratedSliver(
          decoration: BoxDecoration(
            color: AppTheme.surface,
            border: Border.all(color: AppTheme.surfaceVariant, width: 0.7),
            borderRadius: BorderRadius.circular(18),
          ),
          sliver: list,
        ),
      ],
    );
  }

  Widget _buildContent(List<Song> songs, bool isDesktop, _LayoutSize layout) {
    if (_selectedTab == _LibraryTab.playlists && _openedPlaylistId == null) {
      if (_playlistService.playlists.isEmpty) {
        return _emptyState(
          icon: Icons.queue_music_rounded,
          title: 'Todavía no hay playlists',
          message: 'Crea o importa una playlist para organizar tus canciones.',
        );
      }
      return _buildPlaylistsCollection(isDesktop, layout);
    }
    if (_selectedTab == _LibraryTab.playlists && _openedPlaylistId != null) {
      final playlist = _playlistService.findById(_openedPlaylistId!);
      if (playlist == null)
        return _emptyState(
          icon: Icons.queue_music_rounded,
          title: 'Playlist no disponible',
          message: 'La playlist pudo haber sido eliminada.',
        );
      if (songs.isEmpty)
        return _emptyState(
          icon: Icons.queue_music_rounded,
          title: 'Esta playlist está vacía',
          message:
              'Añade canciones con el botón de añadir canciones de arriba.',
        );
      return _buildPlaylistSongList(playlist, songs, isDesktop, layout);
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
          ? _buildCollectionGrid(songs, isDesktop, layout, isArtist: true)
          : _buildCollectionList(songs, isDesktop, layout, isArtist: true);
    }

    if (_selectedTab == _LibraryTab.albums && _openedAlbum == null) {
      return _albumsGridMode
          ? _buildCollectionGrid(songs, isDesktop, layout, isArtist: false)
          : _buildCollectionList(songs, isDesktop, layout, isArtist: false);
    }

    if (_selectedTab == _LibraryTab.podcasts && _openedPodcast == null) {
      return _podcastsGridMode
          ? _buildCollectionGrid(
              songs,
              isDesktop,
              layout,
              isArtist: false,
              isPodcast: true,
            )
          : _buildCollectionList(
              songs,
              isDesktop,
              layout,
              isArtist: false,
              isPodcast: true,
            );
    }

    return _buildSongListContainer(
      songs: songs,
      isDesktop: isDesktop,
      layout: layout,
      reordering: _selectedTab == _LibraryTab.favorites && _reorderingFavorites,
    );
  }

  Widget _buildSongListContainer({
    required List<Song> songs,
    required bool isDesktop,
    required _LayoutSize layout,
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
      final allowSwipeToRemove = _selectedTab == _LibraryTab.favorites;

      list = SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final song = songs[index];

            if (!allowSwipeToRemove) {
              return _buildSongRow(song: song, isDesktop: isDesktop);
            }

            final key = song.filePath ?? '${song.title}_${song.artist}_$index';

            return Dismissible(
              key: ValueKey<String>('favorite_remove_$key'),
              direction: DismissDirection.startToEnd,
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
                unawaited(_scanner.setFavorite(song, false));
              },
              child: _buildSongRow(song: song, isDesktop: isDesktop),
            );
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
    bool isDesktop,
    _LayoutSize layout, {
    required bool isArtist,
    bool isPodcast = false,
  }) {
    final isCompact = layout == _LayoutSize.compact;

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

                margin: EdgeInsets.only(bottom: isCompact ? 6 : 8),

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
            layout,
          );
        },

        childCount: songs.length,

        addAutomaticKeepAlives: false,
      ),
    );
  }

  Widget _buildCollectionGrid(
    List<Song> songs,
    bool isDesktop,
    _LayoutSize layout, {
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

        const double spacing = 12;

        final ratio = _gridAspectRatio(
          crossAxisExtent: width,
          columns: columns,
          crossAxisSpacing: spacing,
          textHeight: 40,
        );

        return SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            childAspectRatio: ratio,
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
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            LayoutBuilder(
                              builder: (context, box) {
                                final size = box.maxWidth;
                                return SizedBox(
                                  width: size,
                                  height: size,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: _buildGridArtwork(
                                      song,
                                      isArtist,
                                      isPodcast: isPodcast,
                                    ),
                                  ),
                                );
                              },
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
                layout,
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
      return Center(child: Icon(icon, size: 44, color: AppTheme.accent));
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
    final tile = SongListTile(
      key: ValueKey(song.filePath ?? song.title),
      song: song,
      isDesktop: isDesktop,
      onFavoriteChanged: (favorite) {
        _scanner.setFavorite(song, favorite);
      },
    );

    final isPodcastEpisode =
        song.isPodcast &&
        _selectedTab == _LibraryTab.podcasts &&
        _openedPodcast != null;

    if (!isPodcastEpisode) {
      return RepaintBoundary(
        child: Row(
          children: [
            Expanded(child: tile),
            if (showDragHandle)
              const Padding(
                padding: EdgeInsets.only(right: 14),
                child: Icon(Icons.drag_handle_rounded),
              ),
          ],
        ),
      );
    }

    final stats = PodcastStatisticsService.instance.statsFor(song);
    final completed = stats?.completed ?? false;
    final duration = stats?.duration ?? Duration.zero;
    final position = stats?.lastPosition ?? Duration.zero;

    final ratio = (duration.inMilliseconds > 0 && !completed)
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return RepaintBoundary(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Stack(
                  children: [
                    tile,
                    if (completed)
                      const Positioned(
                        top: 6,
                        left: 6,
                        child: _PodcastCompletedBadge(),
                      ),
                  ],
                ),
                if (!completed && ratio > 0)
                  Padding(
                    padding: const EdgeInsets.only(
                      left: 12,
                      right: 12,
                      bottom: 6,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: ratio,
                        minHeight: 3,
                        backgroundColor: AppTheme.surfaceVariant,
                        valueColor: AlwaysStoppedAnimation(AppTheme.accent),
                      ),
                    ),
                  ),
              ],
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

class _PodcastCompletedBadge extends StatelessWidget {
  const _PodcastCompletedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.accent,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.25),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_rounded, size: 12, color: Colors.white),
        ],
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

  final double size;

  const _ViewModeButton({
    required this.icon,
    required this.selected,
    required this.tooltip,
    required this.onTap,
    this.size = 38,
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
            width: size,
            height: size - 2,
            child: Icon(
              icon,
              size: size * 0.55,
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
