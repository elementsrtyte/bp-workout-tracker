import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';

/// API + Supabase config. Precedence: `--dart-define` → `Platform.environment` →
/// [dotenv] (`.env.example` + optional `.env` / `.env.local` + bundled `.env.local` on mobile).
abstract final class Env {
  static String get supabaseUrl {
    const d = String.fromEnvironment('SUPABASE_URL', defaultValue: '');
    if (d.trim().isNotEmpty) return _stripTrailingSlashes(d.trim());
    final e = Platform.environment['SUPABASE_URL']?.trim();
    if (e != null && e.isNotEmpty) return _stripTrailingSlashes(e);
    final fromDot = _dot('SUPABASE_URL');
    if (fromDot != null) return _stripTrailingSlashes(fromDot);
    return '';
  }

  static String get supabaseAnonKey {
    const d = String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');
    if (d.trim().isNotEmpty) return d.trim();
    final e = Platform.environment['SUPABASE_ANON_KEY']?.trim();
    if (e != null && e.isNotEmpty) return e;
    final fromDot = _dot('SUPABASE_ANON_KEY');
    if (fromDot != null) return fromDot;
    return '';
  }

  static bool get isSupabaseConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static String get blueprintApiUrl {
    const fromDefine = String.fromEnvironment(
      'BLUEPRINT_API_URL',
      defaultValue: '',
    );
    if (fromDefine.trim().isNotEmpty) {
      return _stripTrailingSlashes(fromDefine.trim());
    }
    final e = Platform.environment['BLUEPRINT_API_URL']?.trim();
    if (e != null && e.isNotEmpty) return _stripTrailingSlashes(e);
    final fromDot = _dot('BLUEPRINT_API_URL');
    if (fromDot != null) return _stripTrailingSlashes(fromDot);
    return '';
  }

  static String? _dot(String key) {
    if (!dotenv.isInitialized) return null;
    final v = dotenv.env[key]?.trim();
    if (v == null || v.isEmpty) return null;
    return v;
  }

  static String _stripTrailingSlashes(String u) =>
      u.replaceAll(RegExp(r'/+$'), '');

  static bool get isApiConfigured => blueprintApiUrl.isNotEmpty;
}
