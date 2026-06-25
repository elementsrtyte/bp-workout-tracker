import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/env.dart';
import '../../theme/blueprint_colors.dart';
import '../auth/auth_providers.dart';
import '../auth/auth_service.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = Env.blueprintApiUrl;
    final session = ref.watch(authSessionProvider).valueOrNull;
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
          ListTile(
            title: const Text('Account'),
            subtitle: Text(
              session?.user?.email ?? 'Not signed in',
              style: const TextStyle(color: BlueprintColors.mutedLight),
            ),
          ),
          if (session != null)
            ListTile(
              title: const Text('Sign out', style: TextStyle(color: BlueprintColors.danger)),
              onTap: () => AuthService.instance.signOut(),
            ),
        ],
      ),
    );
  }
}
