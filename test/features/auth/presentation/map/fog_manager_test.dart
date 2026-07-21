import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kesfedio/features/auth/presentation/map/fog_manager.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

void main() {
  FogManager manager() => FogManager(
    campusBoundary: <Position>[
      Position(28.95, 41.00),
      Position(28.97, 41.00),
      Position(28.97, 41.02),
      Position(28.95, 41.02),
      Position(28.95, 41.00),
    ],
    gridSizeMeters: 65,
    revealRadiusMeters: 85,
  );

  List<Map<String, dynamic>> features(String geoJson) {
    final decoded = jsonDecode(geoJson) as Map<String, dynamic>;
    return (decoded['features'] as List<dynamic>).cast<Map<String, dynamic>>();
  }

  final southwest = Position(28.956, 41.006);
  final northeast = Position(28.964, 41.014);

  test('normal map zoom keeps every original white cloud puff unchanged', () async {
    final fog = manager();
    await fog.initialize();

    final legacyFog = features(
      fog.geoJsonForViewport(southwest: southwest, northeast: northeast),
    );
    final legacyClouds = features(
      fog.cloudGeoJsonForViewport(southwest: southwest, northeast: northeast),
    );
    final optimized = fog.renderForViewport(
      southwest: southwest,
      northeast: northeast,
      zoom: 16,
    );

    expect(optimized, isNotNull);
    final optimizedFogById = <Object?, Map<String, dynamic>>{
      for (final feature in features(optimized!.fogGeoJson))
        feature['id']: feature,
    };
    final optimizedCloudsById = <Object?, Map<String, dynamic>>{
      for (final feature in features(optimized.cloudGeoJson))
        feature['id']: feature,
    };

    for (final feature in legacyFog) {
      expect(optimizedFogById[feature['id']], feature);
    }
    for (final feature in legacyClouds) {
      expect(optimizedCloudsById[feature['id']], feature);
    }
  });

  test(
    'small camera movements reuse the already rendered fog coverage',
    () async {
      final fog = manager();
      await fog.initialize();

      expect(
        fog.renderForViewport(
          southwest: southwest,
          northeast: northeast,
          zoom: 16,
        ),
        isNotNull,
      );
      expect(
        fog.renderForViewport(
          southwest: Position(28.9562, 41.0062),
          northeast: Position(28.9642, 41.0142),
          zoom: 16,
        ),
        isNull,
      );

      expect(fog.revealForPosition(Position(28.96, 41.01)), isTrue);
      expect(
        fog.renderForViewport(
          southwest: Position(28.9562, 41.0062),
          northeast: Position(28.9642, 41.0142),
          zoom: 16,
        ),
        isNotNull,
      );
    },
  );

  test(
    'far zoom removes redundant overdraw while keeping cloud coverage',
    () async {
      final fog = manager();
      await fog.initialize();

      final closeRender =
          fog.renderForViewport(
            southwest: southwest,
            northeast: northeast,
            zoom: 17,
            force: true,
          )!;
      final closeFogCount = features(closeRender.fogGeoJson).length;
      final closeCloudCount = features(closeRender.cloudGeoJson).length;
      expect(closeCloudCount, closeFogCount * 10);

      final farRender =
          fog.renderForViewport(
            southwest: southwest,
            northeast: northeast,
            zoom: 12,
            force: true,
          )!;
      final farCloudCount = features(farRender.cloudGeoJson).length;

      expect(farCloudCount, greaterThan(0));
      expect(farCloudCount, lessThan(closeCloudCount ~/ 80));
    },
  );
}
