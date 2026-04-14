import 'package:flutter/material.dart';

import '../../theme/blueprint_colors.dart';

/// Placeholder — port `GymCalendarView`.
class CalendarScreen extends StatelessWidget {
  const CalendarScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Calendar')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Training calendar — mirror SwiftData / sync queries from the iOS app.',
            textAlign: TextAlign.center,
            style: TextStyle(color: BlueprintColors.mutedLight),
          ),
        ),
      ),
    );
  }
}
