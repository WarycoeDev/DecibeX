import 'package:flutter/material.dart';

import '../app_theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Configuración',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 24),
        Card(
          color: AppTheme.surface,
          child: const Column(
            children: [
              ListTile(
                leading: Icon(Icons.palette_outlined),
                title: Text('Apariencia'),
                subtitle: Text('Personalización visual'),
                trailing: Icon(Icons.chevron_right_rounded),
              ),
              Divider(height: 1),
              ListTile(
                leading: Icon(Icons.audio_file_outlined),
                title: Text('Audio'),
                subtitle: Text('Preferencias de sonido'),
                trailing: Icon(Icons.chevron_right_rounded),
              ),
              Divider(height: 1),
              ListTile(
                leading: Icon(Icons.info_outline_rounded),
                title: Text('Acerca de DecibeX'),
                subtitle: Text('Información de la aplicación'),
                trailing: Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'DecibeX',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppTheme.textSecondary,
          ),
        ),
      ],
    );
  }
}
