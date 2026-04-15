import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/catalog/catalog_repository.dart';
import '../data/models/logged_workout_entity.dart';
import '../data/models/workout_program_models.dart';
import '../data/repositories/logged_workout_repository.dart';
import 'user_program_library.dart';

class WorkoutHubDraft {
  const WorkoutHubDraft({
    required this.programs,
    required this.activeProgramId,
  });

  final List<WorkoutProgram> programs;
  final String? activeProgramId;
}

/// Programs in profile + active program id from SharedPreferences.
final workoutHubDraftProvider = FutureProvider<WorkoutHubDraft>((ref) async {
  ref.watch(userProgramLibraryProvider);
  final bundle = await ref.watch(catalogBundleProvider.future);
  final catalogIds = bundle.programs.map((p) => p.id).toList();
  final inLib =
      await ref.read(userProgramLibraryProvider.notifier).idsInLibrary(catalogIds);
  final programs =
      bundle.programs.where((p) => inLib.contains(p.id)).toList();
  final p = await SharedPreferences.getInstance();
  var activeId = p.getString(UserProgramLibraryNotifier.activeProgramKey);
  if (activeId != null &&
      activeId.isNotEmpty &&
      !programs.any((e) => e.id == activeId)) {
    activeId = null;
  }
  return WorkoutHubDraft(programs: programs, activeProgramId: activeId);
});

final workoutLogRevisionProvider =
    NotifierProvider<WorkoutLogRevisionNotifier, int>(
  WorkoutLogRevisionNotifier.new,
);

class WorkoutLogRevisionNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final recentLoggedWorkoutsProvider =
    FutureProvider<List<LoggedWorkoutEntity>>((ref) async {
  ref.watch(workoutLogRevisionProvider);
  final repo = ref.watch(loggedWorkoutRepositoryProvider);
  return repo.listRecent(limit: 25);
});
