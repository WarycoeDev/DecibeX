import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../l10n/app_localizations.dart';

/// Fuente única de verdad para settings.decibex.
///
/// - Lee el archivo una vez al arrancar.
/// - Reacciona a cambios con un watcher (por si el usuario edita a mano).
/// - Expone setters inmediatos para que `PlaybackService` reaccione sin
///   esperar al watcher (p. ej. al mover el slider de preamp).
class SettingsService extends ChangeNotifier {
  SettingsService._();

  static final SettingsService instance = SettingsService._();

  static const String _settingsFileName = 'settings.decibex';

  Directory? _directory;
  StreamSubscription<FileSystemEvent>? _watcher;
  Timer? _debounce;
  bool _initialized = false;
  bool _disposed = false;

  // --- Valores expuestos ---
  bool darkTheme = true;
  int accentColorValue = 0xFF6750A4;
  AppLanguage language = AppLanguage.system;

  bool replayGainEnabled = false;
  double replayGainPreamp = 0;

  bool fadeInEnabled = false;
  bool fadeOutEnabled = false;
  double fadeInDuration = 2;
  double fadeOutDuration = 2;

  bool scanSubdirectories = true;
  List<String> scanDirectories = [];
  List<String> podcastDirectories = [];

  bool artistsGridMode = false;
  bool albumsGridMode = false;

  /// Ruta del archivo de configuración (útil para mostrar en la UI).
  String? get storagePath =>
      _directory == null ? null : '${_directory!.path}/$_settingsFileName';

  void _notifyIfAlive() {
    if (!_disposed) notifyListeners();
  }

  Future<Directory> _resolveSettingsDirectory() async {
    if (Platform.isAndroid) {
      final external = await getExternalStorageDirectory();
      if (external != null) {
        return Directory('${external.path}/data');
      }
    }
    return getApplicationSupportDirectory();
  }

  Future<File> _settingsFile() async {
    _directory ??= await _resolveSettingsDirectory();
    final dir = _directory!;
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File('${dir.path}/$_settingsFileName');
  }

  /// Carga inicial + arranque del watcher. Idempotente.
  Future<void> initialize() async {
    if (_initialized || _disposed) return;
    _initialized = true;

    await reload();

    try {
      final dir = _directory!;
      _watcher = dir
          .watch(events: FileSystemEvent.all, recursive: false)
          .listen((_) => _scheduleReload(), onError: (_) => _scheduleReload());
    } catch (e) {
      debugPrint('[SettingsService] No se pudo observar settings.decibex: $e');
    }
  }

