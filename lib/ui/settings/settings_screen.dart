import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../app_theme.dart';

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

  bool _artistsGridMode = false;
  bool _albumsGridMode = false;

  Color get _accentColor => Color(_accentColorValue);

  @override
  void initState() {
    super.initState();
    _loadSettings();
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
      final file = await _getSettingsFile();
      _storagePath = file.path;

      if (await file.exists()) {
        final content = await file.readAsString();

        if (content.trim().isNotEmpty) {
          final decoded = jsonDecode(content);

          if (decoded is Map<String, dynamic>) {
            _applySettings(decoded);
          }
        }
      }
    } catch (error) {
      _storageError = error.toString();
    }

    AppTheme.updateAppearance(darkTheme: _darkTheme, accentColor: _accentColor);

    if (!mounted) return;

    setState(() {
      _isLoading = false;
    });
  }

  void _applySettings(Map<String, dynamic> json) {
    _darkTheme = json['darkTheme'] is bool
        ? json['darkTheme'] as bool
        : _darkTheme;

    _accentColorValue = json['accentColor'] is int
        ? json['accentColor'] as int
        : _accentColorValue;

    _replayGainEnabled = json['replayGainEnabled'] is bool
        ? json['replayGainEnabled'] as bool
        : _replayGainEnabled;

    _replayGainPreamp = _readDouble(
      json['replayGainPreamp'],
      _replayGainPreamp,
      -12,
      12,
    );

    _fadeInEnabled = json['fadeInEnabled'] is bool
        ? json['fadeInEnabled'] as bool
        : _fadeInEnabled;

    _fadeOutEnabled = json['fadeOutEnabled'] is bool
        ? json['fadeOutEnabled'] as bool
        : _fadeOutEnabled;

    _fadeInDuration = _readDouble(
      json['fadeInDuration'],
      _fadeInDuration,
      0,
      10,
    );

    _fadeOutDuration = _readDouble(
      json['fadeOutDuration'],
      _fadeOutDuration,
      0,
      10,
    );

    _scanSubdirectories = json['scanSubdirectories'] is bool
        ? json['scanSubdirectories'] as bool
        : _scanSubdirectories;

    _artistsGridMode = json['artistsGridMode'] is bool
        ? json['artistsGridMode'] as bool
        : false;

    _albumsGridMode = json['albumsGridMode'] is bool
        ? json['albumsGridMode'] as bool
        : false;

    final directories = json['scanDirectories'];

    if (directories is List) {
      _scanDirectories = directories.whereType<String>().toSet().toList();
    }
  }

  double _readDouble(
    dynamic value,
    double fallback,
    double minimum,
    double maximum,
  ) {
    final number = value is num ? value.toDouble() : fallback;
    return number.clamp(minimum, maximum).toDouble();
  }

  Map<String, dynamic> _serializeSettings() {
    return {
      'version': 1,
      'darkTheme': _darkTheme,
      'accentColor': _accentColorValue,
      'replayGainEnabled': _replayGainEnabled,
      'replayGainPreamp': _replayGainPreamp,
      'fadeInEnabled': _fadeInEnabled,
      'fadeOutEnabled': _fadeOutEnabled,
      'fadeInDuration': _fadeInDuration,
      'fadeOutDuration': _fadeOutDuration,
      'scanSubdirectories': _scanSubdirectories,
      'scanDirectories': _scanDirectories,
      'artistsGridMode': _artistsGridMode,
      'albumsGridMode': _albumsGridMode,
    };
  }

  Future<void> _saveSettings({bool showError = true}) async {
    if (_isSaving) {
      _saveAgain = true;
      return;
    }

    _isSaving = true;

    try {
      do {
        _saveAgain = false;

        final file = await _getSettingsFile();
        final json = const JsonEncoder.withIndent(
          '  ',
        ).convert(_serializeSettings());

        await file.writeAsString(json, flush: true);

        _storagePath = file.path;
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

  Future<void> _addDirectory() async {
    try {
      final selectedDirectory = await FilePicker.getDirectoryPath(
        dialogTitle: 'Seleccionar directorio de música',
      );

      if (selectedDirectory == null || !mounted) return;

      if (_scanDirectories.contains(selectedDirectory)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Este directorio ya está agregado.')),
        );
        return;
      }

      setState(() {
        _scanDirectories.add(selectedDirectory);
      });

      await _saveSettings();
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo seleccionar el directorio: $error')),
      );
    }
  }

  Future<void> _removeDirectory(String directory) async {
    setState(() {
      _scanDirectories.remove(directory);
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
          'Los directorios agregados también se eliminarán de la lista.',
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

      _artistsGridMode = false;
      _albumsGridMode = false;
    });

    AppTheme.updateAppearance(darkTheme: _darkTheme, accentColor: _accentColor);

    await _saveSettings();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDesktop = MediaQuery.sizeOf(context).width >= 800;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalPadding = constraints.maxWidth >= 800 ? 36.0 : 20.0;

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            isDesktop ? 32 : 24,
            horizontalPadding,
            36,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(theme, isDesktop),
                  const SizedBox(height: 30),
                  _buildSectionTitle(
                    icon: Icons.palette_outlined,
                    title: 'Apariencia',
                    subtitle: 'Personaliza el aspecto de DecibeX.',
                  ),
                  const SizedBox(height: 14),
                  _buildAppearanceCard(),
                  const SizedBox(height: 30),
                  _buildSectionTitle(
                    icon: Icons.graphic_eq_rounded,
                    title: 'Audio',
                    subtitle: 'Preferencias de reproducción y sonido.',
                  ),
                  const SizedBox(height: 14),
                  _buildAudioCard(),
                  const SizedBox(height: 30),
                  _buildSectionTitle(
                    icon: Icons.folder_open_rounded,
                    title: 'Biblioteca',
                    subtitle: 'Configura las carpetas que se analizarán.',
                  ),
                  const SizedBox(height: 14),
                  _buildLibraryCard(),
                  const SizedBox(height: 30),
                  _buildSectionTitle(
                    icon: Icons.info_outline_rounded,
                    title: 'Acerca de DecibeX',
                    subtitle: 'Información y estado de la configuración.',
                  ),
                  const SizedBox(height: 14),
                  _buildAboutCard(),
                  const SizedBox(height: 24),
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
        );
      },
    );
  }

  Widget _buildHeader(ThemeData theme, bool isDesktop) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'PERSONALIZACIÓN',
          style: theme.textTheme.labelMedium?.copyWith(
            color: _accentColor,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.6,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Configuración',
          style:
              (isDesktop
                      ? theme.textTheme.headlineLarge
                      : theme.textTheme.headlineSmall)
                  ?.copyWith(fontWeight: FontWeight.bold, letterSpacing: -0.8),
        ),
        const SizedBox(height: 8),
        Text(
          'Ajusta tu experiencia de escucha a tu manera.',
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
  }) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: _accentColor.withValues(alpha: 0.13),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, color: _accentColor, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
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

  Widget _buildAppearanceCard() {
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
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SettingHeading(
                icon: Icons.color_lens_outlined,
                title: 'Color de acento',
                subtitle: 'Selecciona el color principal de la interfaz.',
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 12,
                runSpacing: 12,
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
                          width: 38,
                          height: 38,
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
                                ? const Icon(
                                    Icons.check_rounded,
                                    size: 18,
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
          },
        ),
        _buildDivider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
          child: _SettingSlider(
            icon: Icons.volume_up_rounded,
            title: 'ReplayGain preamp',
            subtitle: 'Ajuste adicional de ganancia.',
            value: _replayGainPreamp,
            min: -12,
            max: 12,
            divisions: 48,
            accent: _accentColor,
            valueLabel: '${_replayGainPreamp.toStringAsFixed(1)} dB',
            enabled: _replayGainEnabled,
            onChanged: (value) {
              setState(() {
                _replayGainPreamp = value;
              });
            },
            onChangeEnd: (_) => _saveSettings(),
          ),
        ),
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

  Widget _buildLibraryCard() {
    return _buildCard(
      children: [
        Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              const Expanded(
                child: _SettingHeading(
                  icon: Icons.create_new_folder_outlined,
                  title: 'Directorios de música',
                  subtitle: 'Carpetas que se incluirán al escanear.',
                ),
              ),
              const SizedBox(width: 12),
              IconButton.filledTonal(
                onPressed: _addDirectory,
                tooltip: 'Agregar directorio',
                icon: const Icon(Icons.add_rounded),
                style: IconButton.styleFrom(foregroundColor: _accentColor),
              ),
            ],
          ),
        ),
        _buildDivider(),
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
        if (_scanDirectories.isNotEmpty) ...[
          _buildDivider(),
          for (int i = 0; i < _scanDirectories.length; i++) ...[
            if (i > 0) _buildDivider(),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 4,
              ),
              leading: Icon(Icons.folder_rounded, color: _accentColor),
              title: Text(
                _scanDirectories[i],
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: IconButton(
                tooltip: 'Eliminar directorio',
                onPressed: () => _removeDirectory(_scanDirectories[i]),
                icon: const Icon(Icons.close_rounded),
              ),
            ),
          ],
        ] else ...[
          _buildDivider(),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Column(
                children: [
                  Icon(
                    Icons.folder_off_outlined,
                    size: 30,
                    color: AppTheme.textSecondary,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'No hay directorios agregados',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Agrega una carpeta para configurar tu biblioteca.',
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
