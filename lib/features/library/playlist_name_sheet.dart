import 'dart:io';

import 'package:flutter/material.dart';

import '../../ui/app_theme.dart';
import '../../core/models/song.dart';

/// Modal bottom sheet estilizado para crear o renombrar una playlist.
/// Muestra carátula (si hay) con un badge de acción en la esquina inferior
/// derecha, igual que el diálogo de eliminación.
class PlaylistNameSheet extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String confirmLabel;
  final String? initialName;

  /// Canciones de la playlist para resolver la carátula. Si es null o vacío,
  /// se muestra un placeholder con degradado.
  final List<Song>? songs;

  /// Badge de acción en la esquina inferior derecha de la carátula.
  /// Si es null, se usa [icon].
  final IconData? badgeIcon;

  /// Color del badge. Por defecto, el acento de la app.
  final Color? badgeColor;

  const PlaylistNameSheet({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.confirmLabel,
    this.initialName,
    this.songs,
    this.badgeIcon,
    this.badgeColor,
  });

  @override
  State<PlaylistNameSheet> createState() => _PlaylistNameSheetState();
}

class _PlaylistNameSheetState extends State<PlaylistNameSheet> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _canSubmit = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName ?? '');
    _focusNode = FocusNode();
    _canSubmit = _controller.text.trim().isNotEmpty;
    _controller.addListener(_onChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  void _onChanged() {
    final value = _controller.text.trim().isNotEmpty;
    if (value != _canSubmit) {
      setState(() => _canSubmit = value);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(context, name);
  }

  /// Resuelve el artwork de la playlist a partir de sus canciones.
  Widget _buildArtwork() {
    final songs = widget.songs ?? const <Song>[];
    final path = songs.isNotEmpty ? songs.first.artworkPath : null;

    Widget placeholder() {
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppTheme.accent.withValues(alpha: 0.25),
              AppTheme.accent.withValues(alpha: 0.08),
            ],
          ),
        ),
        alignment: Alignment.center,
        child: Icon(
          Icons.queue_music_rounded,
          color: AppTheme.accent,
          size: 44,
        ),
      );
    }

    if (path == null || path.isEmpty) return placeholder();

    return Image.file(
      File(path),
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => placeholder(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final badgeColor = widget.badgeColor ?? AppTheme.accent;
    final badgeIcon = widget.badgeIcon ?? widget.icon;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
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
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle superior
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),

                // Carátula con badge de acción
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: AppTheme.surfaceVariant,
                          width: 0.7,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: _buildArtwork(),
                    ),
                    Positioned(
                      right: -6,
                      bottom: -6,
                      child: Container(
                        width: 32,
                        height: 32,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: badgeColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppTheme.surface, width: 3),
                        ),
                        child: Icon(badgeIcon, size: 16, color: Colors.white),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // Título
                Text(
                  widget.title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 8),

                // Subtítulo
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 340),
                  child: Text(
                    widget.subtitle,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppTheme.textSecondary,
                      height: 1.45,
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Campo de texto
                TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  maxLength: 60,
                  style: theme.textTheme.bodyLarge,
                  decoration: InputDecoration(
                    hintText: 'Nombre de la playlist',
                    hintStyle: TextStyle(color: AppTheme.textSecondary),
                    counterText: '',
                    filled: true,
                    fillColor: AppTheme.surfaceVariant,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                    prefixIcon: Icon(
                      Icons.queue_music_rounded,
                      color: AppTheme.textSecondary,
                      size: 20,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: AppTheme.surfaceVariant,
                        width: 0.7,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: AppTheme.accent,
                        width: 1.4,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Botones
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
                        child: const Text('Cancelar'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _canSubmit ? _submit : null,
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
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: Text(widget.confirmLabel),
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

/// Helper para mostrar el sheet como modal bottom sheet.
Future<String?> showPlaylistNameSheet(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String subtitle,
  required String confirmLabel,
  String? initialName,
  List<Song>? songs,
  IconData? badgeIcon,
  Color? badgeColor,
}) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => PlaylistNameSheet(
      icon: icon,
      title: title,
      subtitle: subtitle,
      confirmLabel: confirmLabel,
      initialName: initialName,
      songs: songs,
      badgeIcon: badgeIcon,
      badgeColor: badgeColor,
    ),
  );
}
