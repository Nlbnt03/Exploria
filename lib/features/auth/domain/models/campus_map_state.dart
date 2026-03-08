import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

class CampusMapState {
  const CampusMapState({
    required this.revealedCellIds,
    required this.visitedPoiIds,
    this.lastInsidePosition,
    this.cameraCenter,
    this.zoom,
  });

  final List<String> revealedCellIds;
  final List<String> visitedPoiIds;
  final Position? lastInsidePosition;
  final Position? cameraCenter;
  final double? zoom;
}
