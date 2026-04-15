import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/env.dart';

/// Emits the current session, then every auth state change (matches `SupabaseSessionManager` flow).
final authSessionProvider = StreamProvider<Session?>((ref) async* {
  if (!Env.isSupabaseConfigured) {
    yield null;
    return;
  }
  final client = Supabase.instance.client;
  yield client.auth.currentSession;
  await for (final event in client.auth.onAuthStateChange) {
    yield event.session;
  }
});
