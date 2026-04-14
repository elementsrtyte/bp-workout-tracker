import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/env.dart';
import '../../data/catalog/catalog_repository.dart';
import '../../data/models/workout_program_models.dart';
import '../../theme/blueprint_colors.dart';

/// Programs / marketplace — loads `GET /v1/catalog/programs` (full UI parity later).
class ProgramsScreen extends ConsumerWidget {
  const ProgramsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!Env.isApiConfigured) {
      return Scaffold(
        appBar: AppBar(title: const Text('Programs')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Set BLUEPRINT_API_URL via --dart-define or environment to load the catalog.',
              textAlign: TextAlign.center,
              style: TextStyle(color: BlueprintColors.amber),
            ),
          ),
        ),
      );
    }

    final async = ref.watch(catalogBundleProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Programs')),
      body: async.when(
        data: (bundle) => _CatalogList(bundle: bundle),
        loading: () => const Center(
          child: CircularProgressIndicator(color: BlueprintColors.lavender),
        ),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Could not load catalog:\n$e',
              style: const TextStyle(color: BlueprintColors.amber),
            ),
          ),
        ),
      ),
    );
  }
}

class _CatalogList extends StatelessWidget {
  const _CatalogList({required this.bundle});

  final WorkoutProgramsBundle bundle;

  @override
  Widget build(BuildContext context) {
    final programs = bundle.programs;
    if (programs.isEmpty) {
      return const Center(
        child: Text(
          'No programs in bundle.',
          style: TextStyle(color: BlueprintColors.mutedLight),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: programs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final p = programs[i];
        final days = p.days.length;
        final perWeek = days == 0            ? 'No training days'
            : days == 1
                ? '1 day/week'
                : '$days days/week';
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        p.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: BlueprintColors.cream,
                        ),
                      ),
                    ),
                    if (p.categoryTitle != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: BlueprintColors.lavender.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          p.categoryTitle!.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: BlueprintColors.lavender,
                          ),
                        ),
                      ),
                  ],
                ),
                if (p.subtitle.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    p.subtitle,
                    style: const TextStyle(
                      color: BlueprintColors.mutedLight,
                      fontSize: 14,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  perWeek,
                  style: const TextStyle(
                    color: BlueprintColors.muted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
