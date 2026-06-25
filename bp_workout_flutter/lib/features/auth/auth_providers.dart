import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/env.dart';
import 'auth_service.dart';
import 'auth_session.dart';

final authServiceProvider = Provider<AuthService>((ref) => AuthService.instance);

/// Emits the current session, then every auth state change.
final authSessionProvider = StreamProvider<AuthSession?>((ref) async* {
  if (!Env.isApiConfigured) {
    yield null;
    return;
  }
  final auth = ref.watch(authServiceProvider);
  yield auth.currentSession;
  await for (final session in auth.sessionStream) {
    yield session;
  }
});

final accessTokenProvider = FutureProvider<String?>((ref) async {
  final session = ref.watch(authSessionProvider).valueOrNull;
  if (session == null) return null;
  try {
    return await ref.watch(authServiceProvider).accessTokenForApi();
  } catch (_) {
    return null;
  }
});
