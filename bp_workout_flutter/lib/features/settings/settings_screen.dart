import 'package:flutter/material.dart';

import '../../core/config/env.dart';
import '../../theme/blueprint_colors.dart';

/// Placeholder — port `SettingsView` + Supabase session.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final api = Env.blueprintApiUrl;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            title: const Text('Blueprint API'),
            subtitle: Text(
              Env.isApiConfigured ? api : 'Not set — use --dart-define=BLUEPRINT_API_URL=…',
              style: TextStyle(
                color: Env.isApiConfigured
                    ? BlueprintColors.mutedLight
                    : BlueprintColors.amber,
              ),
            ),
          ),
          const ListTile(
            title: Text('Supabase auth'),
            subtitle: Text(
              'Next: port Supabase email/password flow from the Swift app.',
              style: TextStyle(color: BlueprintColors.mutedLight),
            ),
          ),
        ],
      ),
    );
  }
}
