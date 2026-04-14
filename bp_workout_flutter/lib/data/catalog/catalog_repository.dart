import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/env.dart';
import '../api/blueprint_api_client.dart';
import '../models/workout_program_models.dart';

final blueprintApiClientProvider = Provider<BlueprintApiClient>((ref) {
  return BlueprintApiClient();
});

final catalogRepositoryProvider = Provider<CatalogRepository>((ref) {
  return CatalogRepository(ref.watch(blueprintApiClientProvider));
});

class CatalogRepository {
  CatalogRepository(this._client);

  final BlueprintApiClient _client;

  Future<WorkoutProgramsBundle> fetchProgramsBundle() async {
    if (!Env.isApiConfigured) {
      throw StateError(
        'BLUEPRINT_API_URL is empty. Use --dart-define=BLUEPRINT_API_URL=... '
        'or set the environment variable.',
      );
    }
    final res = await _client.get<Map<String, dynamic>>('/v1/catalog/programs');
    final data = res.data;
    if (data == null) {
      throw StateError('Empty catalog response');
    }
    return WorkoutProgramsBundle.fromJson(data);
  }

  /// For debugging / offline cache seeding.
  String bundleToJson(WorkoutProgramsBundle bundle) => jsonEncode({
        'programs': bundle.programs.map(_programToMap).toList(),
        'stats': {
          'totalPrograms': bundle.stats.totalPrograms,
          'totalMonths': bundle.stats.totalMonths,
          'totalWorkoutDays': bundle.stats.totalWorkoutDays,
          'dateRange': bundle.stats.dateRange,
        },
        'categories': bundle.categories.map(_categoryToMap).toList(),
      });

  Map<String, dynamic> _programToMap(WorkoutProgram p) => {
        'id': p.id,
        'name': p.name,
        'subtitle': p.subtitle,
        'period': p.period,
        'dateRange': p.dateRange,
        'color': p.color,
        'isUserCreated': p.isUserCreated,
        'categorySlug': p.categorySlug,
        'categoryTitle': p.categoryTitle,
        'days': p.days.map(_dayToMap).toList(),
      };

  Map<String, dynamic> _dayToMap(WorkoutDay d) => {
        'label': d.label,
        'exercises': d.exercises.map(_exToMap).toList(),
      };

  Map<String, dynamic> _exToMap(Exercise e) => {
        'name': e.name,
        'maxWeight': e.maxWeight,
        'targetSets': e.targetSets,
        'targetReps': e.targetReps,
        'supersetGroup': e.supersetGroup,
        'isAmrap': e.isAmrap,
        'isWarmup': e.isWarmup,
        'notes': e.notes,
      };

  Map<String, dynamic> _categoryToMap(CatalogCategory c) => {
        'slug': c.slug,
        'title': c.title,
        'subtitle': c.subtitle,
        'sortOrder': c.sortOrder,
        'iconSfSymbol': c.iconSfSymbol,
      };
}

final catalogBundleProvider = FutureProvider<WorkoutProgramsBundle>((ref) async {
  final repo = ref.watch(catalogRepositoryProvider);
  return repo.fetchProgramsBundle();
});
