import 'package:flutter_test/flutter_test.dart';
import 'package:kesfedio/features/passport/models/passport_models.dart';

void main() {
  test('bölge ilerlemesini ziyaret edilen pullardan hesaplar', () {
    final page = PassportRegionPage(
      areaId: 'istanbul_kadikoy',
      regionName: 'Kadıköy',
      colorHex: '#8B5CF6',
      totalPoiCount: 3,
      firstStartedAt: DateTime(2026),
      slots: <PassportStampSlot>[
        PassportStampSlot(
          poiId: 'moda',
          poiName: 'Moda İskelesi',
          category: PassportPoiCategory.pier,
          visitedAt: DateTime(2026, 7, 10),
        ),
        PassportStampSlot(
          poiId: 'muze',
          poiName: 'Müze Gazhane',
          category: PassportPoiCategory.museum,
          visitedAt: DateTime(2026, 7, 11),
        ),
        const PassportStampSlot(
          poiId: 'park',
          poiName: 'Yoğurtçu Parkı',
          category: PassportPoiCategory.park,
        ),
      ],
    );

    expect(page.visitedPoiCount, 2);
    expect(page.completionPercent, 67);
    expect(page.sealed, isFalse);
  });

  test('tüm slotlar ziyaret edildiğinde sayfayı mühürler', () {
    final page = PassportRegionPage(
      areaId: 'istanbul_fatih',
      regionName: 'Fatih',
      colorHex: '#F2A93B',
      totalPoiCount: 1,
      firstStartedAt: DateTime(2026),
      completedAt: DateTime(2026, 7, 12),
      slots: <PassportStampSlot>[
        PassportStampSlot(
          poiId: 'ayasofya',
          poiName: 'Ayasofya',
          category: PassportPoiCategory.historic,
          visitedAt: DateTime(2026, 7, 12),
        ),
      ],
    );

    expect(page.completionPercent, 100);
    expect(page.sealed, isTrue);
    expect(page.sealYear, 2026);
  });

  test('ham POI kategorilerini pasaport kategorilerine dönüştürür', () {
    expect(
      PassportPoiCategory.fromRaw('Tarihi Yapı'),
      PassportPoiCategory.historic,
    );
    expect(
      PassportPoiCategory.fromRaw('Plaj ve Sahil'),
      PassportPoiCategory.beach,
    );
    expect(
      PassportPoiCategory.fromRaw('Vapur İskelesi'),
      PassportPoiCategory.pier,
    );
  });
}
