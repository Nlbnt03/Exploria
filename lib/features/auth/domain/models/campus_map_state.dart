import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

class CampusMapState {
  const CampusMapState({
    required this.revealedCellIds,
    this.lastInsidePosition,
    this.cameraCenter,
    this.zoom,
  });

  final List<String> revealedCellIds;
  final Position? lastInsidePosition;
  final Position? cameraCenter;
  final double? zoom;
}
