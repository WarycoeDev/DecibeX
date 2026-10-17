import 'package:flutter/material.dart';

class Song {
  final String title;
  final String artist;
  final String album;
  final String duration;
  final IconData icon;
  final Color color;
  final bool favorite;
  final String? filePath;
  final String? artworkPath;

  const Song({
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    this.icon = Icons.music_note_rounded,
    this.color = const Color(0xFF6750A4),
    this.favorite = false,
    this.filePath,
    this.artworkPath,
  });

  Song copyWith({bool? favorite}) {
    return Song(
      title: title,
      artist: artist,
      album: album,
      duration: duration,
      icon: icon,
      color: color,
      favorite: favorite ?? this.favorite,
      filePath: filePath,
      artworkPath: artworkPath,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'artist': artist,
      'album': album,
      'duration': duration,
      'favorite': favorite,
      'filePath': filePath,
      'artworkPath': artworkPath,
    };
  }

  factory Song.fromJson(Map<String, dynamic> json) {
    return Song(
      title: json['title'] as String? ?? 'Desconocido',
      artist: json['artist'] as String? ?? 'Artista desconocido',
      album: json['album'] as String? ?? 'Álbum desconocido',
      duration: json['duration'] as String? ?? '0:00',
      favorite: json['favorite'] as bool? ?? false,
      filePath: json['filePath'] as String?,
      artworkPath: json['artworkPath'] as String?,
    );
  }
}
