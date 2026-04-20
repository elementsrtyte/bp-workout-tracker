import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/models/logged_workout_entity.dart';
import '../../data/models/workout_program_models.dart';
import '../../data/repositories/logged_workout_repository.dart';
import '../../data/sync/workout_sync_service.dart';
import '../../providers/workout_hub_providers.dart';
import '../../theme/blueprint_colors.dart';

const _uuid = Uuid();

double? _parseLeadingNumber(String s) {
  final m = RegExp(r'([\d.]+)').firstMatch(s);
  if (m == null) return null;
  return double.tryParse(m.group(1)!);
}

class _SetControllers {
  _SetControllers({required this.weight, required this.reps});

  final TextEditingController weight;
  final TextEditingController reps;
}

/// Log one day of a program: prescription → per-set weight/reps, save locally + API sync.
class LogWorkoutScreen extends ConsumerStatefulWidget {
  const LogWorkoutScreen({
    super.key,
    required this.program,
    required this.dayIndex,
  });

  final WorkoutProgram program;
  final int dayIndex;

  @override
  ConsumerState<LogWorkoutScreen> createState() => _LogWorkoutScreenState();
}

class _LogWorkoutScreenState extends ConsumerState<LogWorkoutScreen> {
  late final List<List<_SetControllers>> _matrix;
  /// Snapshot of weight/reps fields at open — used to detect edits before save.
  late final List<List<(String, String)>> _initialFieldTexts;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final day = widget.program.days[widget.dayIndex];
    _matrix = day.exercises.map((ex) {
      final n = ex.targetSets ?? 3;
      final defW = _parseLeadingNumber(ex.maxWeight);
      final defR = ex.targetReps ?? 8;
      return List.generate(
        n,
        (_) => _SetControllers(
          weight: TextEditingController(
            text: defW != null && defW > 0 ? _stripTrailingZero(defW) : '',
          ),
          reps: TextEditingController(text: '$defR'),
        ),
      );
    }).toList();
    _initialFieldTexts = _matrix
        .map(
          (row) => row
              .map((c) => (c.weight.text, c.reps.text))
              .toList(),
        )
        .toList();
    for (final row in _matrix) {
      for (final c in row) {
        c.weight.addListener(_onFieldEdit);
        c.reps.addListener(_onFieldEdit);
      }
    }
  }

  void _onFieldEdit() {
    if (mounted) setState(() {});
  }

  bool get _isDirty {
    for (var ei = 0; ei < _matrix.length; ei++) {
      for (var si = 0; si < _matrix[ei].length; si++) {
        final c = _matrix[ei][si];
        final init = _initialFieldTexts[ei][si];
        if (c.weight.text != init.$1 || c.reps.text != init.$2) {
          return true;
        }
      }
    }
    return false;
  }

  Future<bool> _confirmLeaveWithoutSaving() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave without saving?'),
        content: const Text(
          'This workout will not be logged. You can open Log this day again anytime.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return go ?? false;
  }

  Future<void> _attemptPop() async {
    if (!_isDirty) {
      if (!context.mounted) return;
      Navigator.of(context).pop();
      return;
    }
    if (!await _confirmLeaveWithoutSaving()) return;
    if (!context.mounted) return;
    Navigator.of(context).pop();
  }

  static String _stripTrailingZero(double v) {
    if (v == v.roundToDouble()) return '${v.toInt()}';
    return '$v';
  }

  @override
  void dispose() {
    for (final row in _matrix) {
      for (final c in row) {
        c.weight.removeListener(_onFieldEdit);
        c.reps.removeListener(_onFieldEdit);
        c.weight.dispose();
        c.reps.dispose();
      }
    }
    super.dispose();
  }

  Future<void> _save() async {
    final day = widget.program.days[widget.dayIndex];
    final exercises = <LoggedExerciseEntity>[];
    for (var ei = 0; ei < day.exercises.length; ei++) {
      final ex = day.exercises[ei];
      final setCtrls = _matrix[ei];
      final sets = <LoggedSetEntity>[];
      for (var si = 0; si < setCtrls.length; si++) {
        final wText = setCtrls[si].weight.text.trim();
        final rText = setCtrls[si].reps.text.trim();
        final w = double.tryParse(wText) ?? 0.0;
        final r = int.tryParse(rText);
        if (r == null) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Invalid reps for “${ex.name}” set ${si + 1}.'),
            ),
          );
          return;
        }
        sets.add(
          LoggedSetEntity(
            id: _uuid.v4(),
            weight: w,
            reps: r,
            order: si,
          ),
        );
      }
      exercises.add(
        LoggedExerciseEntity(
          id: _uuid.v4(),
          name: ex.name,
          prescribedName: ex.name,
          sortOrder: ei,
          sets: sets,
        ),
      );
    }

    final workout = LoggedWorkoutEntity(
      id: _uuid.v4(),
      date: DateTime.now(),
      programId: widget.program.id,
      programName: widget.program.name,
      dayLabel: day.label,
      notes: null,
      exercises: exercises,
    );

    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repo = ref.read(loggedWorkoutRepositoryProvider);
      await repo.insertFull(workout);
      ref.read(workoutLogRevisionProvider.notifier).bump();
      try {
        await ref.read(workoutSyncServiceProvider).push(workout);
        if (mounted) {
          Navigator.of(context).pop();
          messenger.showSnackBar(
            const SnackBar(content: Text('Workout saved and synced.')),
          );
        }
      } catch (e) {
        if (mounted) {
          Navigator.of(context).pop();
          messenger.showSnackBar(
            SnackBar(
              content: Text('Saved on device; sync failed: $e'),
              backgroundColor: BlueprintColors.amber,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final day = widget.program.days[widget.dayIndex];
    return PopScope(
      canPop: !_isDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (!await _confirmLeaveWithoutSaving()) return;
        if (!context.mounted) return;
        Navigator.of(context).pop();
      },
      child: Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _saving ? null : _attemptPop,
        ),
        title: Text(day.label.isEmpty ? 'Log workout' : day.label),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            widget.program.name,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: BlueprintColors.cream,
                ),
          ),
          const SizedBox(height: 16),
          for (var ei = 0; ei < day.exercises.length; ei++) ...[
            _ExerciseBlock(
              exercise: day.exercises[ei],
              setControllers: _matrix[ei],
            ),
            const SizedBox(height: 20),
          ],
        ],
      ),
    ),
    );
  }
}

class _ExerciseBlock extends StatelessWidget {
  const _ExerciseBlock({
    required this.exercise,
    required this.setControllers,
  });

  final Exercise exercise;
  final List<_SetControllers> setControllers;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: BlueprintColors.card,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              exercise.name,
              style: const TextStyle(
                color: BlueprintColors.cream,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            if (exercise.notes != null && exercise.notes!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  exercise.notes!,
                  style: const TextStyle(
                    color: BlueprintColors.muted,
                    fontSize: 13,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            for (var i = 0; i < setControllers.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 72,
                      child: Text(
                        'Set ${i + 1}',
                        style: const TextStyle(color: BlueprintColors.mutedLight),
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        controller: setControllers[i].weight,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Weight',
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 88,
                      child: TextField(
                        controller: setControllers[i].reps,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Reps',
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
