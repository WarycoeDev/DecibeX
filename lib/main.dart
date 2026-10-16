import 'package:flutter/material.dart';

import 'app_shell.dart';
import 'ui/app_theme.dart';

void main() {
  runApp(const DecibeXApp());
}

class DecibeXApp extends StatelessWidget {
  const DecibeXApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DecibeX',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const AppShell(),
    );
  }
}
