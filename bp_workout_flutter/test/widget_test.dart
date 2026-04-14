import 'package:bp_workout_flutter/app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App loads main shell', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: BpWorkoutApp()),
    );
    expect(find.text('Workout'), findsWidgets);
  });
}
