import 'package:flutter_test/flutter_test.dart';

import 'package:exploria/app/app.dart';

void main() {
  testWidgets('Login page renders', (WidgetTester tester) async {
    await tester.pumpWidget(const ExploriaApp());

    expect(find.text('Welcome Back to Exploria'), findsOneWidget);
    expect(find.text('LAUNCH EXPLORATION'), findsOneWidget);
  });
}
