import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/config/load_env.dart';
import 'features/auth/auth_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadApplicationEnv();
  await AuthService.instance.bootstrap();
  runApp(const ProviderScope(child: BpWorkoutApp()));
}
