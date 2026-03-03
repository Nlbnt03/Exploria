import 'campus_map_state.dart';

class UserMapRecord {
  const UserMapRecord({
    required this.mapId,
    required this.areaId,
    required this.mapName,
    required this.state,
    this.createdAt,
    this.updatedAt,
  });

  final String mapId;
  final String areaId;
  final String mapName;
  final CampusMapState state;
  final DateTime? createdAt;
  final DateTime? updatedAt;
}
