import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kesfedio/features/passport/models/passport_models.dart';
import 'package:kesfedio/features/passport/presentation/passport_screen.dart';

void main() {
  PassportRegionPage buildCompletedPage() {
    return PassportRegionPage(
      areaId: 'istanbul_fatih',
      regionName: 'Fatih',
      colorHex: '#F2A93B',
      totalPoiCount: 2,
      firstStartedAt: DateTime(2026, 7, 1),
      completedAt: DateTime(2026, 7, 12),
      slots: <PassportStampSlot>[
        PassportStampSlot(
          poiId: 'ayasofya',
          poiName: 'Ayasofya',
          category: PassportPoiCategory.historic,
          visitedAt: DateTime(2026, 7, 10),
        ),
        PassportStampSlot(
          poiId: 'eminonu',
          poiName: 'Eminönü İskelesi',
          category: PassportPoiCategory.pier,
          visitedAt: DateTime(2026, 7, 12),
        ),
      ],
    );
  }

  Widget buildBook({String? initialAreaId}) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: const Color(0xFF100A1E),
        body: SizedBox(
          width: 430,
          height: 820,
          child: PassportBookView(
            collection: PassportCollection(pages: [buildCompletedPage()]),
            userName: 'Yusuf',
            initialAreaId: initialAreaId,
          ),
        ),
      ),
    );
  }

  testWidgets('kapaktan bölge sayfasına 3D çevirme ile ilerler', (
    tester,
  ) async {
    await tester.pumpWidget(buildBook());

    expect(find.byKey(const ValueKey('passport-cover-page')), findsOneWidget);
    expect(find.text('Kapak'), findsOneWidget);
    final previousButton = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('passport-previous-button')),
    );
    final previousDisabledColor = previousButton.style?.foregroundColor
        ?.resolve(const <WidgetState>{WidgetState.disabled});
    expect(previousDisabledColor?.a, greaterThan(0.8));

    await tester.tap(find.byKey(const ValueKey('passport-next-button')));
    await tester.pump();
    expect(find.byType(Transform), findsWidgets);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(
      find.byKey(const ValueKey('passport-region-istanbul_fatih')),
      findsOneWidget,
    );
    expect(find.text('2 / 2 mekân'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('passport-stamp-ayasofya')),
      findsOneWidget,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('passport-stamp-ayasofya')))
          .width,
      greaterThan(80),
    );
    expect(
      find.byKey(const ValueKey('passport-seal-istanbul_fatih')),
      findsOneWidget,
    );
    final nextButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey('passport-next-button')),
    );
    final nextDisabledColor = nextButton.style?.foregroundColor?.resolve(
      const <WidgetState>{WidgetState.disabled},
    );
    expect(nextDisabledColor?.a, greaterThanOrEqualTo(0.9));

    await tester.tap(find.byKey(const ValueKey('passport-previous-button')));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('passport-cover-page')), findsOneWidget);
  });

  testWidgets('tamamlanma kartından gelince hedef bölgeyi doğrudan açar', (
    tester,
  ) async {
    await tester.pumpWidget(buildBook(initialAreaId: 'istanbul_fatih'));

    expect(find.text('Fatih'), findsWidgets);
    expect(
      find.byKey(const ValueKey('passport-region-istanbul_fatih')),
      findsOneWidget,
    );
  });

  testWidgets(
    'animasyon sırasında veri listesi değişince indeksi güvenle sıfırlar',
    (tester) async {
      final collection = ValueNotifier<PassportCollection>(
        PassportCollection(pages: [buildCompletedPage()]),
      );
      addTearDown(collection.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<PassportCollection>(
              valueListenable: collection,
              builder:
                  (context, value, _) =>
                      PassportBookView(collection: value, userName: 'Yusuf'),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('passport-next-button')));
      await tester.pump(const Duration(milliseconds: 100));
      collection.value = const PassportCollection(
        pages: <PassportRegionPage>[],
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('passport-cover-page')), findsOneWidget);
      expect(find.text('1 / 1'), findsOneWidget);
    },
  );
}
