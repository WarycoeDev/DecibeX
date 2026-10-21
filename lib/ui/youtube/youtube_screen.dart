import 'package:flutter/material.dart';

import '../app_theme.dart';

class YouTubeScreen extends StatelessWidget {
  const YouTubeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Pantalla de YouTube',
        style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: AppTheme.accent,
        ),
      ),
    );
  }
}
