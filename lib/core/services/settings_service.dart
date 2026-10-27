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
/// - Los setters de efectos (slow / reverb) persisten solos con debounce.
class SettingsService extends ChangeNotifier {
  SettingsService._();

  static final SettingsService instance = SettingsService._();

  static const String _settingsFileName = 'settings.decibex';

  Directory? _directory;
  StreamSubscription<FileSystemEvent>? _watcher;
  Timer? _debounce;
  Timer? _saveDebounce;
  bool _initialized = false;
  bool _disposed = false;

  /// Último contenido escrito por nosotros. Sirve para ignorar el evento del
  /// watcher que provoca nuestra propia escritura (evita que un slider
  /// "salte" hacia atrás con un valor antiguo).
  String? _lastWrittenContent;

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

  // --- Slowed + Reverb ---
  bool slowEnabled = false;

  /// 0.0 = velocidad normal, 1.0 = máxima ralentización.
  double slowAmount = 0.4;

  bool reverbEnabled = false;

  /// 0.0 = sin reverb, 1.0 = máxima intensidad.
  double reverbAmount = 0.4;

  bool scanSubdirectories = true;
  List<String> scanDirectories = [];
  List<String> podcastDirectories = [];

  bool artistsGridMode = false;
  bool albumsGridMode = false;

  /// Con `slowAmount = 1.0` la pista suena a `1 - maxSlowdown` (0.65x).
  static const double maxSlowdown = 0.35;

  /// Velocidad resultante para un nivel de slider [amount] (0..1).
  static double speedForAmount(double amount) {
    final a = amount.clamp(0.0, 1.0).toDouble();
    return 1.0 - a * maxSlowdown;
  }

  /// Velocidad realmente aplicada (1.0 si slow está desactivado).
  double get effectiveSpeed => slowEnabled ? speedForAmount(slowAmount) : 1.0;

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

    // Hay cambios en memoria pendientes de guardar: son más recientes que
    // lo que hay en disco, no los pisamos.
    if (_saveDebounce?.isActive ?? false) return;

    try {
      final file = await _settingsFile();
      if (!await file.exists()) {
        await save();
        return;
      }

      final content = await file.readAsString();
      if (content.trim().isEmpty) return;

      // Es el eco de nuestra propia escritura.
      if (content == _lastWrittenContent) return;

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

    // --- Slowed + Reverb ---
    set(
      slowEnabled,
      readBool('slowEnabled', slowEnabled),
      (v) => slowEnabled = v,
    );
    set(
      slowAmount,
      readDouble('slowAmount', slowAmount, 0, 1),
      (v) => slowAmount = v,
    );
    set(
      reverbEnabled,
      readBool('reverbEnabled', reverbEnabled),
      (v) => reverbEnabled = v,
    );
    set(
      reverbAmount,
      readDouble('reverbAmount', reverbAmount, 0, 1),
      (v) => reverbAmount = v,
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
  // Setters inmediatos (para PlaybackService / idioma / efectos)
  // ------------------------------------------------------------------

  /// Cambia el preamp global y notifica de inmediato a los listeners.
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

  /// Cambia el idioma y notifica de inmediato para que `MaterialApp`
  /// reconstruya con el nuevo `Locale` sin esperar al disco.
  void setLanguage(AppLanguage value) {
    if (language == value) return;
    language = value;
    _notifyIfAlive();
  }

  /// Activa/desactiva el efecto "slowed". Persiste automáticamente.
  void setSlowEnabled(bool value) {
    if (slowEnabled == value) return;
    slowEnabled = value;
    _notifyIfAlive();
    _scheduleSave();
  }

  /// Potencia del efecto "slowed" (0..1). Persiste automáticamente.
  void setSlowAmount(double value) {
    final clamped = value.clamp(0.0, 1.0).toDouble();
    if (slowAmount == clamped) return;
    slowAmount = clamped;
    _notifyIfAlive();
    _scheduleSave();
  }

  /// Activa/desactiva el reverb. Persiste automáticamente.
  void setReverbEnabled(bool value) {
    if (reverbEnabled == value) return;
    reverbEnabled = value;
    _notifyIfAlive();
    _scheduleSave();
  }

  /// Potencia del reverb (0..1). Persiste automáticamente.
  void setReverbAmount(double value) {
    final clamped = value.clamp(0.0, 1.0).toDouble();
    if (reverbAmount == clamped) return;
    reverbAmount = clamped;
    _notifyIfAlive();
    _scheduleSave();
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
      'slowEnabled': slowEnabled,
      'slowAmount': slowAmount,
      'reverbEnabled': reverbEnabled,
      'reverbAmount': reverbAmount,
      'scanSubdirectories': scanSubdirectories,
      'scanDirectories': scanDirectories,
      'podcastDirectories': podcastDirectories,
      'artistsGridMode': artistsGridMode,
      'albumsGridMode': albumsGridMode,
    };
  }

  void _scheduleSave() {
    if (_disposed) return;
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 400), () {
      _saveDebounce = null;
      unawaited(save());
    });
  }

  /// Escribe los valores actuales en disco.
  Future<void> save() async {
    if (_disposed) return;

    _saveDebounce?.cancel();
    _saveDebounce = null;

    try {
      final file = await _settingsFile();
      final json = const JsonEncoder.withIndent('  ').convert(serialize());
      _lastWrittenContent = json;
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
    _saveDebounce?.cancel();
    _watcher?.cancel();
    super.dispose();
  }
}
