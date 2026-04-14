import 'dart:io';

/// Resolves `BLUEPRINT_API_URL` like the Swift `BlueprintAPIConfig` + dart-define.
abstract final class Env {
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
    return '';
  }

  static String _stripTrailingSlashes(String u) =>
      u.replaceAll(RegExp(r'/+$'), '');

  static bool get isApiConfigured => blueprintApiUrl.isNotEmpty;
}
