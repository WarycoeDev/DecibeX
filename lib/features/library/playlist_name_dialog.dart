import 'package:decibex/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

import '../../ui/app_theme.dart';

class PlaylistNameDialog extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String confirmLabel;
  final String? initialName;

  const PlaylistNameDialog({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.confirmLabel,
    this.initialName,
  });

  @override
  State<PlaylistNameDialog> createState() => PlaylistNameDialogState();
}

class PlaylistNameDialogState extends State<PlaylistNameDialog> {
  static const int _maxLength = 80;

  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName ?? '');
    _focusNode = FocusNode();
    if (_controller.text.isNotEmpty) {
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCompact = MediaQuery.sizeOf(context).width < 400;
    final headerPadding = EdgeInsets.fromLTRB(
      isCompact ? 16 : 24,
      24,
      isCompact ? 8 : 16,
      20,
    );

    return Dialog(
      backgroundColor: AppTheme.surfaceVariant,
      surfaceTintColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isCompact ? 16 : 24,
        vertical: 24,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: headerPadding,
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(13),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          AppTheme.accent,
                          Color.lerp(AppTheme.accent, Colors.black, 0.65)!,
                        ],
                      ),
                    ),
                    child: Icon(widget.icon, color: Colors.white, size: 27),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.subtitle,
                          maxLines: 2,
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
                    tooltip: context.l10n.close,
                  ),
                ],
              ),
            ),
            Divider(
              height: 1,
              color: AppTheme.textSecondary.withValues(alpha: 0.16),
            ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _controller,
              builder: (context, value, _) {
                final length = value.text.length;

                return Padding(
                  padding: EdgeInsets.fromLTRB(
                    isCompact ? 16 : 24,
                    16,
                    isCompact ? 16 : 24,
                    20,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              context.l10n.playlistName,
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: length == 0
                                  ? AppTheme.accent.withValues(alpha: 0.07)
                                  : AppTheme.accent.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(50),
                            ),
                            child: Text(
                              '$length/$_maxLength',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: AppTheme.accent,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        autofocus: true,
                        maxLength: _maxLength,
                        textInputAction: TextInputAction.done,
                        textCapitalization: TextCapitalization.sentences,
                        onSubmitted: (_) => _submit(),
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                        cursorColor: AppTheme.accent,
                        decoration: InputDecoration(
                          hintText: context.l10n.typePlaylistName,
                          counterText: '',
                          filled: true,
                          fillColor: AppTheme.surface,
                          prefixIcon: Icon(
                            Icons.edit_note_rounded,
                            color: AppTheme.textSecondary,
                          ),
                          suffixIcon: value.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: context.l10n.clear,
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    size: 20,
                                  ),
                                  onPressed: _controller.clear,
                                ),
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
                              color: AppTheme.accent,
                              width: 1.4,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            Divider(
              height: 1,
              color: AppTheme.textSecondary.withValues(alpha: 0.16),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                isCompact ? 16 : 24,
                16,
                isCompact ? 16 : 24,
                20,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.textSecondary,
                    ),
                    child: Text(context.l10n.cancel),
                  ),
                  const SizedBox(width: 8),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _controller,
                    builder: (context, value, _) {
                      return FilledButton.icon(
                        onPressed: value.text.trim().isEmpty ? null : _submit,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.accent,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: AppTheme.accent.withValues(
                            alpha: 0.3,
                          ),
                          disabledForegroundColor: Colors.white70,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        icon: const Icon(Icons.check_rounded),
                        label: Text(widget.confirmLabel),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
