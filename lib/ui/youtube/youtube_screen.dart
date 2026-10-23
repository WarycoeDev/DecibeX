import 'dart:async';
import 'dart:io';

import 'package:extractor/extractor.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../../core/services/library_scanner.dart';

import '../app_theme.dart';

class YouTubeScreen extends StatefulWidget {
  const YouTubeScreen({super.key});

  @override
  State<YouTubeScreen> createState() => _YouTubeScreenState();
}

class _YouTubeScreenState extends State<YouTubeScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final YoutubeExplode _yt = YoutubeExplode();
  final YoutubeDLFlutter _downloader = YoutubeDLFlutter.instance;
  final ScrollController _scrollController = ScrollController();

  late final AnimationController _entryController;

  List<Video> _results = [];
  // Guardamos la lista paginada para poder pedir más resultados.
  VideoSearchList? _searchList;
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _isDownloading = false;
  String? _query;

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
      value: 1,
    );

    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _scrollController.dispose();
    _entryController.dispose();
    _yt.close();
    super.dispose();
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;

    FocusScope.of(context).unfocus();

    setState(() {
      _isLoading = true;
      _results = [];
      _searchList = null;
      _query = trimmed;
    });

    try {
      // Obtenemos la lista paginada (contiene los primeros 20).
      final searchList = await _yt.search.search(trimmed);
      if (!mounted) return;

      setState(() {
        _searchList = searchList;
        _results = searchList.take(20).toList();
        _isLoading = false;
      });

      _entryController.forward(from: 0);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _message('Error al buscar: $error');
    }
  }

  Future<void> _loadMore() async {
    if (_searchList == null || _isLoadingMore || _isLoading) return;

    setState(() => _isLoadingMore = true);

    try {
      // nextPage() devuelve la siguiente página o null si no hay más.
      final nextPage = await _searchList!.nextPage();
      if (!mounted) return;

      if (nextPage == null) {
        _message('No hay más resultados.');
        setState(() => _isLoadingMore = false);
        return;
      }

      // Actualizamos la lista de búsqueda con la nueva página.
      _searchList = nextPage;

      setState(() {
        // Añadimos los nuevos resultados (máximo 20 por página).
        _results.addAll(nextPage.take(20));
        _isLoadingMore = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
      _message('Error al cargar más: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final desktop = constraints.maxWidth >= 800;
          final horizontal = desktop ? 36.0 : 16.0;

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
                        desktop ? 32 : 20,
                        horizontal,
                        0,
                      ),
                      sliver: SliverToBoxAdapter(child: _buildHeader(desktop)),
                    ),
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        horizontal,
                        desktop ? 24 : 18,
                        horizontal,
                        0,
                      ),
                      sliver: SliverToBoxAdapter(child: _buildSearchField()),
                    ),
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        horizontal,
                        desktop ? 28 : 22,
                        horizontal,
                        0,
                      ),
                      sliver: SliverToBoxAdapter(child: _buildSectionHeader()),
                    ),
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        horizontal,
                        14,
                        horizontal,
                        desktop ? 36 : 24,
                      ),
                      sliver: _buildContent(desktop),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(bool desktop) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'BUSCAR EN YOUTUBE',
          style: theme.textTheme.labelMedium?.copyWith(
            color: AppTheme.accent,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.6,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Explora y descarga',
          style:
              (desktop
                      ? theme.textTheme.headlineLarge
                      : theme.textTheme.headlineSmall)
                  ?.copyWith(fontWeight: FontWeight.bold, letterSpacing: -0.8),
        ),
        const SizedBox(height: 8),
        Text(
          'Busca videos o audio de YouTube y elige el formato de descarga.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppTheme.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildSearchField() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.surfaceVariant, width: 0.7),
      ),
      child: TextField(
        controller: _searchController,
        textInputAction: TextInputAction.search,
        onSubmitted: _search,
        decoration: InputDecoration(
          hintText: 'Buscar en YouTube...',
          hintStyle: TextStyle(color: AppTheme.textSecondary),
          prefixIcon: Icon(Icons.search_rounded, color: AppTheme.accent),
          suffixIcon: _searchController.text.isEmpty
              ? IconButton(
                  onPressed: () => _search(_searchController.text),
                  icon: Icon(
                    Icons.arrow_forward_rounded,
                    color: AppTheme.accent,
                  ),
                  tooltip: 'Buscar',
                )
              : IconButton(
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _results = [];
                      _searchList = null;
                      _query = null;
                      _isLoading = false;
                    });
                  },
                  icon: Icon(
                    Icons.close_rounded,
                    color: AppTheme.textSecondary,
                  ),
                  tooltip: 'Borrar',
                ),
          filled: true,
          fillColor: AppTheme.surfaceVariant.withValues(alpha: 0.35),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(
              color: AppTheme.accent.withValues(alpha: 0.6),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader() {
    final String title;
    final String subtitle;

    if (_isLoading) {
      title = 'Buscando…';
      subtitle = 'Consultando YouTube';
    } else if (_query == null) {
      title = 'Resultados';
      subtitle = 'Escribe algo para empezar a buscar';
    } else if (_results.isEmpty) {
      title = 'Sin resultados';
      subtitle = 'No se encontraron coincidencias para "$_query"';
    } else {
      title = 'Resultados';
      subtitle =
          '${_results.length} ${_results.length == 1 ? "resultado" : "resultados"} para "$_query"';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: AppTheme.textSecondary),
        ),
      ],
    );
  }

  Widget _buildContent(bool desktop) {
    if (_isLoading) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(48),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (_query == null || _results.isEmpty) {
      final hasQuery = _query != null;

      return SliverToBoxAdapter(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.surfaceVariant, width: 0.7),
          ),
          child: Column(
            children: [
              Icon(
                hasQuery ? Icons.search_off_rounded : Icons.search_rounded,
                size: 42,
                color: AppTheme.accent,
              ),
              const SizedBox(height: 16),
              Text(
                hasQuery ? 'Sin resultados' : 'Empieza tu búsqueda',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                hasQuery
                    ? 'Prueba con otras palabras.'
                    : 'Busca un video, una canción o un canal.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    return DecoratedSliver(
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.surfaceVariant, width: 0.7),
        borderRadius: BorderRadius.circular(18),
      ),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            // Si estamos en el último índice, mostramos el botón de cargar más.
            if (index == _results.length) {
              return Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: desktop ? 20 : 12,
                  vertical: 16,
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _isLoadingMore ? null : _loadMore,
                    icon: _isLoadingMore
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.expand_more_rounded),
                    label: Text(
                      _isLoadingMore ? 'Cargando…' : 'Buscar más resultados',
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

            final video = _results[index];

            return Column(
              children: [
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _isDownloading
                        ? null
                        : () => _showDownloadMenu(video),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: desktop ? 20 : 12,
                        vertical: desktop ? 12 : 10,
                      ),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(11),
                            child: SizedBox(
                              width: desktop ? 140 : 120,
                              height: desktop ? 79 : 68,
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
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  video.author,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: AppTheme.textSecondary),
                                ),
                                if (video.duration != null)
                                  Text(
                                    _formatDuration(video.duration!),
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
                            onPressed: _isDownloading
                                ? null
                                : () => _showDownloadMenu(video),
                            icon: const Icon(Icons.more_horiz_rounded),
                            color: AppTheme.textSecondary,
                            tooltip: 'Descargar',
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (index != _results.length - 1)
                  Divider(
                    height: 1,
                    thickness: 0.7,
                    indent: desktop ? 20 : 12,
                    endIndent: desktop ? 20 : 12,
                    color: AppTheme.surfaceVariant,
                  ),
              ],
            );
          },
          childCount: _results.length + 1, // +1 para el botón de "Buscar más".
          addAutomaticKeepAlives: false,
        ),
      ),
    );
  }

  Future<void> _showDownloadMenu(Video video) async {
    if (_isDownloading) return;

    String directory = '';

    try {
      final downloads = await getDownloadsDirectory();
      final fallback = await getExternalStorageDirectory();
      directory = (downloads ?? fallback)?.path ?? '';
    } catch (_) {}

    if (!mounted) return;

    setState(() => _isDownloading = true);

    try {
      final request = await showModalBottomSheet<_DownloadRequest>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) {
          return _DownloadSheetContent(
            video: video,
            initialDirectory: directory,
            onError: _message,
          );
        },
      );

      if (request == null || !mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return _DownloadProgressDialog(
            video: video,
            request: request,
            downloader: _downloader,
            onError: _message,
          );
        },
      );
    } finally {
      if (mounted) {
        setState(() => _isDownloading = false);
      }
    }
  }

  String _formatDuration(Duration duration) {
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
}

