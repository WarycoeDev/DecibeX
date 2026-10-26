import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:universal_youtube_player/universal_youtube_player.dart';

import 'app_shell.dart';
import 'ui/app_theme.dart';
import 'core/services/library_scanner.dart';
import 'core/services/settings_service.dart';
import 'core/services/statistics_service.dart';
import 'core/services/podcast_statistics_service.dart';
import 'core/services/audio_handler.dart';

/// Plugin para notificaciones locales.
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

/// Inicializa las notificaciones locales de Android.
Future<void> _initializeLocalNotifications() async {
  const androidSettings = AndroidInitializationSettings(
    'ic_stat_notification_icon',
  );

  const initializationSettings = InitializationSettings(
    android: androidSettings,
  );

  await flutterLocalNotificationsPlugin.initialize(
    settings: initializationSettings,
  );
}

Future<void> main() async {
  runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      UniversalYoutubePlayerBootstrap.ensureInitialized();
      JustAudioMediaKit.ensureInitialized();

      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        debugPrint('[FlutterError] ${details.exceptionAsString()}');
        debugPrint('${details.stack}');
      };

      // Inicializa notificaciones locales sin impedir que la app arranque
      // si ocurre un problema con este servicio.
      if (Platform.isAndroid) {
        try {
          await _initializeLocalNotifications();
        } catch (e, st) {
          debugPrint('[main] Local notifications init error: $e\n$st');
        }

        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
        ]);
      }

      // Conserva el servicio de reproducción de audio existente.
      await AudioService.init(
        builder: DecibeXAudioHandler.new,
        config: AudioServiceConfig(
          androidNotificationChannelId: 'com.example.decibex.audio',
          androidNotificationChannelName: 'Reproducción de audio',
          androidNotificationChannelDescription:
              'Controles de reproducción de DecibeX',
          androidNotificationOngoing: true,
          androidStopForegroundOnPause: true,
          artDownscaleWidth: 512,
          artDownscaleHeight: 512,

          androidNotificationIcon: 'drawable/ic_stat_notification_icon',
        ),
      );

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

  bool? _appliedDarkTheme;
  int? _appliedAccentColor;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);
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

    try {
      await SettingsService.instance.initialize();
    } catch (e, st) {
      debugPrint('[main] SettingsService init error: $e\n$st');
    }

    try {
      _applyThemeFromSettings();
    } catch (e, st) {
      debugPrint('[main] AppTheme update error: $e\n$st');
    }

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
          builder: (context, widget) {
            return widget ?? const SizedBox.shrink();
          },
        );
      },
    );
  }
}
