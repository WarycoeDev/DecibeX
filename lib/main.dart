import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:permission_handler/permission_handler.dart';

import 'app_shell.dart';
import 'ui/app_theme.dart';
import 'core/services/library_scanner.dart';
import 'core/services/settings_service.dart';
import 'core/services/statistics_service.dart';
import 'core/services/podcast_statistics_service.dart';
import 'package:universal_youtube_player/universal_youtube_player.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

Future<void> main() async {
  UniversalYoutubePlayerBootstrap.ensureInitialized();
  JustAudioMediaKit.ensureInitialized();
  // Captura errores de la zona raíz para ver el stack trace real en consola.
  runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        debugPrint('[FlutterError] ${details.exceptionAsString()}');
        debugPrint('${details.stack}');
      };

      JustAudioMediaKit.ensureInitialized();

      if (Platform.isAndroid) {
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
        ]);
      }

      runApp(const DecibeXApp());
    },
    (error, stack) {
      debugPrint('[Zona raíz] Error no capturado: $error');
      debugPrint('$stack');
    },
  );
}

class DecibeXApp extends StatefulWidget {
  const DecibeXApp({super.key});

  @override
  State<DecibeXApp> createState() => _DecibeXAppState();
}

class _DecibeXAppState extends State<DecibeXApp> with WidgetsBindingObserver {
  bool _permissionRequested = false;
  bool _servicesInitialized = false;

  // Últimos valores aplicados a AppTheme, para no reaplicar en cada build.
  bool? _appliedDarkTheme;
  int? _appliedAccentColor;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Sincroniza AppTheme cuando SettingsService cambie (una sola vez por
    // cambio real), NO dentro de build(). Esto evita el bucle
    // notifyListeners → rebuild → updateAppearance → notifyListeners.
    SettingsService.instance.addListener(_onSettingsChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initServices();
      _requestStoragePermission();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SettingsService.instance.removeListener(_onSettingsChanged);
    super.dispose();
  }

  /// Aplica el tema a AppTheme solo si cambió respecto al último aplicado.
  void _applyThemeFromSettings() {
    final s = SettingsService.instance;
    final accent = s.accentColorValue;

    if (_appliedDarkTheme == s.darkTheme && _appliedAccentColor == accent) {
      return;
    }

    _appliedDarkTheme = s.darkTheme;
    _appliedAccentColor = accent;

    AppTheme.updateAppearance(
      darkTheme: s.darkTheme,
      accentColor: Color(accent),
    );
  }

  void _onSettingsChanged() {
    if (!mounted) return;
    _applyThemeFromSettings();
  }

  Future<void> _initServices() async {
    if (_servicesInitialized) return;
    _servicesInitialized = true;

    // 1) Settings. Si falla, seguimos con defaults.
    try {
      await SettingsService.instance.initialize();
    } catch (e, st) {
      debugPrint('[main] SettingsService init error: $e\n$st');
    }

    // Aplicar el tema cargado (o defaults si falló).
    try {
      _applyThemeFromSettings();
    } catch (e, st) {
      debugPrint('[main] AppTheme update error: $e\n$st');
    }

    // 2) Estadísticas.
    try {
      await StatisticsService.instance.init();
    } catch (e, st) {
      debugPrint('[main] StatisticsService init error: $e\n$st');
    }

    try {
      await PodcastStatisticsService.instance.init();
    } catch (e, st) {
      debugPrint('[main] PodcastStatisticsService init error: $e\n$st');
    }

    // 3) Biblioteca. Si falla (p. ej. permisos aún no concedidos), se
    // reintenta al volver del lifecycle "resumed".
    try {
      await LibraryScanner.instance.initialize();
    } catch (e, st) {
      debugPrint('[main] LibraryScanner init error: $e\n$st');
    }
  }

  Future<void> _requestStoragePermission() async {
    if (!Platform.isAndroid || _permissionRequested) return;

    _permissionRequested = true;

    try {
      final status = await Permission.manageExternalStorage.status;

      if (!status.isGranted) {
        final result = await Permission.manageExternalStorage.request();

        // Si el usuario acaba de conceder el permiso, reintentar la
        // inicialización del escáner (antes falló por no poder leer).
        if (result.isGranted && !_scannerInitialized()) {
          try {
            await LibraryScanner.instance.initialize();
          } catch (e, st) {
            debugPrint('[main] Reintento LibraryScanner error: $e\n$st');
          }
        }
      }
    } catch (e) {
      debugPrint('[main] Permiso error: $e');
      _permissionRequested = false;
    }
  }

  /// Heurística: si lastScan es null, aún no terminó la inicialización.
  bool _scannerInitialized() => LibraryScanner.instance.lastScan != null;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (Platform.isAndroid && state == AppLifecycleState.resumed) {
      _checkStoragePermission();
    }

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(PodcastStatisticsService.instance.flush());
    }
  }

  Future<void> _checkStoragePermission() async {
    try {
      final status = await Permission.manageExternalStorage.status;

      if (!status.isGranted && mounted) {
        _permissionRequested = false;
      } else if (status.isGranted && !_scannerInitialized()) {
        try {
          await LibraryScanner.instance.initialize();
        } catch (e, st) {
          debugPrint('[main] Reinit LibraryScanner error: $e\n$st');
        }
      }
    } catch (_) {
      if (mounted) _permissionRequested = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppTheme.notifier,
      builder: (context, child) {
        return MaterialApp(
          title: 'DecibeX',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.current,
          home: const AppShell(),
          // Evita el flash rojo si un widget lanza excepción en el primer
          // frame y muestra la app igualmente. Hombre soy bien barbaro jeje
          builder: (context, widget) {
            return widget ?? const SizedBox.shrink();
          },
        );
      },
    );
  }
}
