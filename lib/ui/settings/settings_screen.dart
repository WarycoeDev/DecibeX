import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../app_theme.dart';
import '../../core/services/replay_gain_service.dart';
import '../../core/services/settings_service.dart';

enum _LayoutSize { compact, medium, expanded }

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const String _settingsFileName = 'settings.decibex';

  static const List<_AccentOption> _accentOptions = [
    _AccentOption('Violeta', Color(0xFF6750A4)),
    _AccentOption('Azul', Color(0xFF4285F4)),
    _AccentOption('Cian', Color(0xFF00A6B2)),
    _AccentOption('Verde', Color(0xFF40916C)),
    _AccentOption('Naranja', Color(0xFFE58A35)),
    _AccentOption('Rosa', Color(0xFFD65D91)),
    _AccentOption('Rojo', Color(0xFFD94848)),
  ];

  bool _isLoading = true;
  bool _isSaving = false;
  bool _saveAgain = false;

  String? _storagePath;
  String? _storageError;

  bool _darkTheme = AppTheme.defaultDarkTheme;
  int _accentColorValue = 0xFF6750A4;

  bool _replayGainEnabled = false;
  double _replayGainPreamp = 0;

  bool _fadeInEnabled = false;
  bool _fadeOutEnabled = false;
  double _fadeInDuration = 2;
  double _fadeOutDuration = 2;

  bool _scanSubdirectories = true;
  List<String> _scanDirectories = [];
  List<String> _podcastDirectories = [];

  bool _artistsGridMode = false;
  bool _albumsGridMode = false;

  Color get _accentColor => Color(_accentColorValue);

  @override
  void initState() {
    super.initState();
    _loadSettings();
    SettingsService.instance.addListener(_onExternalSettingsChanged);
  }

  @override
  void dispose() {
    SettingsService.instance.removeListener(_onExternalSettingsChanged);
    super.dispose();
  }

  /// Refleja cambios externos (p. ej. `PlaybackService` recargó el archivo).
  void _onExternalSettingsChanged() {
    final s = SettingsService.instance;
    if (!mounted) return;

    final needsUpdate =
        _replayGainEnabled != s.replayGainEnabled ||
        _replayGainPreamp != s.replayGainPreamp ||
        _darkTheme != s.darkTheme ||
        _accentColorValue != s.accentColorValue;

    if (!needsUpdate) return;

    setState(() {
      _darkTheme = s.darkTheme;
      _accentColorValue = s.accentColorValue;
      _replayGainEnabled = s.replayGainEnabled;
      _replayGainPreamp = s.replayGainPreamp;
    });
  }

  _LayoutSize _layoutFor(double width) {
    if (width < 400) return _LayoutSize.compact;
    if (width < 800) return _LayoutSize.medium;
    return _LayoutSize.expanded;
  }

  Future<Directory> _getSettingsDirectory() async {
    if (Platform.isAndroid) {
      final externalDirectory = await getExternalStorageDirectory();

      if (externalDirectory != null) {
        return Directory('${externalDirectory.path}/data');
      }
    }

    return getApplicationSupportDirectory();
  }

  Future<File> _getSettingsFile() async {
    final directory = await _getSettingsDirectory();

    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    return File('${directory.path}/$_settingsFileName');
  }

  Future<void> _loadSettings() async {
    try {
      await SettingsService.instance.initialize();
      await SettingsService.instance.reload();

      final s = SettingsService.instance;

      _storagePath = s.storagePath;
      _darkTheme = s.darkTheme;
      _accentColorValue = s.accentColorValue;
      _replayGainEnabled = s.replayGainEnabled;
      _replayGainPreamp = s.replayGainPreamp;
      _fadeInEnabled = s.fadeInEnabled;
      _fadeOutEnabled = s.fadeOutEnabled;
      _fadeInDuration = s.fadeInDuration;
      _fadeOutDuration = s.fadeOutDuration;
      _scanSubdirectories = s.scanSubdirectories;
      _scanDirectories = List<String>.from(s.scanDirectories);
      _podcastDirectories = List<String>.from(s.podcastDirectories);
      _artistsGridMode = s.artistsGridMode;
      _albumsGridMode = s.albumsGridMode;
    } catch (error) {
      _storageError = error.toString();
    }

    AppTheme.updateAppearance(darkTheme: _darkTheme, accentColor: _accentColor);

    if (!mounted) return;

    setState(() {
      _isLoading = false;
    });
  }

  /// Sincroniza el estado local con `SettingsService` y escribe a disco.
  Future<void> _saveSettings({bool showError = true}) async {
    if (_isSaving) {
      _saveAgain = true;
      return;
    }

    _isSaving = true;

    try {
      do {
        _saveAgain = false;

        final s = SettingsService.instance;
        s.darkTheme = _darkTheme;
        s.accentColorValue = _accentColorValue;
        s.replayGainEnabled = _replayGainEnabled;
        s.replayGainPreamp = _replayGainPreamp;
        s.fadeInEnabled = _fadeInEnabled;
        s.fadeOutEnabled = _fadeOutEnabled;
        s.fadeInDuration = _fadeInDuration;
        s.fadeOutDuration = _fadeOutDuration;
        s.scanSubdirectories = _scanSubdirectories;
        s.scanDirectories = List<String>.from(_scanDirectories);
        s.podcastDirectories = List<String>.from(_podcastDirectories);
        s.artistsGridMode = _artistsGridMode;
        s.albumsGridMode = _albumsGridMode;

        await s.save();

        _storagePath = s.storagePath;
        _storageError = null;
      } while (_saveAgain);
    } catch (error) {
      _storageError = error.toString();

      if (showError && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudieron guardar los ajustes.')),
        );
      }
    } finally {
      _isSaving = false;

      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _updateSetting(VoidCallback update) async {
    setState(update);
    await _saveSettings();
  }

  Future<void> _updateAppearance(VoidCallback update) async {
    setState(update);

    AppTheme.updateAppearance(darkTheme: _darkTheme, accentColor: _accentColor);

    await _saveSettings();
  }

  Future<void> _addDirectory({required bool podcasts}) async {
    try {
      final selectedDirectory = await FilePicker.getDirectoryPath(
        dialogTitle: podcasts
            ? 'Seleccionar directorio de podcasts'
            : 'Seleccionar directorio de música',
      );

      if (selectedDirectory == null || !mounted) return;

      final directories = podcasts ? _podcastDirectories : _scanDirectories;

      if (directories.contains(selectedDirectory)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              podcasts
                  ? 'Este directorio de podcasts ya está agregado.'
                  : 'Este directorio de música ya está agregado.',
            ),
          ),
        );
        return;
      }

      setState(() {
        directories.add(selectedDirectory);
      });

      await _saveSettings();
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            podcasts
                ? 'No se pudo seleccionar el directorio de podcasts: $error'
                : 'No se pudo seleccionar el directorio de música: $error',
          ),
        ),
      );
    }
  }

  Future<void> _removeDirectory(
    String directory, {
    required bool podcasts,
  }) async {
    setState(() {
      if (podcasts) {
        _podcastDirectories.remove(directory);
      } else {
        _scanDirectories.remove(directory);
      }
    });

    await _saveSettings();
  }

  Future<void> _resetSettings() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restablecer configuración'),
        content: const Text(
          'Se restaurarán los valores predeterminados de DecibeX. '
          'Los directorios de música y podcasts también se eliminarán de sus listas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restablecer'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _darkTheme = AppTheme.defaultDarkTheme;
      _accentColorValue = AppTheme.defaultAccent.toARGB32();

      _replayGainEnabled = false;
      _replayGainPreamp = 0;

      _fadeInEnabled = false;
      _fadeOutEnabled = false;
      _fadeInDuration = 2;
      _fadeOutDuration = 2;

      _scanSubdirectories = true;
      _scanDirectories = [];
      _podcastDirectories = [];

      _artistsGridMode = false;
      _albumsGridMode = false;
    });

    AppTheme.updateAppearance(darkTheme: _darkTheme, accentColor: _accentColor);

    await _saveSettings();
  }

  // ===========================================================================
  // HELPERS DE UI — contenedor tipo bottom sheet premium
  // ===========================================================================

  /// Contenedor reutilizable que replica el estilo del selector de playlists:
  /// margen 12, radio 24, borde `surfaceVariant` 0.7, sombra elevada y
  /// altura máxima del 82 % de la pantalla.
  Widget _buildSheetContainer({
    required BuildContext context,
    required Widget child,
  }) {
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
            maxHeight: MediaQuery.sizeOf(context).height * 0.82,
          ),
          child: child,
        ),
      ),
    );
  }

  /// Handle superior (drag indicator) reutilizable.
  Widget _buildSheetHandle() {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = _layoutFor(constraints.maxWidth);
        final isDesktop = layout == _LayoutSize.expanded;
        final isCompact = layout == _LayoutSize.compact;

        final horizontal = switch (layout) {
          _LayoutSize.compact => 16.0,
          _LayoutSize.medium => 20.0,
          _LayoutSize.expanded => 36.0,
        };
        final top = switch (layout) {
          _LayoutSize.compact => 18.0,
          _LayoutSize.medium => 24.0,
          _LayoutSize.expanded => 32.0,
        };

        return SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              horizontal,
              top,
              horizontal,
              isCompact ? 24 : 36,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(theme, layout),
                    SizedBox(height: isCompact ? 22 : 30),
                    _buildSectionTitle(
                      icon: Icons.palette_outlined,
                      title: 'Apariencia',
                      subtitle: 'Personaliza el aspecto de DecibeX.',
                      layout: layout,
                    ),
                    SizedBox(height: isCompact ? 10 : 14),
                    _buildAppearanceCard(layout),
                    SizedBox(height: isCompact ? 22 : 30),
                    _buildSectionTitle(
                      icon: Icons.graphic_eq_rounded,
                      title: 'Audio',
                      subtitle: 'Preferencias de reproducción y sonido.',
                      layout: layout,
                    ),
                    SizedBox(height: isCompact ? 10 : 14),
                    _buildAudioCard(),
                    SizedBox(height: isCompact ? 22 : 30),
                    _buildSectionTitle(
                      icon: Icons.folder_open_rounded,
                      title: 'Biblioteca',
                      subtitle: 'Configura las carpetas de música y podcasts.',
                      layout: layout,
                    ),
                    SizedBox(height: isCompact ? 10 : 14),
                    _buildLibraryCard(layout),
                    SizedBox(height: isCompact ? 22 : 30),
                    _buildSectionTitle(
                      icon: Icons.info_outline_rounded,
                      title: 'Acerca de DecibeX',
                      subtitle: 'Información y estado de la configuración.',
                      layout: layout,
                    ),
                    SizedBox(height: isCompact ? 10 : 14),
                    _buildAboutCard(),
                    SizedBox(height: isCompact ? 18 : 24),
                    Center(
                      child: TextButton.icon(
                        onPressed: _resetSettings,
                        icon: const Icon(Icons.restart_alt_rounded),
                        label: const Text('Restablecer configuración'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: Text(
                        'DecibeX · Configuración local',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(ThemeData theme, _LayoutSize layout) {
    final isDesktop = layout == _LayoutSize.expanded;
    final isCompact = layout == _LayoutSize.compact;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'PERSONALIZACIÓN',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelMedium?.copyWith(
            color: _accentColor,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.6,
          ),
        ),
        SizedBox(height: isCompact ? 8 : 10),
        Text(
          'Configuración',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style:
              (isDesktop
                      ? theme.textTheme.headlineLarge
                      : theme.textTheme.headlineSmall)
                  ?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.8,
                    height: 1.15,
                  ),
        ),
        SizedBox(height: isCompact ? 6 : 8),
        Text(
          'Ajusta tu experiencia de escucha a tu manera.',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppTheme.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle({
    required IconData icon,
    required String title,
    required String subtitle,
    required _LayoutSize layout,
  }) {
    final theme = Theme.of(context);
    final isDesktop = layout == _LayoutSize.expanded;
    final isCompact = layout == _LayoutSize.compact;

    final boxSize = isDesktop ? 42.0 : (isCompact ? 36.0 : 40.0);

    return Row(
      children: [
        Container(
          width: boxSize,
          height: boxSize,
          decoration: BoxDecoration(
            color: _accentColor.withValues(alpha: 0.13),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, color: _accentColor, size: boxSize * 0.52),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCard({required List<Widget> children}) {
    return Material(
      color: AppTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: AppTheme.surfaceVariant, width: 0.7),
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: double.infinity,
        child: Column(children: children),
      ),
    );
  }

  Widget _buildAppearanceCard(_LayoutSize layout) {
    final isCompact = layout == _LayoutSize.compact;
    final swatchSize = isCompact ? 34.0 : 38.0;

    return _buildCard(
      children: [
        _SettingSwitchTile(
          icon: Icons.dark_mode_outlined,
          title: 'Tema oscuro',
          subtitle: _darkTheme
              ? 'La interfaz está configurada en oscuro.'
              : 'La interfaz está configurada en claro.',
          value: _darkTheme,
          accent: _accentColor,
          onChanged: (value) {
            _updateAppearance(() {
              _darkTheme = value;
            });
          },
        ),
        _buildDivider(),
        Padding(
          padding: EdgeInsets.all(isCompact ? 14 : 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SettingHeading(
                icon: Icons.color_lens_outlined,
                title: 'Color de acento',
                subtitle: 'Selecciona el color principal de la interfaz.',
              ),
              SizedBox(height: isCompact ? 14 : 18),
              Wrap(
                spacing: isCompact ? 10 : 12,
                runSpacing: isCompact ? 10 : 12,
                children: [
                  for (final option in _accentOptions)
                    Tooltip(
                      message: option.name,
                      child: InkWell(
                        onTap: () {
                          _updateAppearance(() {
                            _accentColorValue = option.color.toARGB32();
                          });
                        },
                        customBorder: const CircleBorder(),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          width: swatchSize,
                          height: swatchSize,
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color:
                                  _accentColorValue == option.color.toARGB32()
                                  ? option.color
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: option.color,
                            ),
                            child: _accentColorValue == option.color.toARGB32()
                                ? Icon(
                                    Icons.check_rounded,
                                    size: isCompact ? 16 : 18,
                                    color: Colors.white,
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                _accentOptions
                    .firstWhere(
                      (option) => option.color.toARGB32() == _accentColorValue,
                      orElse: () => const _AccentOption(
                        'Personalizado',
                        Color(0xFF6750A4),
                      ),
                    )
                    .name,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppTheme.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAudioCard() {
    return _buildCard(
      children: [
        _SettingSwitchTile(
          icon: Icons.equalizer_rounded,
          title: 'ReplayGain',
          subtitle: 'Normalización del volumen entre canciones.',
          value: _replayGainEnabled,
          accent: _accentColor,
          onChanged: (value) {
            _updateSetting(() {
              _replayGainEnabled = value;
            });
            // Notificación inmediata: PlaybackService lo verá en la
            // siguiente pista sin esperar al watcher del archivo.
            SettingsService.instance.setReplayGainEnabled(value);
          },
        ),
        _buildDivider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
          child: _SettingSlider(
            icon: Icons.volume_up_rounded,
            title: 'ReplayGain preamp',
            subtitle: 'Se suma a la ganancia calculada de cada pista.',
            value: _replayGainPreamp,
            min: -12,
            max: 12,
            divisions: 48,
            accent: _accentColor,
            valueLabel:
                '${_replayGainPreamp >= 0 ? "+" : ""}'
                '${_replayGainPreamp.toStringAsFixed(1)} dB',
            // Siempre activo: se puede configurar antes de activar
            // ReplayGain; solo surte efecto cuando ReplayGain está ON.
            enabled: true,
            onChanged: (value) {
              setState(() {
                _replayGainPreamp = value;
              });
              // Notificación inmediata al PlaybackService.
              SettingsService.instance.setReplayGainPreamp(value);
            },
            onChangeEnd: (_) => _saveSettings(),
          ),
        ),
        _buildDivider(),
        _buildReplayGainAnalyzer(),
        _buildDivider(),
        _SettingSwitchTile(
          icon: Icons.trending_up_rounded,
          title: 'Fade in',
          subtitle: 'Aumenta gradualmente el volumen al iniciar.',
          value: _fadeInEnabled,
          accent: _accentColor,
          onChanged: (value) {
            _updateSetting(() {
              _fadeInEnabled = value;
            });
          },
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
          child: _SettingSlider(
            icon: Icons.timer_outlined,
            title: 'Duración del fade in',
            subtitle: 'Tiempo de entrada gradual.',
            value: _fadeInDuration,
            min: 0,
            max: 10,
            divisions: 20,
            accent: _accentColor,
            valueLabel: '${_fadeInDuration.toStringAsFixed(1)} s',
            enabled: _fadeInEnabled,
            onChanged: (value) {
              setState(() {
                _fadeInDuration = value;
              });
            },
            onChangeEnd: (_) => _saveSettings(),
          ),
        ),
        _buildDivider(),
        _SettingSwitchTile(
          icon: Icons.trending_down_rounded,
          title: 'Fade out',
          subtitle: 'Reduce gradualmente el volumen al finalizar.',
          value: _fadeOutEnabled,
          accent: _accentColor,
          onChanged: (value) {
            _updateSetting(() {
              _fadeOutEnabled = value;
            });
          },
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
          child: _SettingSlider(
            icon: Icons.timer_outlined,
            title: 'Duración del fade out',
            subtitle: 'Tiempo de salida gradual.',
            value: _fadeOutDuration,
            min: 0,
            max: 10,
            divisions: 20,
            accent: _accentColor,
            valueLabel: '${_fadeOutDuration.toStringAsFixed(1)} s',
            enabled: _fadeOutEnabled,
            onChanged: (value) {
              setState(() {
                _fadeOutDuration = value;
              });
            },
            onChangeEnd: (_) => _saveSettings(),
          ),
        ),
      ],
    );
  }

  Widget _buildReplayGainAnalyzer() {
    final service = ReplayGainService.instance;

    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final running = service.isRunning;

        return Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.auto_fix_high_rounded,
                    size: 21,
                    color: _replayGainEnabled
                        ? _accentColor
                        : AppTheme.textSecondary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Calcular ReplayGain por archivo',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          'Analiza cada pista y guarda su ganancia en la biblioteca.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: AppTheme.textSecondary,
                                height: 1.4,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (service.lastError != null) ...[
                const SizedBox(height: 8),
                Text(
                  service.lastError!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.orange),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: (running || !_replayGainEnabled || kIsWeb)
                          ? null
                          : () => _showAnalyzeDialog(),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Analizar pendientes'),
                      style: FilledButton.styleFrom(
                        backgroundColor: _accentColor,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: _accentColor.withValues(
                          alpha: 0.35,
                        ),
                        disabledForegroundColor: Colors.white.withValues(
                          alpha: 0.7,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Reanalizar toda la biblioteca',
                    onPressed: (running || !_replayGainEnabled || kIsWeb)
                        ? null
                        : () => _confirmReanalyze(),
                    icon: const Icon(Icons.refresh_rounded),
                    color: _accentColor,
                  ),
                  IconButton(
                    tooltip: 'Borrar ganancias calculadas',
                    onPressed: (running || !_replayGainEnabled || kIsWeb)
                        ? null
                        : () => _confirmClearReplayGain(),
                    icon: const Icon(Icons.delete_outline_rounded),
                    color: AppTheme.textSecondary,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // ===========================================================================
  // DIÁLOGO: ANALIZAR PENDIENTES (con estado "no hay pistas nuevas")
  // ===========================================================================

  Future<void> _showAnalyzeDialog() async {
    final service = ReplayGainService.instance;

    // Lanza el análisis antes de mostrar el diálogo para que el
    // estado "running" esté disponible de inmediato.
    final future = service.analyzeLibrary();

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (sheetContext) {
        return PopScope(
          canPop: false,
          child: AnimatedBuilder(
            animation: service,
            builder: (context, _) {
              final theme = Theme.of(context);
              final total = service.total;
              final processed = service.processed;
              final running = service.isRunning;
              final finished = !running;
              final progress = total == 0 ? 0.0 : processed / total;
              final percent = (progress * 100).clamp(0, 100).toStringAsFixed(0);

              // [NUEVO] Estado "sin pistas pendientes":
              // - O bien el servicio ya no corre y total == 0 (terminó al instante).
              // - O bien no había pendientes desde el inicio.
              final noPending = finished && total == 0;

              return _buildSheetContainer(
                context: context,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildSheetHandle(),
                    const SizedBox(height: 18),

                    // Header
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: AppTheme.surfaceVariant,
                                    width: 0.7,
                                  ),
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      _accentColor,
                                      Color.lerp(
                                        _accentColor,
                                        Colors.black,
                                        0.55,
                                      )!,
                                    ],
                                  ),
                                ),
                                child: Icon(
                                  noPending
                                      ? Icons.check_circle_outline_rounded
                                      : Icons.graphic_eq_rounded,
                                  color: Colors.white.withValues(alpha: 0.95),
                                  size: 32,
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
                                    color: _accentColor,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: AppTheme.surface,
                                      width: 3,
                                    ),
                                  ),
                                  child: running
                                      ? SizedBox(
                                          width: 12,
                                          height: 12,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                            value: total == 0 ? null : progress,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.check_rounded,
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
                                  running
                                      ? 'Calculando ReplayGain'
                                      : noPending
                                      ? 'No hay pistas nuevas'
                                      : 'ReplayGain completado',
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  running
                                      ? 'Analizando $processed de $total…'
                                      : noPending
                                      ? 'Todas las pistas ya tienen su ganancia.'
                                      : 'Análisis finalizado.',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  running
                                      ? 'Normalización de volumen por pista'
                                      : noPending
                                      ? 'No se ha analizado ninguna pista nueva.'
                                      : 'Ganancias guardadas en la biblioteca',
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
                            onPressed: running
                                ? null
                                : () => Navigator.pop(sheetContext),
                            icon: const Icon(Icons.close_rounded),
                            tooltip: 'Cerrar',
                            visualDensity: VisualDensity.compact,
                            color: AppTheme.textSecondary,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // [NUEVO] Si no hay pendientes, mostramos solo una
                    // caja informativa en lugar del subheader + barra.
                    if (noPending)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _accentColor.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _accentColor.withValues(alpha: 0.30),
                              width: 0.7,
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.info_outline_rounded,
                                size: 18,
                                color: _accentColor,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Usa el botón de reanalizar si quieres volver '
                                  'a calcular las ganancias de toda la biblioteca.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: AppTheme.textSecondary,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else ...[
                      // Subheader con píldora de progreso
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Progreso del análisis',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: AppTheme.textSecondary,
                                  fontWeight: FontWeight.w600,
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
                                color: (running || percent != '0')
                                    ? _accentColor.withValues(alpha: 0.16)
                                    : AppTheme.surfaceVariant,
                                borderRadius: BorderRadius.circular(50),
                              ),
                              child: Text(
                                running
                                    ? '$percent %'
                                    : (finished ? 'Listo' : '$percent %'),
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: (running || percent != '0')
                                      ? _accentColor
                                      : AppTheme.textSecondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Barra de progreso + metadatos + error
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: LinearProgressIndicator(
                                value: total == 0 ? null : progress,
                                color: _accentColor,
                                backgroundColor: AppTheme.surfaceVariant,
                                minHeight: 8,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  running
                                      ? '$processed / $total pistas'
                                      : '$total pistas procesadas',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                                Text(
                                  percent == '100' || finished
                                      ? 'Completado'
                                      : '$percent %',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: _accentColor,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            if (service.lastError != null) ...[
                              const SizedBox(height: 10),
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: Colors.orange.withValues(
                                      alpha: 0.35,
                                    ),
                                    width: 0.7,
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(
                                      Icons.warning_amber_rounded,
                                      size: 16,
                                      color: Colors.orange,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        service.lastError!,
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: Colors.orange,
                                              height: 1.35,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],

                    // Footer con botones gemelos
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: running
                                  ? null
                                  : () => Navigator.pop(sheetContext),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                side: BorderSide(
                                  color: running
                                      ? AppTheme.surfaceVariant.withValues(
                                          alpha: 0.5,
                                        )
                                      : AppTheme.surfaceVariant,
                                  width: 0.9,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: Text(running ? 'En curso…' : 'Cerrar'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: running
                                  ? service.cancel
                                  : () => Navigator.pop(sheetContext),
                              style: FilledButton.styleFrom(
                                backgroundColor: running
                                    ? Colors.red.shade600
                                    : _accentColor,
                                foregroundColor: Colors.white,
                                disabledBackgroundColor:
                                    AppTheme.surfaceVariant,
                                disabledForegroundColor: AppTheme.textSecondary,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              icon: Icon(
                                running
                                    ? Icons.stop_rounded
                                    : Icons.check_rounded,
                                size: 18,
                              ),
                              label: Text(running ? 'Detener' : 'Aceptar'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );

    // Espera a que el análisis termine de verdad antes de salir.
    await future;
  }

  // ===========================================================================
  // DIÁLOGO: REANALIZAR TODA LA BIBLIOTECA
  // ===========================================================================

  Future<void> _confirmReanalyze() async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);

        return _buildSheetContainer(
          context: sheetContext,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildSheetHandle(),
              const SizedBox(height: 18),

              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: AppTheme.surfaceVariant,
                              width: 0.7,
                            ),
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                _accentColor,
                                Color.lerp(_accentColor, Colors.black, 0.55)!,
                              ],
                            ),
                          ),
                          child: Icon(
                            Icons.refresh_rounded,
                            color: Colors.white.withValues(alpha: 0.95),
                            size: 34,
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
                              color: _accentColor,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppTheme.surface,
                                width: 3,
                              ),
                            ),
                            child: const Icon(
                              Icons.auto_fix_high_rounded,
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
                            'Reanalizar biblioteca',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Se recalcularán todas las ganancias.',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Puede tardar bastante según el tamaño de tu biblioteca.',
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
                      onPressed: () => Navigator.pop(sheetContext, false),
                      icon: const Icon(Icons.close_rounded),
                      tooltip: 'Cerrar',
                      visualDensity: VisualDensity.compact,
                      color: AppTheme.textSecondary,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Aviso informativo
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _accentColor.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _accentColor.withValues(alpha: 0.30),
                      width: 0.7,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 18,
                        color: _accentColor,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Las ganancias actuales se sobrescribirán con los '
                          'nuevos valores calculados.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppTheme.textSecondary,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Footer con botones gemelos
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(sheetContext, false),
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
                        onPressed: () => Navigator.pop(sheetContext, true),
                        style: FilledButton.styleFrom(
                          backgroundColor: _accentColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('Reanalizar'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );

    if (confirmed == true) {
      await ReplayGainService.instance.analyzeLibrary(force: true);
    }
  }

  // ===========================================================================
  // DIÁLOGO: BORRAR GANANCIAS CALCULADAS
  // ===========================================================================

  Future<void> _confirmClearReplayGain() async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);

        return _buildSheetContainer(
          context: sheetContext,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildSheetHandle(),
              const SizedBox(height: 18),

              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: AppTheme.surfaceVariant,
                              width: 0.7,
                            ),
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Colors.red.shade600,
                                Color.lerp(
                                  Colors.red.shade600,
                                  Colors.black,
                                  0.55,
                                )!,
                              ],
                            ),
                          ),
                          child: Icon(
                            Icons.delete_outline_rounded,
                            color: Colors.white.withValues(alpha: 0.95),
                            size: 34,
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
                              color: Colors.red.shade600,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppTheme.surface,
                                width: 3,
                              ),
                            ),
                            child: const Icon(
                              Icons.warning_amber_rounded,
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
                            'Borrar ganancias',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Se eliminarán todas las ganancias calculadas.',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Las pistas volverán a sonar sin normalización.',
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
                      onPressed: () => Navigator.pop(sheetContext, false),
                      icon: const Icon(Icons.close_rounded),
                      tooltip: 'Cerrar',
                      visualDensity: VisualDensity.compact,
                      color: AppTheme.textSecondary,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Aviso de advertencia (rojo)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.red.withValues(alpha: 0.30),
                      width: 0.7,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 18,
                        color: Colors.red.shade600,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Esta acción no se puede deshacer. Deberás analizar '
                          'de nuevo cada pista para recuperar la normalización.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppTheme.textSecondary,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Footer con botones gemelos
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(sheetContext, false),
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
                        onPressed: () => Navigator.pop(sheetContext, true),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.red.shade600,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 18,
                        ),
                        label: const Text('Borrar'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );

    if (confirmed == true) {
      await ReplayGainService.instance.clearAll();
    }
  }

  Widget _buildLibraryCard(_LayoutSize layout) {
    return _buildCard(
      children: [
        _SettingSwitchTile(
          icon: Icons.account_tree_outlined,
          title: 'Incluir subdirectorios',
          subtitle: 'Buscar música también dentro de las subcarpetas.',
          value: _scanSubdirectories,
          accent: _accentColor,
          onChanged: (value) {
            _updateSetting(() {
              _scanSubdirectories = value;
            });
          },
        ),
        _buildDivider(),
        _buildDirectorySection(
          title: 'Directorios de música',
          subtitle:
              'Carpetas que se incluirán al escanear la biblioteca musical.',
          icon: Icons.library_music_outlined,
          directories: _scanDirectories,
          podcasts: false,
          layout: layout,
        ),
        _buildDivider(),
        _buildDirectorySection(
          title: 'Directorios de podcasts',
          subtitle:
              'Carpetas independientes para almacenar y localizar podcasts.',
          icon: Icons.podcasts_rounded,
          directories: _podcastDirectories,
          podcasts: true,
          layout: layout,
        ),
      ],
    );
  }

  Widget _buildDirectorySection({
    required String title,
    required String subtitle,
    required IconData icon,
    required List<String> directories,
    required bool podcasts,
    required _LayoutSize layout,
  }) {
    final isCompact = layout == _LayoutSize.compact;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            isCompact ? 14 : 18,
            isCompact ? 14 : 18,
            isCompact ? 8 : 12,
            isCompact ? 10 : 14,
          ),
          child: Row(
            children: [
              Expanded(
                child: _SettingHeading(
                  icon: icon,
                  title: title,
                  subtitle: subtitle,
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                onPressed: () => _addDirectory(podcasts: podcasts),
                tooltip: podcasts
                    ? 'Agregar directorio de podcasts'
                    : 'Agregar directorio de música',
                icon: const Icon(Icons.add_rounded),
                style: IconButton.styleFrom(foregroundColor: _accentColor),
              ),
            ],
          ),
        ),
        if (directories.isNotEmpty) ...[
          for (int i = 0; i < directories.length; i++) ...[
            if (i > 0) _buildDivider(),
            ListTile(
              contentPadding: EdgeInsets.symmetric(
                horizontal: isCompact ? 14 : 18,
                vertical: 4,
              ),
              leading: Icon(Icons.folder_rounded, color: _accentColor),
              title: Text(
                directories[i],
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: IconButton(
                tooltip: 'Eliminar directorio',
                onPressed: () =>
                    _removeDirectory(directories[i], podcasts: podcasts),
                icon: const Icon(Icons.close_rounded),
              ),
            ),
          ],
        ] else
          Padding(
            padding: EdgeInsets.fromLTRB(
              isCompact ? 16 : 24,
              8,
              isCompact ? 16 : 24,
              isCompact ? 16 : 24,
            ),
            child: Center(
              child: Column(
                children: [
                  Icon(
                    Icons.folder_off_outlined,
                    size: isCompact ? 26 : 30,
                    color: AppTheme.textSecondary,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    podcasts
                        ? 'No hay directorios de podcasts'
                        : 'No hay directorios de música',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    podcasts
                        ? 'Agrega una carpeta para configurar tus podcasts.'
                        : 'Agrega una carpeta para configurar tu biblioteca musical.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildAboutCard() {
    return _buildCard(
      children: [
        const ListTile(
          contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: 6),
          leading: Icon(Icons.music_note_rounded),
          title: Text('DecibeX'),
          subtitle: Text('Reproductor de música'),
        ),
        _buildDivider(),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 6,
          ),
          leading: const Icon(Icons.save_outlined),
          title: const Text('Archivo de configuración'),
          subtitle: Text(
            _storagePath ?? 'Ruta pendiente de determinar',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (_storageError != null) ...[
          _buildDivider(),
          ListTile(
            leading: const Icon(
              Icons.warning_amber_rounded,
              color: Colors.orange,
            ),
            title: const Text('Error de almacenamiento'),
            subtitle: Text(
              _storageError!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
        _buildDivider(),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 6,
          ),
          leading: Icon(
            _isSaving ? Icons.sync_rounded : Icons.check_circle_outline,
            color: _isSaving ? _accentColor : AppTheme.textSecondary,
          ),
          title: Text(_isSaving ? 'Guardando ajustes...' : 'Guardado local'),
          subtitle: const Text(
            'Las preferencias se almacenan en un archivo .decibex.',
          ),
        ),
      ],
    );
  }

  Widget _buildDivider() {
    return Divider(height: 1, thickness: 0.7, color: AppTheme.surfaceVariant);
  }
}

class _AccentOption {
  final String name;
  final Color color;

  const _AccentOption(this.name, this.color);
}

class _SettingHeading extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _SettingHeading({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 21, color: AppTheme.textSecondary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppTheme.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SettingSwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final Color accent;
  final ValueChanged<bool> onChanged;

  const _SettingSwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.accent,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      activeThumbColor: accent,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 5),
      secondary: Icon(icon, color: value ? accent : AppTheme.textSecondary),
      title: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppTheme.textSecondary,
            height: 1.4,
          ),
        ),
      ),
    );
  }
}

class _SettingSlider extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String valueLabel;
  final Color accent;
  final bool enabled;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  const _SettingSlider({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.valueLabel,
    required this.accent,
    required this.enabled,
    required this.onChanged,
    required this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Opacity(
      opacity: enabled ? 1 : 0.48,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                size: 21,
                color: enabled ? accent : AppTheme.textSecondary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppTheme.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                valueLabel,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: enabled ? accent : AppTheme.textSecondary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: accent,
              thumbColor: accent,
              overlayColor: accent.withValues(alpha: 0.12),
              inactiveTrackColor: AppTheme.surfaceVariant,
              trackHeight: 4,
            ),
            child: Slider(
              value: value.clamp(min, max).toDouble(),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: enabled ? onChanged : null,
              onChangeEnd: enabled ? onChangeEnd : null,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  min == -12 ? '-12 dB' : '0 s',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
                Text(
                  max == 12 ? '+12 dB' : '10 s',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