  void _scheduleReload() {
    if (_disposed) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      if (!_disposed) unawaited(reload());
    });
  }

  /// Vuelve a leer el archivo y emite cambios si algo cambió.
  Future<void> reload() async {
    if (_disposed) return;

    try {
      final file = await _settingsFile();
      if (!await file.exists()) {
        await save();
        return;
      }

      final content = await file.readAsString();
      if (content.trim().isEmpty) return;

      final decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) return;

      if (_apply(decoded)) {
        _notifyIfAlive();
      }
    } catch (e) {
      debugPrint('[SettingsService] Error leyendo settings: $e');
    }
  }

  bool _apply(Map<String, dynamic> json) {
    var changed = false;

    bool readBool(String key, bool fallback) {
      final v = json[key];
      return v is bool ? v : fallback;
    }

    double readDouble(String key, double fallback, double min, double max) {
      final v = json[key];
      final n = v is num ? v.toDouble() : fallback;
      return n.clamp(min, max).toDouble();
    }

    List<String> readDirs(String key) {
      final v = json[key];
      if (v is! List) return [];
      return v
          .whereType<String>()
          .map((p) => p.trim())
          .where((p) => p.isNotEmpty)
          .toList();
    }

    void set<T>(T current, T next, void Function(T) assign) {
      if (current != next) {
        assign(next);
        changed = true;
      }
    }

    set(darkTheme, readBool('darkTheme', darkTheme), (v) => darkTheme = v);

    final savedLanguage = AppLocalizations.languageFrom(
      json['language'] as String?,
    );
    set(language, savedLanguage, (v) => language = v);

    final accent = json['accentColor'];
    if (accent is int && accent != accentColorValue) {
      accentColorValue = accent;
      changed = true;
    }

    set(
      replayGainEnabled,
      readBool('replayGainEnabled', replayGainEnabled),
      (v) => replayGainEnabled = v,
    );

    set(
      replayGainPreamp,
      readDouble('replayGainPreamp', replayGainPreamp, -12, 12),
      (v) => replayGainPreamp = v,
    );

    set(
      fadeInEnabled,
      readBool('fadeInEnabled', fadeInEnabled),
      (v) => fadeInEnabled = v,
    );
    set(
      fadeOutEnabled,
      readBool('fadeOutEnabled', fadeOutEnabled),
      (v) => fadeOutEnabled = v,
    );
    set(
      fadeInDuration,
      readDouble('fadeInDuration', fadeInDuration, 0, 10),
      (v) => fadeInDuration = v,
    );
    set(
      fadeOutDuration,
      readDouble('fadeOutDuration', fadeOutDuration, 0, 10),
      (v) => fadeOutDuration = v,
    );

    set(
      scanSubdirectories,
      readBool('scanSubdirectories', scanSubdirectories),
      (v) => scanSubdirectories = v,
    );

    final dirs = readDirs('scanDirectories');
    if (!_sameDirs(scanDirectories, dirs)) {
      scanDirectories = dirs;
      changed = true;
    }

    final podcasts = readDirs('podcastDirectories');
    if (!_sameDirs(podcastDirectories, podcasts)) {
      podcastDirectories = podcasts;
      changed = true;
    }

    set(
      artistsGridMode,
      readBool('artistsGridMode', artistsGridMode),
      (v) => artistsGridMode = v,
    );
    set(
      albumsGridMode,
      readBool('albumsGridMode', albumsGridMode),
      (v) => albumsGridMode = v,
    );

    return changed;
  }

  bool _sameDirs(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    final setA = a.toSet();
    final setB = b.toSet();
    return setA.length == setB.length && setA.containsAll(setB);
  }

  // ------------------------------------------------------------------
  // Setters inmediatos (para PlaybackService / idioma)
  // ------------------------------------------------------------------

  /// Cambia el preamp global y notifica de inmediato a los listeners
  /// (PlaybackService lo leerá en la siguiente pista sin esperar al watcher).
  void setReplayGainPreamp(double value) {
    final clamped = value.clamp(-12.0, 12.0).toDouble();
    if (replayGainPreamp == clamped) return;
    replayGainPreamp = clamped;
    _notifyIfAlive();
  }

  /// Activa/desactiva ReplayGain globalmente y notifica de inmediato.
  void setReplayGainEnabled(bool value) {
    if (replayGainEnabled == value) return;
    replayGainEnabled = value;
    _notifyIfAlive();
  }

  /// [NUEVO] Cambia el idioma y notifica de inmediato para que
  /// `MaterialApp` reconstruya con el nuevo `Locale` sin esperar al disco.
  void setLanguage(AppLanguage value) {
    if (language == value) return;
    language = value;
    _notifyIfAlive();
  }

  // ------------------------------------------------------------------
  // Persistencia
  // ------------------------------------------------------------------

  /// Serializa los valores actuales. No escribe el archivo.
  Map<String, dynamic> serialize() {
    return {
      'version': 1,
      'darkTheme': darkTheme,
      'accentColor': accentColorValue,
      'language': language.name,
      'replayGainEnabled': replayGainEnabled,
      'replayGainPreamp': replayGainPreamp,
      'fadeInEnabled': fadeInEnabled,
      'fadeOutEnabled': fadeOutEnabled,
      'fadeInDuration': fadeInDuration,
      'fadeOutDuration': fadeOutDuration,
      'scanSubdirectories': scanSubdirectories,
      'scanDirectories': scanDirectories,
      'podcastDirectories': podcastDirectories,
      'artistsGridMode': artistsGridMode,
      'albumsGridMode': albumsGridMode,
    };
  }

  /// Escribe los valores actuales en disco.
  Future<void> save() async {
    if (_disposed) return;
    try {
      final file = await _settingsFile();
      final json = const JsonEncoder.withIndent('  ').convert(serialize());
      await file.writeAsString(json, flush: true);
      _notifyIfAlive();
    } catch (e) {
      debugPrint('[SettingsService] Error guardando settings: $e');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    _watcher?.cancel();
    super.dispose();
  }
}
