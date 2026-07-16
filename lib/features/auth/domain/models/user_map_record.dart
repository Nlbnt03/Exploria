import 'campus_map_state.dart';

class UserMapRecord {
  const UserMapRecord({
    required this.mapId,
    required this.areaId,
    required this.mapName,
    required this.state,
    this.status = 'active',
    this.totalPois = 0,
    this.visitedPois = 0,
    this.progressPercent = 0,
    this.earnedXp = 0,
    this.createdAt,
    this.updatedAt,
    this.completedAt,
  });

  final String mapId;
  final String areaId;
  final String mapName;
  final CampusMapState state;
  final String status;
  final int totalPois;
  final int visitedPois;
  final double progressPercent;
  final int earnedXp;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? completedAt;

  bool get isActive => status == 'active';
  bool get isCompleted => status == 'completed';
  bool get isDeleted => status == 'deleted';
}
