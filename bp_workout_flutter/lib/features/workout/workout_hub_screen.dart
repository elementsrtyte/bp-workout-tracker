import 'package:flutter/material.dart';

import '../../theme/blueprint_colors.dart';

/// Placeholder — port `WorkoutHubView` from iOS.
class WorkoutHubScreen extends StatelessWidget {
  const WorkoutHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Workout')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Workout hub — log sessions, pick program day, and sync via POST /v1/workouts (next step).',
            textAlign: TextAlign.center,
            style: TextStyle(color: BlueprintColors.mutedLight),
          ),
        ),
      ),
    );
  }
}
