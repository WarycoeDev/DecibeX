import 'dart:async';
import 'dart:io';

import 'package:extractor/extractor.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../core/models/song.dart';
import '../../core/services/library_scanner.dart';
import '../../core/services/playback_queue.dart';
import '../../core/services/playback_service.dart';
import '../library/song_list_tile.dart';

enum _SearchFilter { all, songs, artists, albums, podcasts, youtube }

enum _LayoutSize { compact, medium, expanded }

/// Callback opcional para que la pantalla padre (p. ej. la shell de la app)
/// navegue al detalle de un artista/álbum/podcast. Si no se proporciona,
/// se muestra un SnackBar informativo.
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
    _SearchFilterData(_SearchFilter.all, 'filterAll', Icons.search_rounded),
    _SearchFilterData(
      _SearchFilter.songs,
      'filterSongs',
      Icons.music_note_rounded,
    ),
    _SearchFilterData(
      _SearchFilter.artists,
      'filterArtists',
      Icons.person_rounded,
    ),
    _SearchFilterData(
      _SearchFilter.albums,
      'filterAlbums',
      Icons.album_rounded,
    ),
    _SearchFilterData(
      _SearchFilter.podcasts,
      'filterPodcasts',
      Icons.podcasts_rounded,
    ),
    // [NUEVO] Filtro de YouTube integrado.
    _SearchFilterData(
      _SearchFilter.youtube,
      'filterYoutube',
      Icons.play_circle_outline_rounded,
    ),
  ];

  final LibraryScanner _scanner = LibraryScanner.instance;
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  late final AnimationController _entryController;

  _SearchFilter _selectedFilter = _SearchFilter.all;
  String _query = '';

  /// Caché de resultados por combinación (query normalizada, filtro).
  final Map<String, List<Song>> _songsCache = {};
  final Map<String, List<Song>> _groupedCache = {};

  // ---------------------------------------------------------------------------
  // [NUEVO] Estado de YouTube integrado
  // ---------------------------------------------------------------------------
  final YoutubeExplode _yt = YoutubeExplode();
  final YoutubeDLFlutter _downloader = YoutubeDLFlutter.instance;

  List<Video> _ytResults = [];
  VideoSearchList? _ytSearchList;
  bool _ytLoading = false;
  bool _ytLoadingMore = false;
  bool _ytDownloading = false;
  String? _ytQuery;

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: _entryDuration,
      value: 1,
    );
    _scanner.initialize();
    _scanner.addListener(_invalidateCache);

    // 🔧 FIX: evitar que el teclado se abra automáticamente al entrar a la
    // pantalla. Se asegura que el campo no tenga foco tras el primer frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.unfocus();
      }
    });
  }

  @override
  void dispose() {
    _scanner.removeListener(_invalidateCache);
    _entryController.dispose();
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    _yt.close();
    super.dispose();
  }

  void _invalidateCache() {
    _songsCache.clear();
    _groupedCache.clear();
  }

  _LayoutSize _layoutFor(double width) {
    if (width < 400) return _LayoutSize.compact;
    if (width < 800) return _LayoutSize.medium;
    return _LayoutSize.expanded;
  }

  bool _isUnknownAlbum(String album) {
    final normalized = album.trim().toLowerCase();
    return normalized.isEmpty ||
        normalized == 'desconocido' ||
        normalized == 'unknown' ||
        normalized == 'unknown album';
  }

  // ---------------------------------------------------------------
  // Búsqueda difusa (biblioteca local)
  // ---------------------------------------------------------------

  String _normalizeFuzzy(String value) {
    const accented = 'áàäâãéèëêíìïîóòöôõúùüûñç';
    const plain = 'aaaaaeeeeiiiiooooouuuunc';
    final buffer = StringBuffer();
    for (final ch in value.toLowerCase().trim().split('')) {
      final idx = accented.indexOf(ch);
      buffer.write(idx >= 0 ? plain[idx] : ch);
    }
    return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  int _subsequenceGaps(String needle, String haystack) {
    if (needle.isEmpty) return -1;
    int hi = 0;
    int gaps = 0;
    int lastMatch = -1;
    for (int ni = 0; ni < needle.length; ni++) {
      final target = needle[ni];
      bool found = false;
      while (hi < haystack.length) {
        if (haystack[hi] == target) {
          if (lastMatch >= 0 && hi > lastMatch + 1) {
            gaps += hi - lastMatch - 1;
          }
          lastMatch = hi;
          hi++;
          found = true;
          break;
        }
        hi++;
      }
      if (!found) return -1;
    }
    return gaps;
  }

  int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    if (a.length > b.length) {
      final tmp = a;
      a = b;
      b = tmp;
    }
    final m = a.length;
    final n = b.length;
    var prev = List<int>.generate(m + 1, (i) => i);
    var curr = List<int>.filled(m + 1, 0);
    for (int j = 1; j <= n; j++) {
      curr[0] = j;
      for (int i = 1; i <= m; i++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        curr[i] = [
          curr[i - 1] + 1,
          prev[i] + 1,
          prev[i - 1] + cost,
        ].reduce((x, y) => x < y ? x : y);
      }
      final tmp = prev;
      prev = curr;
      curr = tmp;
    }
    return prev[m];
  }

  double _scoreSong(String query, Song song) {
    if (query.isEmpty) return 0;

    final haystack = _normalizeFuzzy(
      '${song.title} ${song.artist} ${song.album}',
    );

    final idx = haystack.indexOf(query);
    if (idx >= 0) {
      final titleNorm = _normalizeFuzzy(song.title);
      if (titleNorm.startsWith(query)) return 100;
      if (haystack.startsWith(query)) return 95;
      if (idx == 0 || haystack[idx - 1] == ' ') return 85;
      return 80;
    }

    if (query.length < 2) return 0;

    double best = 0;

    final gaps = _subsequenceGaps(query, haystack);
    if (gaps >= 0) {
      final penalty = (gaps / (haystack.length + 1)).clamp(0.0, 0.6);
      final subScore = 60.0 * (1.0 - penalty);
      if (subScore > best) best = subScore;
    }

    final candidates = <String>[
      _normalizeFuzzy(song.title),
      _normalizeFuzzy(song.artist),
      _normalizeFuzzy(song.album),
    ];
    for (final cand in candidates) {
      if (cand.isEmpty) continue;
      final dist = _levenshtein(query, cand);
      final maxLen = query.length > cand.length ? query.length : cand.length;
      if (maxLen == 0) continue;
      final ratio = dist / maxLen;
      if (ratio <= 0.4) {
        final levScore = 50.0 * (1.0 - ratio / 0.4);
        if (levScore > best) best = levScore;
      }
    }

    return best;
  }

  // ---------------------------------------------------------------
  // Reproducción
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
                  title: Text(context.l10n.overwriteQueue),
                  onTap: () => Navigator.pop(sheetContext, true),
                ),
                ListTile(
                  leading: const Icon(Icons.close_rounded),
                  title: Text(context.l10n.cancel),
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
  // Resultados de biblioteca local
  // ---------------------------------------------------------------

  Iterable<Song> _sourceForFilter(_SearchFilter filter) {
    switch (filter) {
      case _SearchFilter.songs:
        return _scanner.musicSongs;
      case _SearchFilter.podcasts:
        return _scanner.podcasts;
      case _SearchFilter.all:
      case _SearchFilter.youtube:
        return _scanner.songs;
      case _SearchFilter.artists:
      case _SearchFilter.albums:
        return _scanner.musicSongs;
    }
  }

  List<Song> _matchingSongs() {
    if (_query.isEmpty) return const [];
    final q = _normalizeFuzzy(_query);
    final cacheKey = '$q|${_selectedFilter.index}';
    final cached = _songsCache[cacheKey];
    if (cached != null) return cached;

    final scored = <_ScoredSong>[];
    for (final song in _sourceForFilter(_selectedFilter)) {
      final score = _scoreSong(q, song);
      if (score > 0) {
        scored.add(_ScoredSong(song, score));
      }
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    final result = scored.map((e) => e.song).toList();
    _songsCache[cacheKey] = result;
    return result;
  }

  List<Song> _groupedSongs({required bool isArtist, required bool isPodcast}) {
    if (_query.isEmpty) return const [];
    final q = _normalizeFuzzy(_query);
    final cacheKey = 'g|$q|${isArtist ? 'a' : 'b'}|${isPodcast ? 'p' : 'm'}';
    final cached = _groupedCache[cacheKey];
    if (cached != null) return cached;

    final unique = <String, _ScoredSong>{};
    final source = isPodcast ? _scanner.podcasts : _scanner.musicSongs;

    for (final song in source) {
      final title = isArtist
          ? (song.artist.isEmpty ? context.l10n.unknown : song.artist)
          : (_isUnknownAlbum(song.album) ? context.l10n.unknown : song.album);

      final normTitle = _normalizeFuzzy(title);
      double score = 0;

      final idx = normTitle.indexOf(q);
      if (idx >= 0) {
        score = idx == 0 ? 100 : 80;
      } else if (q.length >= 2) {
        final gaps = _subsequenceGaps(q, normTitle);
        if (gaps >= 0) {
          final penalty = (gaps / (normTitle.length + 1)).clamp(0.0, 0.6);
          score = 60.0 * (1.0 - penalty);
        }
        final dist = _levenshtein(q, normTitle);
        final maxLen = q.length > normTitle.length
            ? q.length
            : normTitle.length;
        if (maxLen > 0) {
          final ratio = dist / maxLen;
          if (ratio <= 0.4) {
            final levScore = 50.0 * (1.0 - ratio / 0.4);
            if (levScore > score) score = levScore;
          }
        }
      }

      if (score <= 0) continue;

      final key = isArtist ? title : '${song.artist}\u0000$title';
      final existing = unique[key];
      if (existing == null || score > existing.score) {
        unique[key] = _ScoredSong(song, score);
      }
    }

    final list = unique.values.toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    final result = list.map((e) => e.song).toList();
    _groupedCache[cacheKey] = result;
    return result;
  }

  // ---------------------------------------------------------------
  // [NUEVO] Búsqueda y descarga de YouTube
  // ---------------------------------------------------------------

  Future<void> _ytSearch(String rawQuery) async {
    final trimmed = rawQuery.trim();
    if (trimmed.isEmpty) return;

    _focusNode.unfocus();

    setState(() {
      _ytLoading = true;
      _ytResults = [];
      _ytSearchList = null;
      _ytQuery = trimmed;
    });

    try {
      final searchList = await _yt.search.search(trimmed);
      if (!mounted) return;

      setState(() {
        _ytSearchList = searchList;
        _ytResults = searchList.take(20).toList();
        _ytLoading = false;
      });

      _entryController.forward(from: 0);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _ytLoading = false);
      _message(context.l10n.searchYoutubeErrorDetail(error));
    }
  }

  Future<void> _ytLoadMore() async {
    if (_ytSearchList == null || _ytLoadingMore || _ytLoading) return;

    setState(() => _ytLoadingMore = true);

    try {
      final nextPage = await _ytSearchList!.nextPage();
      if (!mounted) return;

      if (nextPage == null) {
        _message(context.l10n.searchYoutubeNoMoreResults);
        setState(() => _ytLoadingMore = false);
        return;
      }

      _ytSearchList = nextPage;

      setState(() {
        _ytResults.addAll(nextPage.take(20));
        _ytLoadingMore = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _ytLoadingMore = false);
      _message(context.l10n.searchYoutubeLoadMoreError(error));
    }
  }

  void _ytClear() {
    setState(() {
      _ytResults = [];
      _ytSearchList = null;
      _ytQuery = null;
      _ytLoading = false;
      _ytLoadingMore = false;
    });
  }

  Future<String> _ytResolveInitialDirectory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('youtube_download_directory');
      if (saved != null && saved.isNotEmpty) {
        return saved;
      }
    } catch (_) {}

    try {
      final downloads = await getDownloadsDirectory();
      final fallback = await getExternalStorageDirectory();
      return (downloads ?? fallback)?.path ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<void> _ytPersistDirectory(String directory) async {
    if (directory.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('youtube_download_directory', directory);
    } catch (_) {}
  }

  Future<void> _ytShowDownloadMenu(Video video) async {
    if (_ytDownloading) return;

    final directory = await _ytResolveInitialDirectory();
    if (!mounted) return;

    setState(() => _ytDownloading = true);

    try {
      final request = await showDialog<_YouTubeDownloadRequest>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return _YouTubeDownloadConfigDialog(
            video: video,
            initialDirectory: directory,
            onError: _message,
          );
        },
      );

      if (request == null || !mounted) return;

      await _ytPersistDirectory(request.directory);

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return _YouTubeDownloadProgressDialog(
            video: video,
            request: request,
            downloader: _downloader,
            onError: _message,
          );
        },
      );
    } finally {
      if (mounted) {
        setState(() => _ytDownloading = false);
      }
    }
  }

  String _formatYtDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    final two = (int value) => value.toString().padLeft(2, '0');

    if (hours > 0) {
      return '$hours:${two(minutes)}:${two(seconds)}';
    }
    return '$minutes:${two(seconds)}';
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ---------------------------------------------------------------
  // Acciones de UI
  // ---------------------------------------------------------------

  void _onQueryChanged(String value) {
    _invalidateCache();
    setState(() => _query = value);

    // Si estamos en modo YouTube, la búsqueda es online (submit).
    if (_selectedFilter == _SearchFilter.youtube) {
      if (value.isEmpty) {
        _ytClear();
      }
      return;
    }

    _entryController.forward(from: 0);
  }

  void _clearQuery() {
    _controller.clear();
    _focusNode.requestFocus();
    _onQueryChanged('');

    if (_selectedFilter == _SearchFilter.youtube) {
      _ytClear();
    }
  }

  void _selectFilter(_SearchFilter filter) {
    if (filter == _selectedFilter) return;
    _invalidateCache();

    setState(() {
      _selectedFilter = filter;
      // Al cambiar a/desde YouTube, limpiamos la búsqueda online si es necesario.
      if (filter != _SearchFilter.youtube) {
        _ytResults = [];
        _ytSearchList = null;
        _ytQuery = null;
        _ytLoading = false;
        _ytLoadingMore = false;
      }
    });

    _entryController.forward(from: 0);
  }

  void _openDetail({
    required String title,
    required String? artist,
    required String? album,
    required bool isPodcast,
  }) {
    final callback = widget.onOpenDetail;
    if (callback != null) {
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
        content: Text(context.l10n.openDetailOfTitle(title)),
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
            final layout = _layoutFor(constraints.maxWidth);
            final isDesktop = layout == _LayoutSize.expanded;
            final isCompact = layout == _LayoutSize.compact;
            final isYouTubeMode = _selectedFilter == _SearchFilter.youtube;

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
                          child: _buildHeader(context, layout, isYouTubeMode),
                        ),
                      ),
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          horizontal,
                          isCompact ? 16 : (isDesktop ? 28 : 20),
                          horizontal,
                          0,
                        ),
                        sliver: SliverToBoxAdapter(
                          child: _buildSearchField(layout, isYouTubeMode),
                        ),
                      ),
                      SliverPadding(
                        padding: EdgeInsets.only(
                          top: isCompact ? 14 : (isDesktop ? 24 : 18),
                        ),
                        sliver: SliverToBoxAdapter(
                          child: _buildFilters(layout),
                        ),
                      ),
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          horizontal,
                          isCompact ? 18 : (isDesktop ? 32 : 24),
                          horizontal,
                          isCompact ? 24 : 36,
                        ),
                        sliver: isYouTubeMode
                            ? _buildYouTubeResults(layout)
                            : _buildResults(isDesktop, layout),
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

  Widget _buildHeader(
    BuildContext context,
    _LayoutSize layout,
    bool isYouTubeMode,
  ) {
    final theme = Theme.of(context);
    final isDesktop = layout == _LayoutSize.expanded;
    final isCompact = layout == _LayoutSize.compact;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isYouTubeMode
              ? context.l10n.searchYoutubeMode
              : context.l10n.findYourMusic,
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
          isYouTubeMode
              ? context.l10n.exploreAndDownload
              : context.l10n.searchTitle,
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
          isYouTubeMode
              ? context.l10n.searchYoutubeDescription
              : context.l10n.searchLibraryDescription,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppTheme.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildSearchField(_LayoutSize layout, bool isYouTubeMode) {
    final theme = Theme.of(context);
    final hasQuery = _query.isNotEmpty;
    final isCompact = layout == _LayoutSize.compact;

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _controller,
      builder: (context, value, _) {
        return TextField(
          controller: _controller,
          focusNode: _focusNode,
          autofocus: false,
          textInputAction: TextInputAction.search,
          onChanged: _onQueryChanged,
          onSubmitted: isYouTubeMode ? (v) => _ytSearch(v) : null,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w500,
          ),
          cursorColor: AppTheme.accent,
          decoration: InputDecoration(
            hintText: isYouTubeMode
                ? context.l10n.searchYoutubeHint
                : context.l10n.searchLibraryHint,
            hintStyle: theme.textTheme.bodyLarge?.copyWith(
              color: AppTheme.textSecondary,
            ),
            prefixIcon: Icon(
              isYouTubeMode
                  ? Icons.play_circle_outline_rounded
                  : Icons.search_rounded,
              color: hasQuery ? AppTheme.accent : AppTheme.textSecondary,
            ),
            suffixIcon: hasQuery
                ? IconButton(
                    tooltip: context.l10n.clear,
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: _clearQuery,
                  )
                : (isYouTubeMode
                      ? IconButton(
                          tooltip: context.l10n.searchYoutube,
                          icon: const Icon(
                            Icons.arrow_forward_rounded,
                            size: 20,
                          ),
                          onPressed: () => _ytSearch(_controller.text),
                        )
                      : null),
            filled: true,
            fillColor: AppTheme.surface,
            contentPadding: EdgeInsets.symmetric(
              horizontal: 18,
              vertical: isCompact ? 14 : 18,
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

  Widget _buildFilters(_LayoutSize layout) {
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

  // ---------------------------------------------------------------
  // [NUEVO] Resultados de YouTube
  // ---------------------------------------------------------------

  Widget _buildYouTubeResults(_LayoutSize layout) {
    final isDesktop = layout == _LayoutSize.expanded;

    if (_ytLoading) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(48),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (_ytQuery == null || _ytResults.isEmpty) {
      final hasQuery = _ytQuery != null;
      return SliverToBoxAdapter(
        child: _entry(
          0,
          _EmptySearchState(
            icon: hasQuery
                ? Icons.search_off_rounded
                : Icons.play_circle_outline_rounded,
            title: hasQuery
                ? context.l10n.searchNoResultsTitle
                : context.l10n.searchOnYoutubeTitle,
            message: hasQuery
                ? context.l10n.searchTryOtherWords
                : context.l10n.searchOnYoutubeMessage,
          ),
          layout,
        ),
      );
    }

    return DecoratedSliver(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border.all(color: AppTheme.surfaceVariant, width: 0.7),
        borderRadius: BorderRadius.circular(18),
      ),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            if (index == _ytResults.length) {
              return Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: isDesktop ? 20 : 12,
                  vertical: 16,
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _ytLoadingMore ? null : _ytLoadMore,
                    icon: _ytLoadingMore
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.expand_more_rounded),
                    label: Text(
                      _ytLoadingMore
                          ? context.l10n.searchLoadingMore
                          : context.l10n.searchLoadMore,
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.accent,
                      side: BorderSide(color: AppTheme.accent),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              );
            }

            final video = _ytResults[index];
            return _entry(
              index,
              RepaintBoundary(
                child: Column(
                  children: [
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _ytDownloading
                            ? null
                            : () => _ytShowDownloadMenu(video),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: isDesktop ? 20 : 12,
                            vertical: isDesktop ? 12 : 10,
                          ),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(11),
                                child: SizedBox(
                                  width: isDesktop ? 140 : 120,
                                  height: isDesktop ? 79 : 68,
                                  child: Image.network(
                                    video.thumbnails.highResUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => ColoredBox(
                                      color: AppTheme.surfaceVariant,
                                      child: Icon(
                                        Icons.video_library_rounded,
                                        color: AppTheme.accent,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      video.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      video.author,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: AppTheme.textSecondary,
                                          ),
                                    ),
                                    if (video.duration != null)
                                      Text(
                                        _formatYtDuration(video.duration!),
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(
                                              color: AppTheme.textSecondary,
                                            ),
                                      ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: _ytDownloading
                                    ? null
                                    : () => _ytShowDownloadMenu(video),
                                icon: const Icon(Icons.more_horiz_rounded),
                                color: AppTheme.textSecondary,
                                tooltip: context.l10n.download,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (index != _ytResults.length - 1)
                      Divider(
                        height: 1,
                        thickness: 0.7,
                        indent: isDesktop ? 20 : 12,
                        endIndent: isDesktop ? 20 : 12,
                        color: AppTheme.surfaceVariant,
                      ),
                  ],
                ),
              ),
              layout,
            );
          },
          childCount: _ytResults.length + 1,
          addAutomaticKeepAlives: false,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------
  // Resultados de biblioteca
  // ---------------------------------------------------------------

  Widget _buildResults(bool isDesktop, _LayoutSize layout) {
    if (_query.isEmpty) {
      return SliverToBoxAdapter(
        child: _entry(
          0,
          _EmptySearchState(
            icon: Icons.search_rounded,
            title: context.l10n.searchStartTypingTitle,
            message: context.l10n.searchStartTypingMessage,
          ),
          layout,
        ),
      );
    }

    switch (_selectedFilter) {
      case _SearchFilter.all:
        return _buildAllResults(isDesktop, layout);

      case _SearchFilter.songs:
        final songs = _matchingSongs();
        return _buildSongResults(
          songs,
          isDesktop,
          layout,
          emptyTitle: context.l10n.searchNoSongsTitle,
          emptyMessage: context.l10n.searchNoSongsMessage(_query),
        );

      case _SearchFilter.artists:
        final artists = _groupedSongs(isArtist: true, isPodcast: false);
        return _buildCollectionResults(
          artists,
          isDesktop,
          layout,
          isArtist: true,
          emptyTitle: context.l10n.searchNoArtistsTitle,
          emptyMessage: context.l10n.searchNoArtistsMessage(_query),
        );

      case _SearchFilter.albums:
        final albums = _groupedSongs(isArtist: false, isPodcast: false);
        return _buildCollectionResults(
          albums,
          isDesktop,
          layout,
          isArtist: false,
          emptyTitle: context.l10n.searchNoAlbumsTitle,
          emptyMessage: context.l10n.searchNoAlbumsMessage(_query),
        );

      case _SearchFilter.podcasts:
        final podcasts = _groupedSongs(isArtist: false, isPodcast: true);
        return _buildCollectionResults(
          podcasts,
          isDesktop,
          layout,
          isArtist: false,
          isPodcast: true,
          emptyTitle: context.l10n.searchNoPodcastsTitle,
          emptyMessage: context.l10n.searchNoPodcastsMessage(_query),
        );

      case _SearchFilter.youtube:
        // No debería llegar aquí (se gestiona antes), pero por seguridad.
        return _buildYouTubeResults(layout);
    }
  }

  Widget _buildAllResults(bool isDesktop, _LayoutSize layout) {
    final isCompact = layout == _LayoutSize.compact;
    final limit = isCompact ? 5 : 8;

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
            title: context.l10n.searchNoResultsTitle,
            message: context.l10n.searchNoResultsMessage(_query),
          ),
          layout,
        ),
      );
    }

    final slivers = <Widget>[];

    if (songs.isNotEmpty) {
      slivers.add(_sectionHeader(context.l10n.filterSongs, songs.length, 0));
      slivers.add(
        _songListSliver(
          songs.take(limit).toList(),
          isDesktop,
          layout,
          start: 0,
        ),
      );
    }

    if (artists.isNotEmpty) {
      slivers.add(
        _sectionHeader(context.l10n.filterArtists, artists.length, 1),
      );
      slivers.add(
        _collectionSliver(
          artists.take(limit).toList(),
          isDesktop,
          layout,
          isArtist: true,
          start: 1,
        ),
      );
    }

    if (albums.isNotEmpty) {
      slivers.add(_sectionHeader(context.l10n.filterAlbums, albums.length, 2));
      slivers.add(
        _collectionSliver(
          albums.take(limit).toList(),
          isDesktop,
          layout,
          isArtist: false,
          start: 2,
        ),
      );
    }

    if (podcasts.isNotEmpty) {
      slivers.add(
        _sectionHeader(context.l10n.filterPodcasts, podcasts.length, 3),
      );
      slivers.add(
        _collectionSliver(
          podcasts.take(limit).toList(),
          isDesktop,
          layout,
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
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
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
    bool isDesktop,
    _LayoutSize layout, {
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
          layout,
        ),
      );
    }
    return _songListSliver(songs, isDesktop, layout, start: 0);
  }

  Widget _songListSliver(
    List<Song> songs,
    bool isDesktop,
    _LayoutSize layout, {
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
              layout,
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
    bool isDesktop,
    _LayoutSize layout, {
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
          layout,
        ),
      );
    }
    return _collectionSliver(
      songs,
      isDesktop,
      layout,
      isArtist: isArtist,
      isPodcast: isPodcast,
      start: 0,
    );
  }

  Widget _collectionSliver(
    List<Song> songs,
    bool isDesktop,
    _LayoutSize layout, {
    required bool isArtist,
    bool isPodcast = false,
    required int start,
  }) {
    final isCompact = layout == _LayoutSize.compact;

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final song = songs[index];
          final title = isArtist
              ? (song.artist.isEmpty ? context.l10n.unknown : song.artist)
              : (_isUnknownAlbum(song.album)
                    ? context.l10n.unknown
                    : song.album);

          return _entry(
            start + index,
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
            layout,
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

    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final cacheSize = (48 * pixelRatio).round().clamp(1, 512);

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 48,
        height: 48,
        child: Image.file(
          File(artworkPath),
          fit: BoxFit.cover,
          alignment: Alignment.center,
          cacheWidth: cacheSize,
          filterQuality: FilterQuality.low,
          errorBuilder: (context, error, stackTrace) => placeholder(),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------
// Widgets auxiliares
// -----------------------------------------------------------------

class _ScoredSong {
  final Song song;
  final double score;
  const _ScoredSong(this.song, this.score);
}

class _SearchFilterData {
  final _SearchFilter filter;
  final String titleKey;
  final IconData icon;

  const _SearchFilterData(this.filter, this.titleKey, this.icon);
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
    final title = context.l10n.get(data.titleKey);

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
                title,
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
    final isCompact = MediaQuery.sizeOf(context).width < 400;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: 24,
        vertical: isCompact ? 32 : 48,
      ),
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

// -----------------------------------------------------------------
// [NUEVO] Diálogos de descarga de YouTube (adaptados del screen original)
// -----------------------------------------------------------------

class _YouTubeDownloadRequest {
  final AudioFormat format;
  final String fileName;
  final String directory;
  final Video video;

  const _YouTubeDownloadRequest({
    required this.format,
    required this.fileName,
    required this.directory,
    required this.video,
  });
}

enum AudioFormat {
  mp3(label: 'MP3', extension: 'mp3', icon: Icons.audiotrack_rounded),
  flac(label: 'FLAC', extension: 'flac', icon: Icons.graphic_eq_rounded),
  wav(label: 'WAV', extension: 'wav', icon: Icons.multitrack_audio_rounded);

  final String label;
  final String extension;
  final IconData icon;

  const AudioFormat({
    required this.label,
    required this.extension,
    required this.icon,
  });
}

/// Diálogo centrado de configuración de descarga.
class _YouTubeDownloadConfigDialog extends StatefulWidget {
  final Video video;
  final String initialDirectory;
  final void Function(String message) onError;

  const _YouTubeDownloadConfigDialog({
    required this.video,
    required this.initialDirectory,
    required this.onError,
  });

  @override
  State<_YouTubeDownloadConfigDialog> createState() =>
      _YouTubeDownloadConfigDialogState();
}

class _YouTubeDownloadConfigDialogState
    extends State<_YouTubeDownloadConfigDialog> {
  late final TextEditingController _nameController;
  final FocusNode _nameFocusNode = FocusNode();
  final GlobalKey _nameFieldKey = GlobalKey();
  final ScrollController _scrollController = ScrollController();
  late String _directory;
  AudioFormat? _selectedFormat;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: _sanitizeFileName(widget.video.title),
    );
    _directory = widget.initialDirectory;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _nameFocusNode.unfocus();
    });

    _nameFocusNode.addListener(() {
      if (_nameFocusNode.hasFocus) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final ctx = _nameFieldKey.currentContext;
            if (ctx != null) {
              Scrollable.ensureVisible(
                ctx,
                duration: const Duration(milliseconds: 250),
                alignment: 0.1,
                curve: Curves.easeOut,
              );
            }
          });
        });
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nameFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String _sanitizeFileName(String value) {
    return value
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .replaceAll(RegExp(r'\.+$'), '');
  }

  InputDecoration _inputDecoration(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, color: AppTheme.accent),
      filled: true,
      fillColor: AppTheme.surfaceVariant.withValues(alpha: 0.35),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: AppTheme.accent.withValues(alpha: 0.7)),
      ),
    );
  }

  Widget _optionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool selected = false,
    bool showCheck = true,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: selected
            ? AppTheme.accent.withValues(alpha: 0.14)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: selected ? AppTheme.accent : AppTheme.textSecondary,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: selected
                              ? AppTheme.accent
                              : Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (showCheck) ...[
                  const SizedBox(width: 8),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: selected ? AppTheme.accent : Colors.transparent,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected
                            ? AppTheme.accent
                            : AppTheme.surfaceVariant,
                        width: 1.5,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: selected
                        ? const Icon(
                            Icons.check_rounded,
                            size: 15,
                            color: Colors.white,
                          )
                        : null,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _confirmDownload() {
    if (_selectedFormat == null) return;

    final fileName = _sanitizeFileName(_nameController.text);
    if (fileName.isEmpty) {
      widget.onError(context.l10n.ytChooseValidFileName);
      return;
    }
    if (_directory.isEmpty) {
      widget.onError(context.l10n.ytChooseFolderFirst);
      return;
    }

    FocusScope.of(context).unfocus();

    Navigator.pop(
      context,
      _YouTubeDownloadRequest(
        format: _selectedFormat!,
        fileName: fileName,
        directory: _directory,
        video: widget.video,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaQuery = MediaQuery.of(context);

    final availableHeight =
        mediaQuery.size.height -
        mediaQuery.padding.top -
        mediaQuery.padding.bottom -
        48;

    final canDownload =
        _selectedFormat != null &&
        _nameController.text.trim().isNotEmpty &&
        _directory.isNotEmpty;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 480,
          maxHeight: availableHeight > 0 ? availableHeight : 100,
        ),
        child: Container(
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
          child: SingleChildScrollView(
            controller: _scrollController,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 128,
                          height: 72,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppTheme.surfaceVariant,
                              width: 0.7,
                            ),
                            color: AppTheme.surfaceVariant,
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Image.network(
                            widget.video.thumbnails.highResUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => ColoredBox(
                              color: AppTheme.surfaceVariant,
                              child: Icon(
                                Icons.video_library_rounded,
                                color: AppTheme.accent,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          right: -6,
                          bottom: -6,
                          child: Container(
                            width: 28,
                            height: 28,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: AppTheme.accent,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppTheme.surface,
                                width: 3,
                              ),
                            ),
                            child: const Icon(
                              Icons.download_rounded,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.l10n.ytDownloadTitle,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            widget.video.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.video.author,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                      tooltip: context.l10n.close,
                      visualDensity: VisualDensity.compact,
                      color: AppTheme.textSecondary,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  context.l10n.ytDownloadDirectory,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                _optionTile(
                  icon: Icons.folder_outlined,
                  title: _directory.isEmpty
                      ? context.l10n.chooseFolder
                      : _directory,
                  subtitle: context.l10n.selectLocation,
                  showCheck: false,
                  onTap: () async {
                    final picked = await FilePicker.getDirectoryPath(
                      dialogTitle: context.l10n.downloadFolder,
                      initialDirectory: _directory.isEmpty ? null : _directory,
                    );

                    if (picked != null) {
                      setState(() => _directory = picked);
                    }
                  },
                ),
                const SizedBox(height: 16),
                Text(
                  context.l10n.ytFileName,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  key: _nameFieldKey,
                  focusNode: _nameFocusNode,
                  controller: _nameController,
                  autofocus: false,
                  onChanged: (_) => setState(() {}),
                  decoration: _inputDecoration(
                    context.l10n.ytFileNameHint,
                    Icons.drive_file_rename_outline_rounded,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  context.l10n.downloadFormat,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                for (final format in AudioFormat.values)
                  _optionTile(
                    icon: format.icon,
                    title: format.label,
                    subtitle: switch (format) {
                      AudioFormat.mp3 => context.l10n.compressedCompatible,
                      AudioFormat.flac => context.l10n.losslessAudio,
                      AudioFormat.wav => context.l10n.uncompressedAudio,
                    },
                    selected: _selectedFormat == format,
                    onTap: () {
                      setState(() => _selectedFormat = format);
                    },
                  ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
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
                        child: Text(context.l10n.cancel),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: canDownload ? _confirmDownload : null,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.accent,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: AppTheme.surfaceVariant,
                          disabledForegroundColor: AppTheme.textSecondary,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(Icons.download_rounded, size: 18),
                        label: Text(context.l10n.download),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Diálogo de descarga: progreso, completado y error en un solo widget.
class _YouTubeDownloadProgressDialog extends StatefulWidget {
  final Video video;
  final _YouTubeDownloadRequest request;
  final YoutubeDLFlutter downloader;
  final void Function(String message) onError;

  const _YouTubeDownloadProgressDialog({
    required this.video,
    required this.request,
    required this.downloader,
    required this.onError,
  });

  @override
  State<_YouTubeDownloadProgressDialog> createState() =>
      _YouTubeDownloadProgressDialogState();
}

enum _DialogPhase { downloading, completed, error }

class _YouTubeDownloadProgressDialogState
    extends State<_YouTubeDownloadProgressDialog> {
  _DialogPhase _phase = _DialogPhase.downloading;
  double _progress = 0;
  String _status = '';
  bool _isInitializing = true;
  String? _errorMessage;
  String? _savedPath;

  StreamSubscription<DownloadProgress>? _progressSubscription;
  String? _activeProcessId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startDownload();
    });
  }

  @override
  void dispose() {
    _progressSubscription?.cancel();
    super.dispose();
  }

  Future<void> _startDownload() async {
    if (!Platform.isAndroid) {
      widget.onError(context.l10n.ytAndroidOnly);
      if (mounted) Navigator.pop(context);
      return;
    }

    setState(() {
      _phase = _DialogPhase.downloading;
      _isInitializing = true;
      _progress = 0;
      _status = context.l10n.ytPreparingDownloader;
      _errorMessage = null;
      _savedPath = null;
    });

    final directory = Directory(widget.request.directory);

    try {
      await directory.create(recursive: true);

      final initResult = await widget.downloader.initialize(
        enableFFmpeg: true,
        enableAria2c: false,
      );

      if (!initResult.success) {
        final errorMsg =
            initResult.errorMessage ?? context.l10n.ytInitializeFailed;
        throw Exception(errorMsg);
      }

      if (!mounted) return;

      final processId = 'decibex_${DateTime.now().microsecondsSinceEpoch}';
      _activeProcessId = processId;

      setState(() {
        _isInitializing = false;
        _status = context.l10n.ytDownloadingStatus;
      });

      await _progressSubscription?.cancel();

      _progressSubscription = widget.downloader.onProgress.listen((progress) {
        if (!mounted || progress.processId != _activeProcessId) return;

        setState(() {
          _progress = progress.progress;
          _status = context.l10n.ytDownloadingStatus;
        });
      });

      final outputTemplate = '${widget.request.fileName}.%(ext)s';

      final downloadRequest = DownloadRequest(
        url: 'https://www.youtube.com/watch?v=${widget.video.id}',
        outputPath: directory.path,
        outputTemplate: outputTemplate,
        noPlaylist: true,
        extractAudio: true,
        audioFormat: widget.request.format.extension,
        audioQuality: 0,
        embedMetadata: false,
        embedThumbnail: true,
        processId: processId,
        customOptions: {
          '--retries': '5',
          '--fragment-retries': '5',
          '--no-mtime': '',
          '--format': 'bestaudio/best',
          '--extractor-args':
              'youtube:player_client=android;player_skip=webpage,configs',
        },
      );

      final result = await widget.downloader
          .download(downloadRequest)
          .timeout(const Duration(minutes: 15));

      if (result.status != OperationStatus.success) {
        throw Exception(
          result.errorMessage ?? context.l10n.ytDownloadErrorMessage,
        );
      }

      File? downloadedFile;

      if (result.outputPath != null && result.outputPath!.isNotEmpty) {
        final file = File(result.outputPath!);
        if (await file.exists() && await file.length() > 0) {
          downloadedFile = file;
        }
      }

      if (downloadedFile == null) {
        final expectedFile = File(
          '${directory.path}${Platform.pathSeparator}'
          '${widget.request.fileName}.${widget.request.format.extension}',
        );
        if (await expectedFile.exists() && await expectedFile.length() > 0) {
          downloadedFile = expectedFile;
        }
      }

      if (downloadedFile == null) {
        await for (final entity in directory.list()) {
          if (entity is File &&
              entity.path.contains(widget.request.fileName) &&
              await entity.length() > 0) {
            downloadedFile = entity;
            break;
          }
        }
      }

      if (downloadedFile == null) {
        throw Exception(context.l10n.ytDownloadFinishedNoFile);
      }

      if (!mounted) return;

      setState(() {
        _progress = 100;
        _status = context.l10n.ytDownloadCompleted;
        _savedPath = downloadedFile!.path;
        _phase = _DialogPhase.completed;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = '$error';
        _phase = _DialogPhase.error;
      });
    } finally {
      await _progressSubscription?.cancel();
      _progressSubscription = null;
      _activeProcessId = null;
    }
  }

  bool get _isBusy => _phase == _DialogPhase.downloading;

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context);

    return PopScope(
      canPop: !_isBusy,
      child: AnimatedPadding(
        padding: EdgeInsets.only(bottom: viewInsets.bottom),
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 440,
              maxHeight: MediaQuery.sizeOf(context).height * 0.85,
            ),
            child: Container(
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                    child: _buildHeader(context),
                  ),
                  const SizedBox(height: 18),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: _buildBody(context),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                    child: _buildFooter(context),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);

    final (
      Color badgeColor,
      IconData badgeIcon,
      String title,
      String subtitle,
    ) = switch (_phase) {
      _DialogPhase.downloading => (
        AppTheme.accent,
        _isInitializing ? Icons.settings_rounded : Icons.download_rounded,
        _isInitializing
            ? context.l10n.ytPreparingDownloader
            : context.l10n.ytDownloading,
        _isInitializing ? context.l10n.ytPreparingDownloaderSubtitle : _status,
      ),
      _DialogPhase.completed => (
        AppTheme.accent,
        Icons.check_rounded,
        context.l10n.ytDownloadCompleted,
        widget.request.format.label,
      ),
      _DialogPhase.error => (
        Colors.redAccent,
        Icons.close_rounded,
        context.l10n.ytDownloadFailed,
        context.l10n.ytDownloadFailedSubtitle,
      ),
    };

    return Row(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 128,
              height: 72,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.surfaceVariant, width: 0.7),
                color: AppTheme.surfaceVariant,
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.network(
                widget.video.thumbnails.highResUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => ColoredBox(
                  color: AppTheme.surfaceVariant,
                  child: Icon(
                    Icons.video_library_rounded,
                    color: AppTheme.accent,
                  ),
                ),
              ),
            ),
            Positioned(
              right: -6,
              bottom: -6,
              child: Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: badgeColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.surface, width: 3),
                ),
                child: Icon(badgeIcon, size: 14, color: Colors.white),
              ),
            ),
          ],
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.video.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
        if (!_isBusy)
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded),
            tooltip: context.l10n.close,
            visualDensity: VisualDensity.compact,
            color: AppTheme.textSecondary,
          ),
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (_phase) {
      case _DialogPhase.downloading:
        return _buildProgressBody(context);
      case _DialogPhase.completed:
        return _buildCompletedBody(context);
      case _DialogPhase.error:
        return _buildErrorBody(context);
    }
  }

  Widget _buildProgressBody(BuildContext context) {
    final theme = Theme.of(context);
    final hasProgress = _progress > 0;

    return Column(
      key: const ValueKey('progress'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                widget.video.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
            if (hasProgress) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(50),
                ),
                child: Text(
                  '${_progress.toStringAsFixed(0)}%',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: AppTheme.accent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: hasProgress ? (_progress / 100).clamp(0.0, 1.0) : null,
            minHeight: 8,
            backgroundColor: AppTheme.surfaceVariant,
            color: AppTheme.accent,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          context.l10n.ytDoNotClose,
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppTheme.textSecondary,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }

  Widget _buildCompletedBody(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      key: const ValueKey('completed'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.check_circle_rounded, color: AppTheme.accent, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                context.l10n.ytFileSavedSuccessfully,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        if (_savedPath != null) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.surfaceVariant, width: 0.7),
            ),
            child: Text(
              _savedPath!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildErrorBody(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      key: const ValueKey('error'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.red.withValues(alpha: 0.35),
              width: 0.7,
            ),
          ),
          child: Text(
            _errorMessage ?? context.l10n.ytUnexpectedError,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFooter(BuildContext context) {
    switch (_phase) {
      case _DialogPhase.downloading:
        return const SizedBox.shrink();

      case _DialogPhase.completed:
        return SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => Navigator.pop(context),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.done_rounded, size: 18),
            label: Text(context.l10n.ytDownloadClose),
          ),
        );

      case _DialogPhase.error:
        return SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => Navigator.pop(context),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.close_rounded, size: 18),
            label: Text(context.l10n.ytDownloadClose),
          ),
        );
    }
  }
}
