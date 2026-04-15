import 'package:flutter/material.dart';

import 'features/auth/auth_shell.dart';
import 'theme/blueprint_theme.dart';

class BpWorkoutApp extends StatelessWidget {
  const BpWorkoutApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Blueprint Workout',
      debugShowCheckedModeBanner: false,
      theme: buildBlueprintTheme(),
      themeMode: ThemeMode.dark,
      home: const AuthShell(),
    );
  }
}
