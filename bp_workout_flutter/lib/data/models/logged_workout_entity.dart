/// On-device logged workout (mirrors iOS `LoggedWorkout` / exercise / set).
class LoggedWorkoutEntity {
  const LoggedWorkoutEntity({
    required this.id,
    required this.date,
    this.programId,
    this.programName,
    this.dayLabel,
    this.notes,
    required this.exercises,
  });

  final String id;
  final DateTime date;
  final String? programId;
  final String? programName;
  final String? dayLabel;
  final String? notes;
  final List<LoggedExerciseEntity> exercises;
}

class LoggedExerciseEntity {
  const LoggedExerciseEntity({
    required this.id,
    required this.name,
    this.prescribedName,
    required this.sortOrder,
    required this.sets,
  });

  final String id;
  final String name;
  final String? prescribedName;
  final int sortOrder;
  final List<LoggedSetEntity> sets;
}

class LoggedSetEntity {
  const LoggedSetEntity({
    required this.id,
    required this.weight,
    required this.reps,
    required this.order,
  });

  final String id;
  final double weight;
  final int reps;
  final int order;
}
