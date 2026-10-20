import 'dart:convert';

class Playlist {
  final String id;
  final String name;
  final List<String> songPaths;
  final DateTime createdAt;
  final DateTime updatedAt;

  Playlist({
    required this.id,
    required this.name,
    List<String> songPaths = const [],
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : songPaths = List.unmodifiable(songPaths),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  int get songCount => songPaths.length;

  Playlist copyWith({
    String? id,
    String? name,
    List<String>? songPaths,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Playlist(
      id: id ?? this.id,
      name: name ?? this.name,
      songPaths: songPaths ?? this.songPaths,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'format': 'decibex-playlist',
    'version': 1,
    'id': id,
    'name': name,
    'songPaths': songPaths,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory Playlist.fromJson(Map<String, dynamic> json) {
    final paths = json['songPaths'];
    return Playlist(
      id:
          json['id']?.toString() ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      name: json['name']?.toString() ?? 'Playlist',
      songPaths: paths is List ? paths.whereType<String>().toList() : const [],
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());
}
