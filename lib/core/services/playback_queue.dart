import 'package:flutter/foundation.dart';

import '../models/song.dart';

class PlaybackQueue extends ChangeNotifier {
  PlaybackQueue._();

  static final PlaybackQueue instance = PlaybackQueue._();

  final List<Song> _songs = [];

  List<Song> get songs => List.unmodifiable(_songs);

  bool get isEmpty => _songs.isEmpty;

  bool get isNotEmpty => _songs.isNotEmpty;

  int get length => _songs.length;

  bool contains(Song song) {
    return _songs.any((item) => _sameSong(item, song));
  }

  bool add(Song song) {
    if (contains(song)) {
      debugPrint('[PlaybackQueue] Canción duplicada: ${song.title}');
      return false;
    }

    _songs.add(song);
    _logQueue('Canción añadida: ${song.title}');
    notifyListeners();
    return true;
  }

  bool remove(Song song) {
    final index = _songs.indexWhere((item) => _sameSong(item, song));

    if (index == -1) {
      debugPrint('[PlaybackQueue] Canción no encontrada: ${song.title}');
      return false;
    }

    final removed = _songs.removeAt(index);
    _logQueue('Canción eliminada: ${removed.title}');
    notifyListeners();
    return true;
  }

  void replace(Song song) {
    _songs
      ..clear()
      ..add(song);

    _logQueue('Cola sobrescrita con: ${song.title}');
    notifyListeners();
  }

  void clear() {
    if (_songs.isEmpty) {
      debugPrint('[PlaybackQueue] La cola ya está vacía');
      return;
    }

    _songs.clear();
    _logQueue('Cola vaciada');
    notifyListeners();
  }

  bool _sameSong(Song a, Song b) {
    final pathA = a.filePath?.trim();
    final pathB = b.filePath?.trim();

    if (pathA != null &&
        pathA.isNotEmpty &&
        pathB != null &&
        pathB.isNotEmpty) {
      return pathA.replaceAll('\\', '/') == pathB.replaceAll('\\', '/');
    }

    return a.title.trim().toLowerCase() == b.title.trim().toLowerCase() &&
        a.artist.trim().toLowerCase() == b.artist.trim().toLowerCase();
  }

  void _logQueue(String action) {
    debugPrint('[PlaybackQueue] $action');
    debugPrint('[PlaybackQueue] Canciones en cola: ${_songs.length}');

    for (var i = 0; i < _songs.length; i++) {
      debugPrint(
        '[PlaybackQueue] ${i + 1}. ${_songs[i].title} - ${_songs[i].artist}',
      );
    }
  }
}