/// Datos que se pasan del menú de descarga al diálogo de progreso.
class _DownloadRequest {
  final AudioFormat format;
  final String fileName;
  final String directory;
  final Video video;

  const _DownloadRequest({
    required this.format,
    required this.fileName,
    required this.directory,
    required this.video,
  });
}

/// Contenido del bottom sheet de configuración de descarga.
class _DownloadSheetContent extends StatefulWidget {
  final Video video;
  final String initialDirectory;
  final void Function(String message) onError;

  const _DownloadSheetContent({
    required this.video,
    required this.initialDirectory,
    required this.onError,
  });

  @override
  State<_DownloadSheetContent> createState() => _DownloadSheetContentState();
}

class _DownloadSheetContentState extends State<_DownloadSheetContent> {
  late final TextEditingController _nameController;
  late String _directory;
  AudioFormat? _selectedFormat;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: _sanitizeFileName(widget.video.title),
    );
    _directory = widget.initialDirectory;
  }

  @override
  void dispose() {
    _nameController.dispose();
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

  /// Tile estilo playlist (selección con check circular animado).
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
      widget.onError('Escribe un nombre de archivo válido.');
      return;
    }
    if (_directory.isEmpty) {
      widget.onError('Elige una carpeta de descarga.');
      return;
    }

    FocusScope.of(context).unfocus();

    Navigator.pop(
      context,
      _DownloadRequest(
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

    final canDownload =
        _selectedFormat != null &&
        _nameController.text.trim().isNotEmpty &&
        _directory.isNotEmpty;

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
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
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.88,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle superior
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // Cabecera con thumbnail rectangular (16:9) + título
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          // Proporción 16:9 para que la carátula se vea completa.
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
                            'Descargar',
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
                      tooltip: 'Cerrar',
                      visualDensity: VisualDensity.compact,
                      color: AppTheme.textSecondary,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Contenido scrollable
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Directorio de guardado',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _optionTile(
                        icon: Icons.folder_outlined,
                        title: _directory.isEmpty
                            ? 'Elegir carpeta'
                            : _directory,
                        subtitle: 'Seleccionar ubicación',
                        showCheck: false,
                        onTap: () async {
                          final picked = await FilePicker.getDirectoryPath(
                            dialogTitle: 'Elegir carpeta de descarga',
                            initialDirectory: _directory.isEmpty
                                ? null
                                : _directory,
                          );

                          if (picked != null) {
                            setState(() => _directory = picked);
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Nombre del archivo',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _nameController,
                        onChanged: (_) => setState(() {}),
                        decoration: _inputDecoration(
                          'Nombre sin extensión',
                          Icons.drive_file_rename_outline_rounded,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Formato de descarga',
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
                          subtitle: format.subtitle,
                          selected: _selectedFormat == format,
                          onTap: () {
                            setState(() => _selectedFormat = format);
                          },
                        ),
                    ],
                  ),
                ),
              ),

              // Botones cuadrados estilo playlist
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Row(
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
                        child: const Text('Cancelar'),
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
                        label: const Text('Descargar'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Diálogo de descarga: progreso, completado y error en un solo widget
/// con la misma estética que el bottom sheet de configuración.
class _DownloadProgressDialog extends StatefulWidget {
  final Video video;
  final _DownloadRequest request;
  final YoutubeDLFlutter downloader;
  final void Function(String message) onError;

  const _DownloadProgressDialog({
    required this.video,
    required this.request,
    required this.downloader,
    required this.onError,
  });

  @override
  State<_DownloadProgressDialog> createState() =>
      _DownloadProgressDialogState();
}

enum _DialogPhase { downloading, completed, error }

class _DownloadProgressDialogState extends State<_DownloadProgressDialog> {
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
      widget.onError(
        'La descarga con Extractor solo está habilitada en Android.',
      );
      if (mounted) Navigator.pop(context);
      return;
    }

    setState(() {
      _phase = _DialogPhase.downloading;
      _isInitializing = true;
      _progress = 0;
      _status = 'Inicializando el descargador…';
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
            initResult.errorMessage ??
            'No se pudo inicializar Extractor. Verifica tu conexión a internet.';
        throw Exception(errorMsg);
      }

      if (!mounted) return;

      final processId = 'decibex_${DateTime.now().microsecondsSinceEpoch}';
      _activeProcessId = processId;

      setState(() {
        _isInitializing = false;
        _status = 'Descargando audio…';
      });

      await _progressSubscription?.cancel();

      _progressSubscription = widget.downloader.onProgress.listen((progress) {
        if (!mounted || progress.processId != _activeProcessId) return;

        setState(() {
          _progress = progress.progress;
          _status = 'Descargando audio…';
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
          result.errorMessage ?? 'No se pudo descargar el audio.',
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
        throw Exception(
          'La descarga terminó pero no se encontró el archivo generado.',
        );
      }

      if (!mounted) return;

      //unawaited(LibraryScanner.instance.scan());

      setState(() {
        _progress = 100;
        _status = 'Descarga completada';
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

  // ---------------------------------------------------------------------------
  // Construcción unificada
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isBusy,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 440),
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
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
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.88,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle superior
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),

                // Cabecera con thumbnail rectangular 16:9 + badge de estado
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _buildHeader(context),
                ),
                const SizedBox(height: 18),

                // Cuerpo variable según la fase
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: _buildBody(context),
                    ),
                  ),
                ),

                // Botones al pie
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: _buildFooter(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Cabecera común (thumbnail rectangular + badge según estado)
  // ---------------------------------------------------------------------------

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
        _isInitializing ? 'Preparando descargador' : 'Descargando…',
        _isInitializing ? 'Esto puede tardar la primera vez' : _status,
      ),
      _DialogPhase.completed => (
        AppTheme.accent,
        Icons.check_rounded,
        'Descarga completada',
        widget.request.format.label,
      ),
      _DialogPhase.error => (
        Colors.redAccent,
        Icons.close_rounded,
        'No se pudo descargar',
        'Ocurrió un error inesperado',
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
            tooltip: 'Cerrar',
            visualDensity: VisualDensity.compact,
            color: AppTheme.textSecondary,
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Cuerpo variable
  // ---------------------------------------------------------------------------

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
          'No cierres esta ventana mientras se descarga.',
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
                'Archivo guardado correctamente',
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
            _errorMessage ?? 'Ocurrió un error inesperado.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Pie con botones estilo menú
  // ---------------------------------------------------------------------------

  Widget _buildFooter(BuildContext context) {
    switch (_phase) {
      case _DialogPhase.downloading:
        // Sin botones durante la descarga (no se puede cerrar).
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
            label: const Text('Cerrar'),
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
            label: const Text('Cerrar'),
          ),
        );
    }
  }
}

enum AudioFormat {
  mp3(
    label: 'MP3',
    subtitle: 'Comprimido y compatible',
    extension: 'mp3',
    icon: Icons.audiotrack_rounded,
  ),
  flac(
    label: 'FLAC',
    subtitle: 'Audio sin pérdida',
    extension: 'flac',
    icon: Icons.graphic_eq_rounded,
  ),
  wav(
    label: 'WAV',
    subtitle: 'Audio sin comprimir',
    extension: 'wav',
    icon: Icons.multitrack_audio_rounded,
  );

  final String label;
  final String subtitle;
  final String extension;
  final IconData icon;

  const AudioFormat({
    required this.label,
    required this.subtitle,
    required this.extension,
    required this.icon,
  });
}
