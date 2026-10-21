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
  final String mediaType;

  /// Ganancia ReplayGain calculada para este archivo, en dB.
  /// `null` significa que aún no se ha analizado.
  final double? replayGainDb;

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
    this.mediaType = 'music',
    this.replayGainDb,
  });

  bool get isPodcast => mediaType == 'podcast';

  Song copyWith({
    String? title,
    String? artist,
    String? album,
    String? duration,
    IconData? icon,
    Color? color,
    bool? favorite,
    String? filePath,
    String? artworkPath,
    String? mediaType,
    double? replayGainDb,
  }) {
    return Song(
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      duration: duration ?? this.duration,
      icon: icon ?? this.icon,
      color: color ?? this.color,
      favorite: favorite ?? this.favorite,
      filePath: filePath ?? this.filePath,
      artworkPath: artworkPath ?? this.artworkPath,
      mediaType: mediaType ?? this.mediaType,
      replayGainDb: replayGainDb ?? this.replayGainDb,
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
      'mediaType': mediaType,
      'replayGainDb': replayGainDb,
    };
  }

  factory Song.fromJson(Map<String, dynamic> json) {
    return Song(
      title: json['title'] is String ? json['title'] as String : '',
      artist: json['artist'] is String ? json['artist'] as String : '',
      album: json['album'] is String ? json['album'] as String : '',
      duration: json['duration'] is String
          ? json['duration'] as String
          : '0:00',
      favorite: json['favorite'] is bool ? json['favorite'] as bool : false,
      filePath: json['filePath'] is String ? json['filePath'] as String : null,
      artworkPath: json['artworkPath'] is String
          ? json['artworkPath'] as String
          : null,
      mediaType: json['mediaType'] == 'podcast' ? 'podcast' : 'music',
      replayGainDb: json['replayGainDb'] is num
          ? (json['replayGainDb'] as num).toDouble()
          : null,
    );
  }
}
