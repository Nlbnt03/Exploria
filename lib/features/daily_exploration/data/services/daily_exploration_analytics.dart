import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';

import '../../domain/models/daily_exploration.dart';

class DailyExplorationAnalytics {
  const DailyExplorationAnalytics();

  void promptShown(DailyExploration exploration) =>
      _log('daily_share_prompt_shown', exploration);

  void previewOpened(DailyExploration exploration) =>
      _log('daily_share_preview_opened', exploration);

  void completed(DailyExploration exploration) =>
      _log('daily_share_completed', exploration);

  void dismissed(DailyExploration exploration) =>
      _log('daily_share_dismissed', exploration);

  void failed(DailyExploration exploration) =>
      _log('daily_share_failed', exploration);

  void _log(String name, DailyExploration exploration) {
    unawaited(
      FirebaseAnalytics.instance.logEvent(
        name: name,
        parameters: <String, Object>{
          'map_id': exploration.mapId,
          'area_id': exploration.areaId,
          'session_count': exploration.sessionCount,
          'new_place_count': exploration.newPlaceCount,
          'distance_bucket': _distanceBucket(exploration.totalDistanceMeters),
        },
      ),
    );
  }

  String _distanceBucket(double meters) {
    if (meters < 1000) return 'under_1km';
    if (meters < 3000) return '1_3km';
    if (meters < 5000) return '3_5km';
    if (meters < 10000) return '5_10km';
    return '10km_plus';
  }
}
