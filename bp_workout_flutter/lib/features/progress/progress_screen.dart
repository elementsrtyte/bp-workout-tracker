import 'package:flutter/material.dart';

import '../../theme/blueprint_colors.dart';

/// Placeholder — port `ProgressTrackerView`.
class ProgressScreen extends StatelessWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Progress')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Progress charts and PRs — wire to your progress bundle / API when ready.',
            textAlign: TextAlign.center,
            style: TextStyle(color: BlueprintColors.mutedLight),
          ),
        ),
      ),
    );
  }
}
