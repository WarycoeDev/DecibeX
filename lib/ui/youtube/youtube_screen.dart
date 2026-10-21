import 'package:flutter/material.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:universal_youtube_player/universal_youtube_player.dart';

import '../app_theme.dart';

class YouTubeScreen extends StatefulWidget {
  const YouTubeScreen({super.key});

  @override
  State<YouTubeScreen> createState() => _YouTubeScreenState();
}

class _YouTubeScreenState extends State<YouTubeScreen> {
  final TextEditingController _searchController = TextEditingController();
  final YoutubeExplode _yt = YoutubeExplode();

  // El tipo devuelto por search() en la versión 3.x sigue siendo VideoSearchList (List<Video>)
  List<Video> _results = [];
  bool _isLoading = false;

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) return;

    FocusScope.of(context).unfocus();

    setState(() {
      _isLoading = true;
      _results = [];
    });

    try {
      final searchList = await _yt.search.search(query);

      if (!mounted) return;

      setState(() {
        _results = searchList.toList();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() => _isLoading = false);

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al buscar: $e')));
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _yt.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surface,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              textInputAction: TextInputAction.search,
              onSubmitted: _search,
              decoration: InputDecoration(
                hintText: 'Buscar en YouTube...',
                hintStyle: TextStyle(color: AppTheme.textSecondary),
                prefixIcon: Icon(Icons.search, color: AppTheme.accent),
                suffixIcon: IconButton(
                  tooltip: 'Buscar',
                  icon: Icon(Icons.arrow_forward, color: AppTheme.accent),
                  onPressed: () => _search(_searchController.text),
                ),
                filled: true,
                fillColor: AppTheme.surfaceVariant,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _results.isEmpty
                ? Center(
                    child: Text(
                      'Escribe algo para buscar en YouTube',
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _results.length,
                    separatorBuilder: (_, __) =>
                        Divider(height: 1, color: AppTheme.surfaceVariant),
                    itemBuilder: (context, index) {
                      final video = _results[index];

                      // En la versión 3.x, thumbnails sigue siendo un ThumbnailSet.
                      // highResUrl es la propiedad correcta para la URL de alta calidad.
                      final thumbnailUrl = video.thumbnails.highResUrl;

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: 120,
                            height: 68,
                            child: Image.network(
                              thumbnailUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  const Icon(Icons.video_library),
                            ),
                          ),
                        ),
                        title: Text(
                          video.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          video.author,
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        onTap: () => _playVideo(video.url),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _playVideo(String videoUrl) {
    // UniversalYoutubePlayer acepta la URL completa directamente.
    if (videoUrl.isEmpty) return;

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          backgroundColor: AppTheme.surface,
          appBar: AppBar(
            backgroundColor: AppTheme.surface,
            foregroundColor: Colors.white,
            title: const Text('Reproduciendo'),
          ),
          body: SafeArea(
            // Usamos el reproductor universal que funciona en PC y móvil.
            child: UniversalYoutubePlayer(url: videoUrl),
          ),
        ),
      ),
    );
  }
}
