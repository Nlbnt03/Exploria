import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kesfedio/features/onboarding/presentation/pages/onboarding_demo_page.dart';

void main() {
  Widget buildCard({
    required OnboardingDemoCheckInStage stage,
    VoidCallback? onOpenCheckIn,
    VoidCallback? onContinue,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: OnboardingDemoCheckInCard(
          stage: stage,
          venueName: 'Galatasaray Lisesi',
          onOpenCheckIn: onOpenCheckIn ?? () {},
          onContinue: onContinue ?? () {},
        ),
      ),
    );
  }

  testWidgets('yakındaki mekan için check-in eylemini gösterir', (
    tester,
  ) async {
    var openCount = 0;
    await tester.pumpWidget(
      buildCard(
        stage: OnboardingDemoCheckInStage.ready,
        onOpenCheckIn: () => openCount++,
      ),
    );

    expect(find.byKey(const ValueKey('demo-check-in-guide')), findsOneWidget);
    expect(find.text('Mekana ulaştın'), findsOneWidget);
    expect(find.text('Galatasaray Lisesi'), findsOneWidget);
    expect(find.text('Check-in’i Dene'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('demo-check-in-open')));
    expect(openCount, 1);
  });

  testWidgets('başarılı check-in sonrası demoya devam ettirir', (tester) async {
    var continueCount = 0;
    await tester.pumpWidget(
      buildCard(
        stage: OnboardingDemoCheckInStage.completed,
        onContinue: () => continueCount++,
      ),
    );

    expect(find.byKey(const ValueKey('demo-check-in-success')), findsOneWidget);
    expect(find.text('Check-in tamamlandı!'), findsOneWidget);
    expect(find.text('Demoya Devam Et'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('demo-check-in-continue')));
    expect(continueCount, 1);
  });
}
