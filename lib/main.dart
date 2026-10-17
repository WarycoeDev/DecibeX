import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

import 'app_shell.dart';
import 'ui/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  JustAudioMediaKit.ensureInitialized();
  runApp(const DecibeXApp());
}

class DecibeXApp extends StatefulWidget {
  const DecibeXApp({super.key});

  @override
  State<DecibeXApp> createState() => _DecibeXAppState();
}

class _DecibeXAppState extends State<DecibeXApp> with WidgetsBindingObserver {
  bool _permissionRequested = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestStoragePermission();
    });
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
