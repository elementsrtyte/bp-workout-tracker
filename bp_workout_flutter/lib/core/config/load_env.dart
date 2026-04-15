import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:path/path.dart' as p;

/// Loads bundled `.env.example`, then optional `.env` / `.env.local` from disk, then on
/// **iOS/Android** merges a bundled `.env.local` (see `pubspec.yaml` assets).
///
/// Disk lookup tries `PWD`, [Directory.current], and `bp_workout_flutter/` under each
/// (monorepo-friendly). On simulators/devices, CWD is not the project dir, so the
/// bundled `.env.local` is what makes local secrets available at runtime.
///
/// **Note:** We merge extra files by patching [dotenv.env] with parsed key/value pairs.
/// `flutter_dotenv`'s [DotEnv.testLoad] is not suitable here: it prepends prior keys
/// then parses with "first key wins", so empty placeholders in `.env.example` would
/// block real values from `.env.local`.
///
/// Precedence for each key remains [Env]: `--dart-define` → `Platform.environment` → dotenv.
Future<void> loadApplicationEnv() async {
  await dotenv.load(fileName: '.env.example');
  await _mergeOptionalFileFromDisk('.env');
  await _mergeOptionalFileFromDisk('.env.local');
  await _mergeBundledEnvLocalOnMobile();
}

/// Applies `text` so later keys **overwrite** earlier (including empty → non-empty).
void _applyParsedEnv(String text) {
  const parser = Parser();
  final entries = parser.parse(text.split('\n'));
  for (final e in entries.entries) {
    dotenv.env[e.key] = e.value;
  }
}

Future<void> _mergeOptionalFileFromDisk(String name) async {
  for (final file in _envFileSearchPaths(name)) {
    try {
      if (await file.exists()) {
        _applyParsedEnv(await file.readAsString());
        return;
      }
    } catch (_) {
      // Unreadable path; try next candidate.
    }
  }
}

/// Bundled copy of `.env.local` (listed in `pubspec.yaml`) — used on iOS/Android only
/// so secrets are not dependent on process CWD.
Future<void> _mergeBundledEnvLocalOnMobile() async {
  if (kIsWeb) return;
  if (!Platform.isIOS && !Platform.isAndroid) return;
  try {
    final text = await rootBundle.loadString('.env.local');
    _applyParsedEnv(text);
  } catch (_) {
    // Asset missing or not declared; rely on dart-define / shell env.
  }
}

List<File> _envFileSearchPaths(String name) {
  final bases = <String>[];
  final pwd = Platform.environment['PWD'];
  if (pwd != null && pwd.isNotEmpty) bases.add(pwd);
  bases.add(Directory.current.path);

  final expanded = <String>[];
  for (final b in bases) {
    expanded.add(b);
    expanded.add(p.join(b, 'bp_workout_flutter'));
  }

  final out = <File>[];
  final seen = <String>{};
  for (final b in expanded) {
    final norm = p.normalize(b);
    if (seen.contains(norm)) continue;
    seen.add(norm);
    out.add(File(p.join(b, name)));
  }
  return out;
}
