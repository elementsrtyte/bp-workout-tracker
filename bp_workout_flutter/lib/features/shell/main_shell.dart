import 'package:flutter/material.dart';

import '../../theme/blueprint_colors.dart';
import '../calendar/calendar_screen.dart';
import '../programs/programs_screen.dart';
import '../progress/progress_screen.dart';
import '../settings/settings_screen.dart';
import '../workout/workout_hub_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  static const _tabs = <_TabSpec>[
    _TabSpec('Workout', Icons.fitness_center, WorkoutHubScreen()),
    _TabSpec('Progress', Icons.show_chart, ProgressScreen()),
    _TabSpec('Calendar', Icons.calendar_month, CalendarScreen()),
    _TabSpec('Programs', Icons.storefront, ProgramsScreen()),
    _TabSpec('Settings', Icons.settings, SettingsScreen()),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: _tabs.map((t) => t.child).toList(),
      ),
      bottomNavigationBar: Theme(
        data: Theme.of(context).copyWith(
          splashColor: BlueprintColors.purple.withOpacity(0.12),
          highlightColor: BlueprintColors.purple.withOpacity(0.08),
        ),
        child: BottomNavigationBar(
          currentIndex: _index,
          onTap: (i) => setState(() => _index = i),
          items: [
            for (final t in _tabs)
              BottomNavigationBarItem(
                icon: Icon(t.icon),
                label: t.label,
              ),
          ],
        ),
      ),
    );
  }
}

class _TabSpec {
  const _TabSpec(this.label, this.icon, this.child);
  final String label;
  final IconData icon;
  final Widget child;
}
