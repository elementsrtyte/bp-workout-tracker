/// JSON shapes for `GET /v1/catalog/programs` (see `api/src/services/workout-catalog.ts`).

class Exercise {
  const Exercise({
    required this.name,
    required this.maxWeight,
    this.targetSets,
    this.targetReps,
    this.supersetGroup,
    this.isAmrap,
    this.isWarmup,
    this.notes,
  });

  final String name;
  final String maxWeight;
  final int? targetSets;
  final int? targetReps;
  final int? supersetGroup;
  final bool? isAmrap;
  final bool? isWarmup;
  final String? notes;

  factory Exercise.fromJson(Map<String, dynamic> j) => Exercise(
        name: j['name'] as String? ?? '',
        maxWeight: j['maxWeight'] as String? ?? '',
        targetSets: j['targetSets'] as int?,
        targetReps: j['targetReps'] as int?,
        supersetGroup: j['supersetGroup'] as int?,
        isAmrap: j['isAmrap'] as bool?,
        isWarmup: j['isWarmup'] as bool?,
        notes: j['notes'] as String?,
      );
}

class WorkoutDay {
  const WorkoutDay({required this.label, required this.exercises});

  final String label;
  final List<Exercise> exercises;

  factory WorkoutDay.fromJson(Map<String, dynamic> j) => WorkoutDay(
        label: j['label'] as String? ?? '',
        exercises: (j['exercises'] as List<dynamic>? ?? [])
            .map((e) => Exercise.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class WorkoutProgram {
  const WorkoutProgram({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.period,
    required this.dateRange,
    required this.days,
    required this.color,
    this.isUserCreated,
    this.categorySlug,
    this.categoryTitle,
  });

  final String id;
  final String name;
  final String subtitle;
  final String period;
  final String dateRange;
  final List<WorkoutDay> days;
  final String color;
  final bool? isUserCreated;
  final String? categorySlug;
  final String? categoryTitle;

  factory WorkoutProgram.fromJson(Map<String, dynamic> j) => WorkoutProgram(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        subtitle: j['subtitle'] as String? ?? '',
        period: j['period'] as String? ?? '',
        dateRange: j['dateRange'] as String? ?? '',
        days: (j['days'] as List<dynamic>? ?? [])
            .map((e) => WorkoutDay.fromJson(e as Map<String, dynamic>))
            .toList(),
        color: j['color'] as String? ?? '#66bfcc',
        isUserCreated: j['isUserCreated'] as bool?,
        categorySlug: j['categorySlug'] as String?,
        categoryTitle: j['categoryTitle'] as String?,
      );
}

class CatalogCategory {
  const CatalogCategory({
    required this.slug,
    required this.title,
    required this.subtitle,
    required this.sortOrder,
    required this.iconSfSymbol,
  });

  final String slug;
  final String title;
  final String subtitle;
  final int sortOrder;
  final String iconSfSymbol;

  factory CatalogCategory.fromJson(Map<String, dynamic> j) => CatalogCategory(
        slug: j['slug'] as String? ?? '',
        title: j['title'] as String? ?? '',
        subtitle: j['subtitle'] as String? ?? '',
        sortOrder: j['sortOrder'] as int? ?? 0,
        iconSfSymbol: j['iconSfSymbol'] as String? ?? 'figure.strengthtraining.traditional',
      );
}

class ProgramStats {
  const ProgramStats({
    required this.totalPrograms,
    required this.totalMonths,
    required this.totalWorkoutDays,
    required this.dateRange,
  });

  final int totalPrograms;
  final int totalMonths;
  final int totalWorkoutDays;
  final String dateRange;

  factory ProgramStats.fromJson(Map<String, dynamic> j) => ProgramStats(
        totalPrograms: j['totalPrograms'] as int? ?? 0,
        totalMonths: j['totalMonths'] as int? ?? 0,
        totalWorkoutDays: j['totalWorkoutDays'] as int? ?? 0,
        dateRange: j['dateRange'] as String? ?? '',
      );
}

class WorkoutProgramsBundle {
  const WorkoutProgramsBundle({
    required this.programs,
    required this.stats,
    required this.categories,
  });

  final List<WorkoutProgram> programs;
  final ProgramStats stats;
  final List<CatalogCategory> categories;

  factory WorkoutProgramsBundle.fromJson(Map<String, dynamic> j) =>
      WorkoutProgramsBundle(
        programs: (j['programs'] as List<dynamic>? ?? [])
            .map((e) => WorkoutProgram.fromJson(e as Map<String, dynamic>))
            .toList(),
        stats: ProgramStats.fromJson(
          j['stats'] as Map<String, dynamic>? ?? {},
        ),
        categories: (j['categories'] as List<dynamic>? ?? [])
            .map((e) => CatalogCategory.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
