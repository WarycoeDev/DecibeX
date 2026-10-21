import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:media_metadata/media_metadata.dart';
import 'package:path_provider/path_provider.dart';

import '../models/song.dart';

class LibraryScanner extends ChangeNotifier {
  LibraryScanner._();

  static final LibraryScanner instance = LibraryScanner._();

  static const _settingsFileName = 'settings.decibex';
  static const _indexFileName = 'library_index.json';
  static const _favoritesFileName = 'favorites.json';

  static const _audioExtensions = {
    '.mp3',
    '.flac',
    '.m4a',
    '.mp4',
    '.ogg',
    '.opus',
    '.wav',
    '.aiff',
    '.aif',
    '.ape',
    '.webm',
    '.mkv',
    '.mov',
  };

  static const int _parallelism = 3;
  static const int _publishBatchSize = 50;

  final Map<String, Map<String, dynamic>> _index = {};
  final List<StreamSubscription<FileSystemEvent>> _watchers = [];
  final LinkedHashSet<String> _favoritePaths = LinkedHashSet<String>();
  final List<String> _favoriteOrderPaths = [];

  List<Song> _songs = [];
  List<String> _directories = [];
  List<String> _podcastDirectories = [];

  Timer? _periodicTimer;
  Timer? _debounceTimer;
  Timer? _settingsDebounceTimer;

  StreamSubscription<FileSystemEvent>? _settingsWatcher;

  Future<void>? _activeScan;
  Future<void>? _configurationRefresh;
  Future<void> _favoritesWriteQueue = Future<void>.value();

  bool _recursive = true;
  bool _initialized = false;
  bool _disposed = false;
  bool _scanRequested = false;
  bool _configurationRefreshRequested = false;
  bool _legacyFavoritesFound = false;

  int _configurationRevision = 0;

  bool isScanning = false;
  String? error;
  DateTime? lastScan;

  List<Song> get songs => UnmodifiableListView<Song>(_songs);

  List<Song> get musicSongs =>
      UnmodifiableListView(_songs.where((song) => !song.isPodcast));

  List<Song> get podcasts =>
      UnmodifiableListView(_songs.where((song) => song.isPodcast));

  int get songCount => _songs.where((song) => !song.isPodcast).length;

  int get podcastCount => _songs.where((song) => song.isPodcast).length;

  Future<Directory> _settingsDirectory() async {
    if (Platform.isAndroid) {
      final external = await getExternalStorageDirectory();

      if (external != null) {
        return Directory('${external.path}/data');
      }
    }

    return getApplicationSupportDirectory();
  }

  Future<Directory> _dataDirectory() async {
    late final Directory directory;

    if (Platform.isAndroid) {
      final external = await getExternalStorageDirectory();

      if (external != null) {
        directory = external;
      } else {
        final support = await getApplicationSupportDirectory();
        directory = Directory('${support.path}/decibex');
      }
    } else {
      final support = await getApplicationSupportDirectory();
      directory = Directory('${support.path}/decibex');
    }

    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    return directory;
  }

