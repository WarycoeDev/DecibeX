import 'package:flutter/material.dart';

class Song {
  final String title;
  final String artist;
  final String album;
  final String duration;
  final IconData icon;
  final Color color;
  final bool favorite;

  const Song({
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    required this.icon,
    required this.color,
    this.favorite = false,
  });
}
