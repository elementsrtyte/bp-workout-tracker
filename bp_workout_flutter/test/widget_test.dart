import 'package:bp_workout_flutter/app.dart';
import 'package:bp_workout_flutter/core/config/load_env.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadApplicationEnv();
  });

  testWidgets('App builds', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: BpWorkoutApp()),
    );
    expect(find.byType(BpWorkoutApp), findsOneWidget);
  });
}
