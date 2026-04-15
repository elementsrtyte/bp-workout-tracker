import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../local/local_database.dart';
import '../models/logged_workout_entity.dart';

final loggedWorkoutRepositoryProvider = Provider<LoggedWorkoutRepository>((ref) {
  return LoggedWorkoutRepository();
});

class LoggedWorkoutRepository {
  Future<Database> get _db => LocalDatabase.instance();

  /// Inserts workout, exercises, and sets in one transaction.
  Future<void> insertFull(LoggedWorkoutEntity workout) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.insert('logged_workouts', {
        'id': workout.id,
        'date_ms': workout.date.millisecondsSinceEpoch,
        'program_id': workout.programId,
        'program_name': workout.programName,
        'day_label': workout.dayLabel,
        'notes': workout.notes,
      });
      for (final ex in workout.exercises) {
        await txn.insert('logged_exercises', {
          'id': ex.id,
          'workout_id': workout.id,
          'name': ex.name,
          'prescribed_name': ex.prescribedName,
          'sort_order': ex.sortOrder,
        });
        for (final s in ex.sets) {
          await txn.insert('logged_sets', {
            'id': s.id,
            'exercise_id': ex.id,
            'weight': s.weight,
            'reps': s.reps,
            'sort_order': s.order,
          });
        }
      }
    });
  }

  Future<List<LoggedWorkoutEntity>> listRecent({int limit = 25}) async {
    final db = await _db;
    final wRows = await db.query(
      'logged_workouts',
      orderBy: 'date_ms DESC',
      limit: limit,
    );
    final out = <LoggedWorkoutEntity>[];
    for (final wr in wRows) {
      final id = wr['id']! as String;
      final exRows = await db.query(
        'logged_exercises',
        where: 'workout_id = ?',
        whereArgs: [id],
        orderBy: 'sort_order ASC',
      );
      final exercises = <LoggedExerciseEntity>[];
      for (final er in exRows) {
        final exId = er['id']! as String;
        final setRows = await db.query(
          'logged_sets',
          where: 'exercise_id = ?',
          whereArgs: [exId],
          orderBy: 'sort_order ASC',
        );
        final sets = setRows
            .map(
              (sr) => LoggedSetEntity(
                id: sr['id']! as String,
                weight: (sr['weight'] as num).toDouble(),
                reps: sr['reps']! as int,
                order: sr['sort_order']! as int,
              ),
            )
            .toList();
        exercises.add(
          LoggedExerciseEntity(
            id: exId,
            name: er['name']! as String,
            prescribedName: er['prescribed_name'] as String?,
            sortOrder: er['sort_order']! as int,
            sets: sets,
          ),
        );
      }
      out.add(
        LoggedWorkoutEntity(
          id: id,
          date: DateTime.fromMillisecondsSinceEpoch(
            wr['date_ms']! as int,
            isUtc: false,
          ),
          programId: wr['program_id'] as String?,
          programName: wr['program_name'] as String?,
          dayLabel: wr['day_label'] as String?,
          notes: wr['notes'] as String?,
          exercises: exercises,
        ),
      );
    }
    return out;
  }
}
