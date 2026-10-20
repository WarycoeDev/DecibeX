import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../../core/models/song.dart';
import '../../core/services/library_scanner.dart';
import '../../core/services/playback_queue.dart';
import '../../core/services/playback_service.dart';
import '../library/song_list_tile.dart';

enum _SearchFilter { all, songs, artists, albums, podcasts }

/// Callback opcional para que la pantalla padre (p. ej. la shell de la app)
/// navegue al detalle de un artista/álbum/podcast. Si no se proporciona,
/// se muestra un SnackBar informativo.
///
/// Se permite `FutureOr<void>` para que la implementación pueda esperar
/// (p. ej. a que LibraryScreen esté montado) sin romper el contrato.
typedef SearchNavigationCallback =
    FutureOr<void> Function({
      required String title,
      required String? artist,
      required String? album,
      required bool isPodcast,
    });

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, this.onOpenDetail});

  /// [CONECTADO] Permite que la app navegue al detalle real.
  final SearchNavigationCallback? onOpenDetail;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen>
    with SingleTickerProviderStateMixin {
  static const Duration _entryDuration = Duration(milliseconds: 450);
  static const int _maxAnimatedItems = 16;

  static const List<_SearchFilterData> _filters = [
    _SearchFilterData(_SearchFilter.all, 'Todo', Icons.search_rounded),
    _SearchFilterData(
      _SearchFilter.songs,
      'Canciones',
      Icons.music_note_rounded,
    ),
    _SearchFilterData(_SearchFilter.artists, 'Artistas', Icons.person_rounded),
    _SearchFilterData(_SearchFilter.albums, 'Álbumes', Icons.album_rounded),
    _SearchFilterData(
      _SearchFilter.podcasts,
      'Podcasts',
      Icons.podcasts_rounded,
    ),
  ];

  final LibraryScanner _scanner = LibraryScanner.instance;
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  late final AnimationController _entryController;

  _SearchFilter _selectedFilter = _SearchFilter.all;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: _entryDuration,
      value: 1,
    );
    _scanner.initialize();
  }

  @override
  void dispose() {
    _entryController.dispose();
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  bool _isUnknownAlbum(String album) {
    final normalized = album.trim().toLowerCase();
    return normalized.isEmpty ||
        normalized == 'desconocido' ||
        normalized == 'unknown' ||
        normalized == 'unknown album';
  }

  String _normalize(String value) =>
      value.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');

  // ---------------------------------------------------------------
  // Reproducción [CONECTADO]
  // ---------------------------------------------------------------

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

  // ---------------------------------------------------------------
  // Resultados [CONECTADO a LibraryScanner]
  // ---------------------------------------------------------------

  List<Song> _matchingSongs() {
    if (_query.isEmpty) return const [];
    final q = _normalize(_query);

    final Iterable<Song> source;
    switch (_selectedFilter) {
      case _SearchFilter.songs:
        source = _scanner.musicSongs;
        break;
      case _SearchFilter.podcasts:
        source = _scanner.podcasts;
        break;
      case _SearchFilter.all:
        source = _scanner.songs;
        break;
      case _SearchFilter.artists:
      case _SearchFilter.albums:
        source = _scanner.musicSongs;
        break;
    }

    return source.where((song) {
      final haystack = _normalize('${song.title} ${song.artist} ${song.album}');
      return haystack.contains(q);
    }).toList();
  }

  List<Song> _groupedSongs({required bool isArtist, required bool isPodcast}) {
    if (_query.isEmpty) return const [];
    final q = _normalize(_query);
    final unique = <String, Song>{};

    final Iterable<Song> source = isPodcast
        ? _scanner.podcasts
        : _scanner.musicSongs;

    for (final song in source) {
      final title = isArtist
          ? (song.artist.isEmpty ? 'Desconocido' : song.artist)
          : (_isUnknownAlbum(song.album) ? 'Desconocido' : song.album);

      if (!_normalize(title).contains(q)) continue;

      final key = isArtist ? title : '${song.artist}\u0000$title';
      unique.putIfAbsent(key, () => song);
    }

    return unique.values.toList();
  }

  // ---------------------------------------------------------------
  // Acciones de UI
  // ---------------------------------------------------------------

  void _onQueryChanged(String value) {
    setState(() => _query = value);
    _entryController.forward(from: 0);
  }

  void _clearQuery() {
    _controller.clear();
    _focusNode.requestFocus();
    _onQueryChanged('');
  }

  void _selectFilter(_SearchFilter filter) {
    if (filter == _selectedFilter) return;
    setState(() => _selectedFilter = filter);
    _entryController.forward(from: 0);
  }

  /// [CONECTADO] Abre el detalle usando el callback del padre.
  void _openDetail({
    required String title,
    required String? artist,
    required String? album,
    required bool isPodcast,
  }) {
    final callback = widget.onOpenDetail;
    if (callback != null) {
      // Se descarta el Future (si lo hay): el callback se encarga de
      // esperar internamente a que la biblioteca esté lista.
      callback(
        title: title,
        artist: artist,
        album: album,
        isPodcast: isPodcast,
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Abrir detalle de "$title"'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ---------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scanner,
      builder: (context, _) {
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
                      padding: EdgeInsets.fromLTRB(
                        isDesktop ? 36 : 20,
                        isDesktop ? 28 : 20,
                        isDesktop ? 36 : 20,
                        0,
                      ),
                      sliver: SliverToBoxAdapter(child: _buildSearchField()),
                    ),
                    SliverPadding(
                      padding: EdgeInsets.only(top: isDesktop ? 24 : 18),
                      sliver: SliverToBoxAdapter(child: _buildFilters()),
                    ),
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        isDesktop ? 36 : 20,
                        isDesktop ? 32 : 24,
                        isDesktop ? 36 : 20,
                        36,
                      ),
                      sliver: _buildResults(isDesktop),
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
          'ENCUENTRA TU MÚSICA',
          style: theme.textTheme.labelMedium?.copyWith(
            color: AppTheme.accent,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.6,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Buscar',
          style:
              (isDesktop
                      ? theme.textTheme.headlineLarge
                      : theme.textTheme.headlineSmall)
                  ?.copyWith(fontWeight: FontWeight.bold, letterSpacing: -0.8),
        ),
        const SizedBox(height: 8),
        Text(
          'Explora toda tu colección por canción, artista, álbum o podcast.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppTheme.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildSearchField() {
    final theme = Theme.of(context);
    final hasQuery = _query.isNotEmpty;

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _controller,
      builder: (context, value, _) {
        return TextField(
          controller: _controller,
          focusNode: _focusNode,
          textInputAction: TextInputAction.search,
          onChanged: _onQueryChanged,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w500,
          ),
          cursorColor: AppTheme.accent,
          decoration: InputDecoration(
            hintText: 'Canciones, artistas, álbumes o podcasts',
            hintStyle: theme.textTheme.bodyLarge?.copyWith(
              color: AppTheme.textSecondary,
            ),
            prefixIcon: Icon(
              Icons.search_rounded,
              color: hasQuery ? AppTheme.accent : AppTheme.textSecondary,
            ),
            suffixIcon: hasQuery
                ? IconButton(
                    tooltip: 'Borrar',
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: _clearQuery,
                  )
                : null,
            filled: true,
            fillColor: AppTheme.surface,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 18,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: AppTheme.surfaceVariant,
                width: 0.7,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: AppTheme.surfaceVariant,
                width: 0.7,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: AppTheme.accent, width: 1.4),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFilters() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          for (int i = 0; i < _filters.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            _SearchFilterButton(
              data: _filters[i],
              selected: _selectedFilter == _filters[i].filter,
              onTap: () => _selectFilter(_filters[i].filter),
            ),
          ],
        ],
      ),
    );
  }

  Widget _entry(int index, Widget child) {
    if (index >= _maxAnimatedItems) return child;
    return _EntryTransition(
      animation: _entryController,
      index: index,
      child: child,
    );
  }

  Widget _buildResults(bool isDesktop) {
    if (_query.isEmpty) {
      return SliverToBoxAdapter(
        child: _entry(
          0,
          _EmptySearchState(
            icon: Icons.search_rounded,
            title: 'Empieza a escribir',
            message:
                'Busca por título, artista, álbum o podcast en toda tu biblioteca.',
          ),
        ),
      );
    }

    switch (_selectedFilter) {
      case _SearchFilter.all:
        return _buildAllResults(isDesktop);

      case _SearchFilter.songs:
        final songs = _matchingSongs();
        return _buildSongResults(
          songs,
          isDesktop,
          emptyTitle: 'Sin canciones',
          emptyMessage: 'Ninguna canción coincide con "$_query".',
        );

      case _SearchFilter.artists:
        final artists = _groupedSongs(isArtist: true, isPodcast: false);
        return _buildCollectionResults(
          artists,
          isDesktop,
          isArtist: true,
          emptyTitle: 'Sin artistas',
          emptyMessage: 'Ningún artista coincide con "$_query".',
        );

      case _SearchFilter.albums:
        final albums = _groupedSongs(isArtist: false, isPodcast: false);
        return _buildCollectionResults(
          albums,
          isDesktop,
          isArtist: false,
          emptyTitle: 'Sin álbumes',
          emptyMessage: 'Ningún álbum coincide con "$_query".',
        );

      case _SearchFilter.podcasts:
        final podcasts = _groupedSongs(isArtist: false, isPodcast: true);
        return _buildCollectionResults(
          podcasts,
          isDesktop,
          isArtist: false,
          isPodcast: true,
          emptyTitle: 'Sin podcasts',
          emptyMessage: 'Ningún podcast coincide con "$_query".',
        );
    }
  }

  Widget _buildAllResults(bool isDesktop) {
    final songs = _matchingSongs();
    final artists = _groupedSongs(isArtist: true, isPodcast: false);
    final albums = _groupedSongs(isArtist: false, isPodcast: false);
    final podcasts = _groupedSongs(isArtist: false, isPodcast: true);

    if (songs.isEmpty &&
        artists.isEmpty &&
        albums.isEmpty &&
        podcasts.isEmpty) {
      return SliverToBoxAdapter(
        child: _entry(
          0,
          _EmptySearchState(
            icon: Icons.search_off_rounded,
            title: 'Sin resultados',
            message: 'No encontramos nada que coincida con "$_query".',
          ),
        ),
      );
    }

    final slivers = <Widget>[];

    if (songs.isNotEmpty) {
      slivers.add(_sectionHeader('Canciones', songs.length, 0));
      slivers.add(_songListSliver(songs.take(8).toList(), isDesktop, start: 0));
    }

    if (artists.isNotEmpty) {
      slivers.add(_sectionHeader('Artistas', artists.length, 1));
      slivers.add(
        _collectionSliver(
          artists.take(8).toList(),
          isDesktop,
          isArtist: true,
          start: 1,
        ),
      );
    }

    if (albums.isNotEmpty) {
      slivers.add(_sectionHeader('Álbumes', albums.length, 2));
      slivers.add(
        _collectionSliver(
          albums.take(8).toList(),
          isDesktop,
          isArtist: false,
          start: 2,
        ),
      );
    }

    if (podcasts.isNotEmpty) {
      slivers.add(_sectionHeader('Podcasts', podcasts.length, 3));
      slivers.add(
        _collectionSliver(
          podcasts.take(8).toList(),
          isDesktop,
          isArtist: false,
          isPodcast: true,
          start: 3,
        ),
      );
    }

    return SliverMainAxisGroup(slivers: slivers);
  }

  Widget _sectionHeader(String title, int count, int slot) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.only(top: slot == 0 ? 0 : 20, bottom: 10),
        child: Row(
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 8),
            Text(
              '$count',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSongResults(
    List<Song> songs,
    bool isDesktop, {
    required String emptyTitle,
    required String emptyMessage,
  }) {
    if (songs.isEmpty) {
      return SliverToBoxAdapter(
        child: _entry(
          0,
          _EmptySearchState(
            icon: Icons.music_off_rounded,
            title: emptyTitle,
            message: emptyMessage,
          ),
        ),
      );
    }
    return _songListSliver(songs, isDesktop, start: 0);
  }

  Widget _songListSliver(
    List<Song> songs,
    bool isDesktop, {
    required int start,
  }) {
    return DecoratedSliver(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border.all(color: AppTheme.surfaceVariant, width: 0.7),
        borderRadius: BorderRadius.circular(18),
      ),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final song = songs[index];
            return _entry(
              start + index,
              RepaintBoundary(
                child: SongListTile(
                  key: ValueKey(song.filePath ?? song.title),
                  song: song,
                  isDesktop: isDesktop,
                  onFavoriteChanged: (favorite) {
                    _scanner.setFavorite(song, favorite);
                  },
                ),
              ),
            );
          },
          childCount: songs.length,
          addAutomaticKeepAlives: false,
        ),
      ),
    );
  }

  Widget _buildCollectionResults(
    List<Song> songs,
    bool isDesktop, {
    required bool isArtist,
    bool isPodcast = false,
    required String emptyTitle,
    required String emptyMessage,
  }) {
    if (songs.isEmpty) {
      return SliverToBoxAdapter(
        child: _entry(
          0,
          _EmptySearchState(
            icon: isPodcast
                ? Icons.podcasts_rounded
                : isArtist
                ? Icons.person_outline_rounded
                : Icons.album_outlined,
            title: emptyTitle,
            message: emptyMessage,
          ),
        ),
      );
    }
    return _collectionSliver(
      songs,
      isDesktop,
      isArtist: isArtist,
      isPodcast: isPodcast,
      start: 0,
    );
  }

  Widget _collectionSliver(
    List<Song> songs,
    bool isDesktop, {
    required bool isArtist,
    bool isPodcast = false,
    required int start,
  }) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final song = songs[index];
          final title = isArtist
              ? (song.artist.isEmpty ? 'Desconocido' : song.artist)
              : (_isUnknownAlbum(song.album) ? 'Desconocido' : song.album);

          return _entry(
            start + index,
            RepaintBoundary(
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
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
                    // [CONECTADO] Abre el detalle real vía callback.
                    // Para podcasts/artistas el álbum se pasa como null;
                    // el nombre del grupo viaja en `title`.
                    onTap: () => _openDetail(
                      title: title,
                      artist: song.artist,
                      album: (isArtist || isPodcast) ? null : song.album,
                      isPodcast: isPodcast,
                    ),
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
}

// -----------------------------------------------------------------
// Widgets auxiliares
// -----------------------------------------------------------------

class _SearchFilterData {
  final _SearchFilter filter;
  final String title;
  final IconData icon;

  const _SearchFilterData(this.filter, this.title, this.icon);
}

class _SearchFilterButton extends StatelessWidget {
  final _SearchFilterData data;
  final bool selected;
  final VoidCallback onTap;

  const _SearchFilterButton({
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

class _EmptySearchState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _EmptySearchState({
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
