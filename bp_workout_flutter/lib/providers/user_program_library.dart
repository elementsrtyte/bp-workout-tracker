import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Same keys as iOS `UserProgramLibrary.swift`.
final userProgramLibraryProvider =
    NotifierProvider<UserProgramLibraryNotifier, int>(
  UserProgramLibraryNotifier.new,
);

class UserProgramLibraryNotifier extends Notifier<int> {
  static const libraryKey = 'profile.libraryProgramIds';
  static const activeProgramKey = 'workoutHub.activeProgramId';

  @override
  int build() => 0;

  void _bump() => state++;

  /// Default “all catalog programs” when key is unset.
  Future<Set<String>> idsInLibrary(List<String> catalogIds) async {
    final p = await SharedPreferences.getInstance();
    final catalog = catalogIds.toSet();
    if (!p.containsKey(libraryKey)) return catalog;
    final stored = p.getStringList(libraryKey) ?? [];
    return stored.toSet().intersection(catalog);
  }

  Future<bool> isInLibrary(String programId, List<String> catalogIds) async {
    final s = await idsInLibrary(catalogIds);
    return s.contains(programId);
  }

  Future<void> setProgramInLibrary(
    String programId,
    bool enabled,
    List<String> catalogIds,
  ) async {
    final p = await SharedPreferences.getInstance();
    var next = await idsInLibrary(catalogIds);
    if (enabled) {
      next.add(programId);
    } else {
      next.remove(programId);
    }
    await p.setStringList(libraryKey, next.toList());
    await _reconcileActiveProgram(p, catalogIds, next);
    _bump();
  }

  /// Sets the hub’s active program (must be in profile). Same key as iOS.
  Future<void> setActiveProgramId(String? programId) async {
    final p = await SharedPreferences.getInstance();
    if (programId == null || programId.isEmpty) {
      await p.remove(activeProgramKey);
    } else {
      await p.setString(activeProgramKey, programId);
    }
    _bump();
  }

  Future<void> _reconcileActiveProgram(
    SharedPreferences p,
    List<String> catalogIds,
    Set<String> inLib,
  ) async {
    final inProfilePrograms = catalogIds.where(inLib.contains).toList();
    if (inProfilePrograms.isEmpty) {
      await p.setString(activeProgramKey, '');
      return;
    }
    final saved = p.getString(activeProgramKey);
    if (saved != null &&
        saved.isNotEmpty &&
        inProfilePrograms.contains(saved)) {
      return;
    }
    await p.setString(activeProgramKey, inProfilePrograms.first);
  }
}