  Future<Directory> _cacheDirectory() async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory('${support.path}/decibex/library_cache');

    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    return directory;
  }

  Future<File> _favoritesFile() async {
    final directory = await _dataDirectory();
    return File('${directory.path}/$_favoritesFileName');
  }

  void _notifyIfAlive() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  Future<void> initialize() async {
    if (_initialized || _disposed) return;

    _initialized = true;

    try {
      await _loadIndex();
      if (_disposed) return;

      await _loadFavorites();
      if (_disposed) return;

      if (_legacyFavoritesFound) {
        await _saveIndex();
        _legacyFavoritesFound = false;
      }

      _publishSongs();
      if (_disposed) return;

      await refreshConfiguration();
      if (_disposed) return;

      _periodicTimer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => unawaited(refreshConfiguration()),
      );
    } catch (e) {
      if (_disposed) return;

      error = 'No se pudo inicializar la biblioteca: $e';
      _notifyIfAlive();
    }
  }

  Future<void> _loadIndex() async {
    final cacheDirectory = await _cacheDirectory();
    final file = File('${cacheDirectory.path}/$_indexFileName');

    if (!await file.exists() || _disposed) return;

    try {
      final decoded = jsonDecode(await file.readAsString());
      if (_disposed) return;

      if (decoded is Map) {
        for (final item in decoded.entries) {
          if (item.key is! String || item.value is! Map) continue;

          try {
            final path = item.key as String;
            final entry = Map<String, dynamic>.from(item.value as Map);

            if (entry.remove('favorite') == true) {
              _favoritePaths.add(path);
              _legacyFavoritesFound = true;
            }

            if (entry.containsKey('favorite')) {
              entry.remove('favorite');
              _legacyFavoritesFound = true;
            }

            entry['mediaType'] = entry['mediaType'] == 'podcast'
                ? 'podcast'
                : 'music';

            _index[path] = entry;
          } catch (_) {}
        }
      }
    } catch (_) {
      _index.clear();
    }
  }

  Future<void> _loadFavorites() async {
    if (_disposed) return;

    final file = await _favoritesFile();
    if (_disposed) return;

    if (!await file.exists()) {
      await _saveFavorites();
      return;
    }

    try {
      final decoded = jsonDecode(await file.readAsString());
      if (_disposed) return;

      if (decoded is Map) {
        final favorites = decoded['favorites'];

        if (favorites is List) {
          _favoritePaths
            ..clear()
            ..addAll(favorites.whereType<String>());
        }

        final order = decoded['favoriteOrder'];
        if (order is List) {
          _favoriteOrderPaths
            ..clear()
            ..addAll(order.whereType<String>());
        } else {
          _favoriteOrderPaths
            ..clear()
            ..addAll(_favoritePaths);
        }
      } else if (decoded is List) {
        _favoritePaths
          ..clear()
          ..addAll(decoded.whereType<String>());

        _favoriteOrderPaths
          ..clear()
          ..addAll(_favoritePaths);
      }
    } catch (e) {
      debugPrint('[LibraryScanner] No se pudieron cargar los favoritos: $e');
    }
  }

  Future<void> _saveIndex() async {
    if (_disposed) return;

    final cacheDirectory = await _cacheDirectory();
    if (_disposed) return;

    final file = File('${cacheDirectory.path}/$_indexFileName');
    final temporaryFile = File('${file.path}.tmp');

    final cleanIndex = <String, Map<String, dynamic>>{};

    for (final item in _index.entries) {
      final entry = Map<String, dynamic>.from(item.value);
      entry.remove('favorite');
      cleanIndex[item.key] = entry;
    }

    final contents = jsonEncode(cleanIndex);
    await temporaryFile.writeAsString(contents, flush: true);
    if (_disposed) return;

    try {
      await temporaryFile.rename(file.path);
    } catch (_) {
      await file.writeAsString(contents, flush: true);

      if (await temporaryFile.exists()) {
        await temporaryFile.delete();
      }
    }
  }

  Future<void> _saveFavorites() {
    final snapshot = List<String>.from(_favoritePaths);
    final orderSnapshot = List<String>.from(_favoriteOrderPaths);

    final operation = _favoritesWriteQueue.then((_) async {
      if (_disposed) return;

      final file = await _favoritesFile();
      if (_disposed) return;

      final temporaryFile = File('${file.path}.tmp');

      final contents = jsonEncode({
        'favorites': snapshot,
        'favoriteOrder': orderSnapshot,
      });

      await temporaryFile.writeAsString(contents, flush: true);
      if (_disposed) return;

      try {
        await temporaryFile.rename(file.path);
      } catch (_) {
        await file.writeAsString(contents, flush: true);

        if (await temporaryFile.exists()) {
          await temporaryFile.delete();
        }
      }
    });

    _favoritesWriteQueue = operation.catchError((Object e) {
      debugPrint('[LibraryScanner] Error guardando favoritos: $e');
    });

    return operation;
  }

  Future<void> refreshConfiguration() {
    if (_disposed) return Future<void>.value();

    _configurationRefreshRequested = true;
    final active = _configurationRefresh;

    if (active != null) return active;

    final operation = _runConfigurationRefreshQueue();
    _configurationRefresh = operation;

    return operation.whenComplete(() {
      if (identical(_configurationRefresh, operation)) {
        _configurationRefresh = null;
      }

      if (_configurationRefreshRequested && !_disposed) {
        unawaited(refreshConfiguration());
      }
    });
  }

  Future<void> _runConfigurationRefreshQueue() async {
    do {
      _configurationRefreshRequested = false;
      if (_disposed) return;

      await _readConfigurationOnce();
    } while (_configurationRefreshRequested && !_disposed);
  }

  List<String> _normalizeDirectories(dynamic raw) {
    if (raw is! List) return [];

    final paths = raw
        .whereType<String>()
        .map((path) => path.trim())
        .where((path) => path.isNotEmpty)
        .map((path) => Directory(path).absolute.path)
        .toSet()
        .toList();

    paths.sort();
    return paths;
  }

  Future<void> _readConfigurationOnce() async {
    try {
      final directory = await _settingsDirectory();
      if (_disposed) return;

      await _configureSettingsWatcher(directory);
      if (_disposed) return;

      final file = File('${directory.path}/$_settingsFileName');

      if (!await file.exists()) {
        if (_directories.isNotEmpty || _podcastDirectories.isNotEmpty) {
          error =
              'No se encontró el archivo de configuración. '
              'Se conservará la configuración anterior.';
          _notifyIfAlive();
          return;
        }

        if (lastScan == null) {
          await scan();
        }

        return;
      }

      final decoded = jsonDecode(await file.readAsString());
      if (_disposed || decoded is! Map) return;

      final directories = _normalizeDirectories(decoded['scanDirectories']);
      final podcastDirectories = _normalizeDirectories(
        decoded['podcastDirectories'],
      );

      final recursive = decoded['scanSubdirectories'] is bool
          ? decoded['scanSubdirectories'] as bool
          : true;

      final changed =
          !_sameDirectories(_directories, directories) ||
          !_sameDirectories(_podcastDirectories, podcastDirectories) ||
          _recursive != recursive;

      if (changed) {
        _directories = directories;
        _podcastDirectories = podcastDirectories;
        _recursive = recursive;
        _configurationRevision++;

        await _configureWatchers();
        if (_disposed) return;

        await scan();
      } else if (lastScan == null) {
        await scan();
      }

      if (!_disposed) {
        error = null;
        _notifyIfAlive();
      }
    } catch (e) {
      if (_disposed) return;

      error = 'No se pudo actualizar la configuración: $e';
      _notifyIfAlive();
    }
  }

  bool _sameDirectories(List<String> a, List<String> b) {
    if (a.length != b.length) return false;

    final setA = a.toSet();
    final setB = b.toSet();

    return setA.length == setB.length && setA.containsAll(setB);
  }

  Future<void> _configureSettingsWatcher(Directory directory) async {
    if (_disposed || _settingsWatcher != null) return;

    try {
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      if (_disposed) return;

      _settingsWatcher = directory
          .watch(events: FileSystemEvent.all, recursive: false)
          .listen(
            (_) => _scheduleConfigurationRefresh(),
            onError: (_) => _scheduleConfigurationRefresh(),
          );
    } catch (_) {}
  }

  void _scheduleConfigurationRefresh() {
    if (_disposed) return;

    _settingsDebounceTimer?.cancel();
    _settingsDebounceTimer = Timer(const Duration(milliseconds: 200), () {
      if (!_disposed) {
        unawaited(refreshConfiguration());
      }
    });
  }

  Future<void> _configureWatchers() async {
    final oldWatchers = List<StreamSubscription<FileSystemEvent>>.from(
      _watchers,
    );

    _watchers.clear();

    for (final watcher in oldWatchers) {
      try {
        await watcher.cancel();
      } catch (_) {}
    }

    if (_disposed) return;

    final allDirectories = <String>{..._directories, ..._podcastDirectories};

    for (final path in allDirectories) {
      if (_disposed) return;

      try {
        final directory = Directory(path);
        if (!await directory.exists()) continue;

        final subscription = directory
            .watch(events: FileSystemEvent.all, recursive: _recursive)
            .listen((_) => _scheduleScan(), onError: (_) => _scheduleScan());

        _watchers.add(subscription);
      } catch (_) {}
    }
  }

  void _scheduleScan() {
    if (_disposed) return;

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 350), () {
      if (!_disposed) {
        unawaited(scan());
      }
    });
  }

  Future<void> scan() {
    if (_disposed) return Future<void>.value();

    final active = _activeScan;

    if (active != null) {
      _scanRequested = true;
      return active;
    }

    _scanRequested = false;
    final operation = _runScanQueue();
    _activeScan = operation;

    return operation.whenComplete(() {
      if (identical(_activeScan, operation)) {
        _activeScan = null;
      }

      if (_scanRequested && !_disposed) {
        unawaited(scan());
      }
    });
  }

  Future<void> _runScanQueue() async {
    do {
      _scanRequested = false;
      if (_disposed) return;

      await _performScan();
    } while (_scanRequested && !_disposed);
  }

  Future<void> _performScan() async {
    if (_disposed) return;

    isScanning = true;
    error = null;
    _notifyIfAlive();

    final scanDirectories = List<String>.from(_directories);
    final podcastDirectories = List<String>.from(_podcastDirectories);
    final recursive = _recursive;
    final revision = _configurationRevision;

    try {
      final files = <String, File>{};
      final mediaTypes = <String, String>{};
      var enumerationComplete = true;

      Future<void> enumerate(
        List<String> directories, {
        required String mediaType,
      }) async {
        for (final path in directories) {
          if (_disposed) return;

          final directory = Directory(path);

          try {
            if (!await directory.exists()) {
              enumerationComplete = false;
              continue;
            }

            await for (final entity in directory.list(
              recursive: recursive,
              followLinks: false,
            )) {
              if (_disposed) return;
              if (entity is! File) continue;
              if (!_audioExtensions.contains(_extension(entity.path))) continue;

              final absolutePath = entity.absolute.path;
              files[absolutePath] = entity;
              mediaTypes[absolutePath] = mediaType;
            }
          } catch (e) {
            enumerationComplete = false;
            debugPrint('[LibraryScanner] No se pudo leer "$path": $e');
          }
        }
      }

      await enumerate(scanDirectories, mediaType: 'music');
      await enumerate(podcastDirectories, mediaType: 'podcast');

      if (_disposed) return;

      final cacheDirectory = await _cacheDirectory();
      if (_disposed) return;

      final fileList = files.values.toList(growable: false);
      var nextIndex = 0;
      var processed = 0;

      Future<void> worker() async {
        while (!_disposed) {
          final currentIndex = nextIndex++;

          if (currentIndex >= fileList.length) return;

          final file = fileList[currentIndex];
          await _processFile(
            file,
            cacheDirectory.path,
            mediaType: mediaTypes[file.absolute.path] ?? 'music',
          );

          if (_disposed) return;

          processed++;

          if (processed % _publishBatchSize == 0) {
            _publishSongs();
          }
        }
      }

      final workerCount = fileList.length < _parallelism
          ? fileList.length
          : _parallelism;

      await Future.wait(List.generate(workerCount, (_) => worker()));
      if (_disposed) return;

      final configurationUnchanged = revision == _configurationRevision;

      if (enumerationComplete && configurationUnchanged) {
        final activePaths = files.keys.toSet();

        final removedPaths = _index.keys
            .where((path) => !activePaths.contains(path))
            .toList();

        for (final path in removedPaths) {
          if (_disposed) return;

          final previous = _index.remove(path);
          final artworkPath = previous?['artworkPath'];

          if (artworkPath is String) {
            try {
              final artwork = File(artworkPath);
              if (await artwork.exists()) {
                await artwork.delete();
              }
            } catch (_) {}
          }
        }
      } else if (!enumerationComplete) {
        error =
            'El escaneo terminó parcialmente. '
            'Se conservaron los archivos que no pudieron verificarse.';
      }

      _publishSongs();
      await _saveIndex();
      if (_disposed) return;

      lastScan = DateTime.now();
    } catch (e, stackTrace) {
      if (!_disposed) {
        error = 'Error durante el escaneo: $e';
        debugPrint('$stackTrace');
      }
    } finally {
      isScanning = false;
      _notifyIfAlive();
    }
  }

  Future<void> _processFile(
    File file,
    String cacheDirectoryPath, {
    required String mediaType,
  }) async {
    if (_disposed) return;

    final path = file.absolute.path;

    try {
      final stat = await file.stat();
      if (_disposed) return;

      final previous = _index[path];

      final unchanged =
          previous != null &&
          previous['modified'] == stat.modified.millisecondsSinceEpoch &&
          previous['size'] == stat.size &&
          (previous['mediaType'] == 'podcast' ? 'podcast' : 'music') ==
              mediaType;

      if (unchanged) return;

      final metadata = await MediaMetadata.read(path);
      if (_disposed) return;

      final title =
          _nonEmpty(metadata?.title) ?? _filenameWithoutExtension(path);
      final artist = _nonEmpty(metadata?.artist) ?? 'Artista desconocido';
      final album = _nonEmpty(metadata?.album) ?? 'Álbum desconocido';
      final duration = _formatDuration(metadata?.duration);

      String? artworkPath = previous?['artworkPath'] as String?;
      final imageData = metadata?.imageMetadata?.data;

      if (imageData != null && imageData.isNotEmpty) {
        final imageFile = File('$cacheDirectoryPath/${_stableId(path)}.art');
        await imageFile.writeAsBytes(imageData, flush: true);
        artworkPath = imageFile.path;
      }

      _index[path] = {
        'title': title,
        'artist': artist,
        'album': album,
        'duration': duration,
        'filePath': path,
        'artworkPath': artworkPath,
        'mediaType': mediaType,
        'modified': stat.modified.millisecondsSinceEpoch,
        'size': stat.size,
        // Conserva la ganancia ReplayGain ya calculada (si existía).
        'replayGainDb': previous?['replayGainDb'],
      };
    } catch (e) {
      if (_disposed) return;

      final previous = _index[path];

      _index[path] = {
        'title': previous?['title'] ?? _filenameWithoutExtension(path),
        'artist': previous?['artist'] ?? 'Artista desconocido',
        'album': previous?['album'] ?? 'Álbum desconocido',
        'duration': previous?['duration'] ?? '0:00',
        'filePath': path,
        'artworkPath': previous?['artworkPath'],
        'mediaType': mediaType,
        'modified': previous?['modified'] ?? 0,
        'size': previous?['size'] ?? 0,
        // Conserva la ganancia ReplayGain ya calculada (si existía).
        'replayGainDb': previous?['replayGainDb'],
      };

      debugPrint('[LibraryScanner] No se pudo procesar "$path": $e');
    }
  }

  void _publishSongs() {
    if (_disposed) return;

    final songs = <Song>[];

    for (final item in _index.entries) {
      try {
        final songData = Map<String, dynamic>.from(item.value);
        songData['favorite'] = _favoritePaths.contains(item.key);

        final song = Song.fromJson(songData);

        if (song.filePath != null) {
          songs.add(song);
        }
      } catch (e) {
        debugPrint('[LibraryScanner] Entrada de índice inválida: $e');
      }
    }

    final keyed = [for (final song in songs) MapEntry(_sortKey(song), song)];

    keyed.sort((a, b) {
      final byName = a.key.compareTo(b.key);
      if (byName != 0) return byName;

      return (a.value.filePath ?? '').compareTo(b.value.filePath ?? '');
    });

    _songs = keyed.map((entry) => entry.value).toList();
    _notifyIfAlive();
  }

  // ------------------------------------------------------------------
  // ReplayGain por archivo
  // ------------------------------------------------------------------

  /// Guarda la ganancia ReplayGain calculada para [song] en el índice
  /// en memoria y republica la lista. NO escribe el índice a disco: el
  /// llamador controla el batching con [saveIndexNow].
  Future<void> setReplayGain(Song song, double? gainDb) async {
    if (_disposed) return;

    final path = song.filePath;
    if (path == null || !_index.containsKey(path)) return;

    _index[path]!['replayGainDb'] = gainDb;
    _publishSongs();
  }

  /// Persiste el índice actual en disco inmediatamente.
  Future<void> saveIndexNow() async {
    if (_disposed) return;
    await _saveIndex();
  }

  // ------------------------------------------------------------------
  // Favoritos
  // ------------------------------------------------------------------

  List<Song> orderFavorites(Iterable<Song> songs) {
    final favorites = songs.where((song) => song.favorite).toList();
    final positions = <String, int>{};

    for (var i = 0; i < _favoriteOrderPaths.length; i++) {
      positions[_favoriteOrderPaths[i]] = i;
    }

    favorites.sort((a, b) {
      final pathA = a.filePath ?? '';
      final pathB = b.filePath ?? '';
      final positionA = positions[pathA];
      final positionB = positions[pathB];

      if (positionA != null && positionB != null) {
        return positionA.compareTo(positionB);
      }
      if (positionA != null) return -1;
      if (positionB != null) return 1;

      final byTitle = _sortKey(a).compareTo(_sortKey(b));
      return byTitle != 0 ? byTitle : pathA.compareTo(pathB);
    });

    return favorites;
  }

  Future<void> setFavoriteOrder(List<Song> songs) async {
    if (_disposed) return;

    final orderedPaths = songs
        .map((song) => song.filePath)
        .whereType<String>()
        .where((path) => _favoritePaths.contains(path))
        .toList();

    for (final path in _favoritePaths) {
      if (!orderedPaths.contains(path)) {
        orderedPaths.add(path);
      }
    }

    _favoriteOrderPaths
      ..clear()
      ..addAll(orderedPaths);

    _notifyIfAlive();
    await _saveFavorites();
  }

  Future<void> setFavorite(Song song, bool favorite) async {
    if (_disposed) return;

    final path = song.filePath;
    if (path == null || !_index.containsKey(path)) return;

    final wasFavorite = _favoritePaths.contains(path);
    if (wasFavorite == favorite) return;

    final previousOrder = List<String>.from(_favoriteOrderPaths);

    if (favorite) {
      _favoritePaths.add(path);
      if (!_favoriteOrderPaths.contains(path)) {
        _favoriteOrderPaths.add(path);
      }
    } else {
      _favoritePaths.remove(path);
      _favoriteOrderPaths.remove(path);
    }

    _publishSongs();

    try {
      await _saveFavorites();
    } catch (e) {
      if (_disposed) return;

      if (wasFavorite) {
        _favoritePaths.add(path);
      } else {
        _favoritePaths.remove(path);
      }

      _favoriteOrderPaths
        ..clear()
        ..addAll(previousOrder);

      _publishSongs();
      error = 'No se pudo guardar el favorito: $e';
      _notifyIfAlive();
    }
  }

  // ------------------------------------------------------------------
  // Helpers
  // ------------------------------------------------------------------

  String _extension(String path) {
    final name = path.split(Platform.pathSeparator).last;
    final dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot).toLowerCase();
  }

  String _filenameWithoutExtension(String path) {
    final name = path.split(Platform.pathSeparator).last;
    final dot = name.lastIndexOf('.');
    return dot <= 0 ? name : name.substring(0, dot);
  }

  String? _nonEmpty(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return value.trim();
  }

  String _sortKey(Song song) {
    final path = song.filePath;
    final name = path == null ? song.title : _filenameWithoutExtension(path);
    return _removeAccents(name.trim().toLowerCase());
  }

  String _removeAccents(String input) {
    const from = 'áàäâéèëêíìïîóòöôúùüû';
    const to = 'aaaaeeeeiiiioooouuuu';

    final buffer = StringBuffer();

    for (final char in input.split('')) {
      final index = from.indexOf(char);
      buffer.write(index == -1 ? char : to[index]);
    }

    return buffer.toString();
  }

  String _formatDuration(Duration? duration) {
    if (duration == null || duration.isNegative) return '0:00';

    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');

    if (hours > 0) {
      return '$hours:$minutes:$seconds';
    }

    return '${duration.inMinutes}:$seconds';
  }

  String _stableId(String path) {
    var hash = 0xCBF29CE484222325;

    for (final unit in path.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x100000001B3) & 0xFFFFFFFFFFFFFFFF;
    }

    return hash.toRadixString(16);
  }

  @override
  void dispose() {
    _disposed = true;

    _periodicTimer?.cancel();
    _debounceTimer?.cancel();
    _settingsDebounceTimer?.cancel();

    final settingsWatcher = _settingsWatcher;
    if (settingsWatcher != null) {
      unawaited(settingsWatcher.cancel());
    }

    for (final watcher in _watchers) {
      unawaited(watcher.cancel());
    }

    _watchers.clear();
    super.dispose();
  }
}
