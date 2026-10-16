import 'package:flutter/material.dart';

import '../app_theme.dart';

class SearchScreen extends StatelessWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Buscar música',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 24),
          const TextField(
            decoration: InputDecoration(
              hintText: 'Canciones, artistas o álbumes',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Busca tu próxima canción favorita.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
