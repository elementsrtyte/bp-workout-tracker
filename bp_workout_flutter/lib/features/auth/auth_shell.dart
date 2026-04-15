import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/env.dart';
import '../../theme/blueprint_colors.dart';
import '../shell/main_shell.dart';
import 'auth_providers.dart';
import 'login_screen.dart';

/// Mirrors `AuthRootView`: config check → loading → signed out (login) → signed in (`MainShell`).
class AuthShell extends ConsumerWidget {
  const AuthShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!Env.isSupabaseConfigured) {
      return const _ConfigMissingScreen();
    }

    final sessionAsync = ref.watch(authSessionProvider);

    return sessionAsync.when(
      data: (session) {
        if (session == null) {
          return const LoginScreen();
        }
        return const MainShell();
      },
      loading: () => const _AuthLoading(),
      error: (e, _) => _AuthError(message: '$e'),
    );
  }
}

class _AuthLoading extends StatelessWidget {
  const _AuthLoading();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: BlueprintColors.bg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: BlueprintColors.purple),
            SizedBox(height: 16),
            Text(
              'Loading…',
              style: TextStyle(color: BlueprintColors.mutedLight),
            ),
          ],
        ),
      ),
    );
  }
}

class _AuthError extends StatelessWidget {
  const _AuthError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BlueprintColors.bg,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            message,
            style: const TextStyle(color: BlueprintColors.danger),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

class _ConfigMissingScreen extends StatelessWidget {
  const _ConfigMissingScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BlueprintColors.bg,
      appBar: AppBar(title: const Text('Blueprint')),
      body: const Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Missing Supabase config. Add real values to `bp_workout_flutter/.env.local` '
          '(it must exist — copy from `.env.example` — and is bundled on iOS/Android), '
          'or pass --dart-define / --dart-define-from-file. Also set BLUEPRINT_API_URL for the catalog.',
          style: TextStyle(color: BlueprintColors.amber, height: 1.4),
        ),
      ),
    );
  }
}
