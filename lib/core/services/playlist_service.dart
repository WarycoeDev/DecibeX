import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/playlist.dart';
import '../models/song.dart';
import 'library_scanner.dart';

class PlaylistService extends ChangeNotifier {
  PlaylistService._();

  static final PlaylistService instance = PlaylistService._();
  static const String extension = '.decibex';
  static const String _directoryName = 'playlist';

  final List<Playlist> _playlists = [];
  bool _initialized = false;
  Future<void>? _initializing;

  List<Playlist> get playlists => List.unmodifiable(_playlists);
  bool get isInitialized => _initialized;

  Future<Directory> getDirectory() async {
    final Directory base;
    if (Platform.isAndroid) {
      final external = await getExternalStorageDirectory();
      base = external == null
          ? await getApplicationSupportDirectory()
          : Directory('${Directory(external.path).parent.path}/data');
    } else {
      base = await getApplicationSupportDirectory();
    }
    final directory = Directory('${base.path}/$_directoryName');
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  Future<void> initialize() async {
    if (_initialized) return;
    if (_initializing != null) return _initializing;
    _initializing = _load();
    try {
      await _initializing;
    } finally {
      _initializing = null;
    }
  }

  Future<void> _load() async {
    final directory = await getDirectory();
    final loaded = <Playlist>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File || !entity.path.toLowerCase().endsWith(extension))
        continue;
      try {
        final content = await entity.readAsString();
        final decoded = jsonDecode(content);
        if (decoded is Map<String, dynamic>) {
          loaded.add(Playlist.fromJson(decoded));
        } else if (decoded is Map) {
          loaded.add(Playlist.fromJson(Map<String, dynamic>.from(decoded)));
        }
      } catch (error) {
        debugPrint('[PlaylistService] No se pudo leer ${entity.path}: $error');
      }
    }
    loaded.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    _playlists
      ..clear()
      ..addAll(loaded);
    _initialized = true;
    notifyListeners();
  }

  Future<Playlist> create(String name, {List<Song> songs = const []}) async {
    await initialize();
    final cleanName = _validateName(name);
    if (_nameExists(cleanName))
      throw ArgumentError('Ya existe una playlist con ese nombre.');
    final now = DateTime.now();
    final playlist = Playlist(
      id: '${now.microsecondsSinceEpoch}',
      name: cleanName,
      songPaths: _uniquePaths(
        songs.map((song) => song.filePath).whereType<String>(),
      ),
      createdAt: now,
      updatedAt: now,
    );
    await _write(playlist);
    _playlists.add(playlist);
    _sort();
    notifyListeners();
    return playlist;
  }

  Future<Playlist> rename(Playlist playlist, String name) async {
    await initialize();
    final cleanName = _validateName(name);
    if (_playlists.any(
      (item) =>
          item.id != playlist.id &&
          item.name.toLowerCase() == cleanName.toLowerCase(),
    )) {
      throw ArgumentError('Ya existe una playlist con ese nombre.');
    }
    final updated = playlist.copyWith(name: cleanName);
    await _write(updated);
    if (_safeFileName(playlist.name) != _safeFileName(updated.name)) {
      await _deleteFileFor(playlist);
    }
    _replace(updated);
    _sort();
    notifyListeners();
    return updated;
  }

  Future<void> delete(Playlist playlist) async {
    await initialize();
    final file = await _fileFor(playlist);
    if (await file.exists()) await file.delete();
    _playlists.removeWhere((item) => item.id == playlist.id);
    notifyListeners();
  }

  Future<Playlist> addSongs(Playlist playlist, List<Song> songs) async {
    final paths = _uniquePaths([
      ...playlist.songPaths,
      ...songs.map((song) => song.filePath).whereType<String>(),
    ]);
    return updateSongs(playlist, paths);
  }

  Future<Playlist> removeSongAt(Playlist playlist, int index) async {
    if (index < 0 || index >= playlist.songPaths.length) return playlist;
    final paths = List<String>.from(playlist.songPaths)..removeAt(index);
    return updateSongs(playlist, paths);
  }

  Future<Playlist> reorder(
    Playlist playlist,
    int oldIndex,
    int newIndex,
  ) async {
    final paths = List<String>.from(playlist.songPaths);
    if (oldIndex < 0 || oldIndex >= paths.length) return playlist;
    if (newIndex > oldIndex) newIndex--;
    if (newIndex < 0 || newIndex >= paths.length || oldIndex == newIndex)
      return playlist;
    final path = paths.removeAt(oldIndex);
    paths.insert(newIndex, path);
    return updateSongs(playlist, paths);
  }

  Future<Playlist> updateSongs(Playlist playlist, List<String> paths) async {
    await initialize();
    final updated = playlist.copyWith(songPaths: _uniquePaths(paths));
    await _write(updated);
    _replace(updated);
    notifyListeners();
    return updated;
  }

  List<Song> resolveSongs(Playlist playlist) {
    final byPath = <String, Song>{};
    for (final song in LibraryScanner.instance.songs) {
      final path = song.filePath;
      if (path != null && path.isNotEmpty) byPath[path] = song;
    }
    return playlist.songPaths
        .map((path) => byPath[path])
        .whereType<Song>()
        .toList(growable: false);
  }

  Playlist? findById(String id) {
    for (final playlist in _playlists) {
      if (playlist.id == id) return playlist;
    }
    return null;
  }

  Future<void> _write(Playlist playlist) async {
    final file = await _fileFor(playlist);
    await file.writeAsString(playlist.encode(), flush: true);
  }

  Future<File> _fileFor(Playlist playlist) async {
    final directory = await getDirectory();
    return File('${directory.path}/${_safeFileName(playlist.name)}$extension');
  }

  Future<void> _deleteFileFor(Playlist playlist) async {
    final file = await _fileFor(playlist);
    if (await file.exists()) await file.delete();
  }

  String _validateName(String name) {
    final clean = name.trim();
    if (clean.isEmpty)
      throw ArgumentError('El nombre de la playlist no puede estar vacío.');
    if (clean.length > 80)
      throw ArgumentError('El nombre no puede superar 80 caracteres.');
    if (clean.contains('/') ||
        clean.contains('\\') ||
        clean == '.' ||
        clean == '..') {
      throw ArgumentError('El nombre contiene caracteres no válidos.');
    }
    return clean;
  }

  bool _nameExists(String name) =>
      _playlists.any((item) => item.name.toLowerCase() == name.toLowerCase());

  String _safeFileName(String name) => name
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  List<String> _uniquePaths(Iterable<String> paths) {
    final seen = <String>{};
    return paths
        .where((path) => path.trim().isNotEmpty && seen.add(path))
        .toList();
  }

  void _replace(Playlist updated) {
    final index = _playlists.indexWhere((item) => item.id == updated.id);
    if (index >= 0) _playlists[index] = updated;
  }

  void _sort() => _playlists.sort(
    (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
  );
}
