import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../api/blueprint_api_client.dart';
import '../catalog/catalog_repository.dart';
import '../models/logged_workout_entity.dart';

final workoutSyncServiceProvider = Provider<WorkoutSyncService>((ref) {
  return WorkoutSyncService(ref.watch(blueprintApiClientProvider));
});

/// Pushes a logged workout to `POST /v1/workouts` (same contract as iOS).
class WorkoutSyncService {
  WorkoutSyncService(this._api);

  final BlueprintApiClient _api;

  Future<void> push(LoggedWorkoutEntity workout) async {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token == null || token.isEmpty) {
      throw StateError('Not signed in');
    }
    await _api.post<void>(
      '/v1/workouts',
      body: _body(workout),
      bearerToken: token,
    );
  }

  Map<String, dynamic> _body(LoggedWorkoutEntity w) {
    return {
      'id': w.id,
      'date': w.date.toUtc().toIso8601String(),
      'programId': w.programId,
      'programName': w.programName,
      'dayLabel': w.dayLabel,
      'notes': w.notes,
      'exercises': w.exercises
          .map(
            (e) => {
              'id': e.id,
              'name': e.name,
              'prescribedName': e.prescribedName,
              'sortOrder': e.sortOrder,
              'sets': e.sets
                  .map(
                    (s) => {
                      'id': s.id,
                      'weight': s.weight,
                      'reps': s.reps,
                      'order': s.order,
                    },
                  )
                  .toList(),
            },
          )
          .toList(),
    };
  }
}
