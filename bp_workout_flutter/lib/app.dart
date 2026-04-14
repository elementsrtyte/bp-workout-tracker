import 'package:flutter/material.dart';

import 'features/shell/main_shell.dart';
import 'theme/blueprint_theme.dart';

class BpWorkoutApp extends StatelessWidget {
  const BpWorkoutApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Blueprint Workout',
      debugShowCheckedModeBanner: false,
      theme: buildBlueprintTheme(),
      home: const MainShell(),
    );
  }
}
