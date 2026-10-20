import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:permission_handler/permission_handler.dart';

import 'app_shell.dart';
import 'ui/app_theme.dart';
import 'core/services/statistics_service.dart';
import 'core/services/podcast_statistics_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  JustAudioMediaKit.ensureInitialized();

  if (Platform.isAndroid) {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }

  runApp(const DecibeXApp());
}

class DecibeXApp extends StatefulWidget {
  const DecibeXApp({super.key});

  @override
  State<DecibeXApp> createState() => _DecibeXAppState();
}

class _DecibeXAppState extends State<DecibeXApp> with WidgetsBindingObserver {
  bool _permissionRequested = false;
  bool _servicesInitialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Inicializar servicios y permisos después del primer frame para no
      // bloquear el arranque de la app (causa típica de "se queda instalando").
      _initServices();
      _requestStoragePermission();
    });
  }

  Future<void> _initServices() async {
    if (_servicesInitialized) return;
    _servicesInitialized = true;

    try {
      await StatisticsService.instance.init();
    } catch (e) {
      debugPrint('[main] StatisticsService init error: $e');
    }

    try {
      await PodcastStatisticsService.instance.init();
    } catch (e) {
      debugPrint('[main] PodcastStatisticsService init error: $e');
    }
  }

  Future<void> _requestStoragePermission() async {
    if (!Platform.isAndroid || _permissionRequested) return;

    _permissionRequested = true;

    try {
      final status = await Permission.manageExternalStorage.status;

      if (!status.isGranted) {
        await Permission.manageExternalStorage.request();
      }
    } catch (_) {
      _permissionRequested = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (Platform.isAndroid && state == AppLifecycleState.resumed) {
      _checkStoragePermission();
    }

    // Guardar la posición del episodio al minimizar o cerrar.
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
      }
    } catch (_) {
      if (mounted) {
        _permissionRequested = false;
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
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
        );
      },
    );
  }
}
