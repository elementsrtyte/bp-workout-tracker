import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/config/env.dart';
import '../../data/catalog/catalog_repository.dart';
import '../../data/models/workout_program_models.dart';
import '../../providers/user_program_library.dart';
import '../../providers/workout_hub_providers.dart';
import '../../theme/blueprint_colors.dart';
import 'log_workout_screen.dart';

/// Hub: pick profile program + day, log workout, list recent sessions.
class WorkoutHubScreen extends ConsumerStatefulWidget {
  const WorkoutHubScreen({super.key});

  @override
  ConsumerState<WorkoutHubScreen> createState() => _WorkoutHubScreenState();
}

class _WorkoutHubScreenState extends ConsumerState<WorkoutHubScreen> {
  int _dayIndex = 0;
  String? _lastProgramId;

  static final _dateFmt = DateFormat.yMMMd().add_jm();

  void _ensureDayInRange(WorkoutProgram? program) {
    if (program == null) {
      _dayIndex = 0;
      return;
    }
    if (program.id != _lastProgramId) {
      _lastProgramId = program.id;
      _dayIndex = 0;
    }
    if (program.days.isEmpty) {
      _dayIndex = 0;
    } else if (_dayIndex >= program.days.length) {
      _dayIndex = program.days.length - 1;
    }
  }

  WorkoutProgram? _selectedProgram(WorkoutHubDraft draft) {
    if (draft.programs.isEmpty) return null;
    final id = draft.activeProgramId;
    if (id != null && id.isNotEmpty) {
      final m = draft.programs.where((p) => p.id == id);
      if (m.isNotEmpty) return m.first;
    }
    return draft.programs.first;
  }

  @override
  Widget build(BuildContext context) {
    if (!Env.isApiConfigured) {
      return Scaffold(
        appBar: AppBar(title: const Text('Workout')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Set BLUEPRINT_API_URL via --dart-define or env to load programs.',
              textAlign: TextAlign.center,
              style: TextStyle(color: BlueprintColors.amber),
            ),
          ),
        ),
      );
    }

    final hubAsync = ref.watch(workoutHubDraftProvider);
    final recentAsync = ref.watch(recentLoggedWorkoutsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Workout')),
      body: hubAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: BlueprintColors.lavender),
        ),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Could not load hub:\n$e',
              style: const TextStyle(color: BlueprintColors.amber),
            ),
          ),
        ),
        data: (draft) {
          final selected = _selectedProgram(draft);
          if (draft.programs.isNotEmpty &&
              (draft.activeProgramId == null ||
                  draft.activeProgramId!.isEmpty)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              ref
                  .read(userProgramLibraryProvider.notifier)
                  .setActiveProgramId(draft.programs.first.id);
            });
          }
          _ensureDayInRange(selected);

          return RefreshIndicator(
            color: BlueprintColors.lavender,
            onRefresh: () async {
              ref.invalidate(catalogBundleProvider);
              ref.invalidate(workoutHubDraftProvider);
              ref.invalidate(recentLoggedWorkoutsProvider);
              await Future.wait([
                ref.read(catalogBundleProvider.future),
                ref.read(recentLoggedWorkoutsProvider.future),
              ]);
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                if (draft.programs.isEmpty) ...[
                  const Text(
                    'Add programs to your profile in the Programs tab to log workouts.',
                    style: TextStyle(color: BlueprintColors.mutedLight),
                  ),
                ] else ...[
                  const Text(
                    'Active program',
                    style: TextStyle(
                      color: BlueprintColors.muted,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 8),
                  InputDecorator(
                    decoration: const InputDecoration(
                      filled: true,
                      fillColor: BlueprintColors.cardInner,
                      border: OutlineInputBorder(),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        dropdownColor: BlueprintColors.card,
                        value: selected?.id,
                        items: [
                          for (final p in draft.programs)
                            DropdownMenuItem(value: p.id, child: Text(p.name)),
                        ],
                        onChanged: (id) {
                          if (id == null) return;
                          ref
                              .read(userProgramLibraryProvider.notifier)
                              .setActiveProgramId(id);
                          setState(() => _dayIndex = 0);
                        },
                      ),
                    ),
                  ),
                  if (selected != null && selected.days.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    const Text(
                      'Day',
                      style: TextStyle(
                        color: BlueprintColors.muted,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 40,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: selected.days.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, i) {
                          final label = selected.days[i].label.isEmpty
                              ? 'Day ${i + 1}'
                              : selected.days[i].label;
                          final on = i == _dayIndex;
                          return ChoiceChip(
                            label: Text(label),
                            selected: on,
                            onSelected: (_) => setState(() => _dayIndex = i),
                            selectedColor: BlueprintColors.purple.withOpacity(0.35),
                            labelStyle: TextStyle(
                              color: on
                                  ? BlueprintColors.cream
                                  : BlueprintColors.mutedLight,
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => LogWorkoutScreen(
                              program: selected,
                              dayIndex: _dayIndex,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.edit_note),
                      label: const Text('Log this day'),
                    ),
                  ],
                ],
                const SizedBox(height: 32),
                const Text(
                  'Recent',
                  style: TextStyle(
                    color: BlueprintColors.cream,
                    fontWeight: FontWeight.w600,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 12),
                recentAsync.when(
                  data: (list) {
                    if (list.isEmpty) {
                      return const Text(
                        'No logged workouts yet.',
                        style: TextStyle(color: BlueprintColors.mutedLight),
                      );
                    }
                    return Column(
                      children: [
                        for (final w in list)
                          Card(
                            color: BlueprintColors.card,
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              title: Text(
                                w.programName ?? 'Workout',
                                style: const TextStyle(color: BlueprintColors.cream),
                              ),
                              subtitle: Text(
                                [
                                  _dateFmt.format(w.date.toLocal()),
                                  if (w.dayLabel != null && w.dayLabel!.isNotEmpty)
                                    w.dayLabel!,
                                ].join(' · '),
                                style: const TextStyle(color: BlueprintColors.muted),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                  loading: () => const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(
                      child: CircularProgressIndicator(
                        color: BlueprintColors.lavender,
                      ),
                    ),
                  ),
                  error: (e, _) => Text(
                    'Could not load history: $e',
                    style: const TextStyle(color: BlueprintColors.amber),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
