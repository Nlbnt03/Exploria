import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../app/router/app_router.dart';
import '../core/theme/app_colors.dart';
import '../features/auth/data/services/map_progress_service.dart';
import '../features/multi_room/services/multi_room_firestore_service.dart';
import '../features/auth/presentation/map/map_areas.dart';
import '../features/auth/presentation/pages/city_map_page.dart';
import '../features/multi_room/presentation/screens/waiting_room_screen.dart';
import '../features/multi_room/presentation/screens/multi_map_screen.dart';
import '../features/auth/domain/models/user_map_record.dart';
import '../features/daily_exploration/data/services/share_map_snapshot_service.dart';
import '../features/daily_exploration/presentation/widgets/exploration_share_card.dart';
import '../features/free_walk/data/services/free_walk_history_service.dart';
import '../features/free_walk/domain/models/free_walk_result.dart';
import '../features/free_walk/presentation/pages/free_walk_share_preview_page.dart';
import '../features/free_walk/presentation/widgets/free_walk_share_card.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key, required this.uid});

  final String uid;

  @override
  State<HistoryPage> createState() => HistoryPageState();
}

class HistoryPageState extends State<HistoryPage> {
  final MapProgressService _mapProgressService = MapProgressService();
  final MultiRoomFirestoreService _multiRoomService =
      MultiRoomFirestoreService();
  final FreeWalkHistoryService _freeWalkHistoryService =
      FreeWalkHistoryService();
  final ShareMapSnapshotService _shareMapSnapshotService =
      const ShareMapSnapshotService();
  static const Duration _deleteUndoDuration = Duration(seconds: 6);
  final Set<String> _pendingDeleteMapIds = <String>{};
  final Set<String> _pendingDeleteWalkIds = <String>{};
  String? _deletingMapId;
  String? _openingMapId;
  String? _deletingWalkId;
  String? _openingWalkId;

  Future<void> _openMap(UserMapRecord record) async {
    if (_openingMapId != null) {
      return;
    }

    setState(() => _openingMapId = record.mapId);
    try {
      if (_isMultiHistoryRecord(record)) {
        await _openMultiMapFromHistory(record);
        return;
      }

      await Navigator.pushNamed(
        context,
        AppRouter.cityMap,
        arguments: CityMapPageArgs(
          areaId: record.areaId,
          mapId: record.mapId,
          mapName: record.mapName,
          fogEnabled: record.fogEnabled,
        ),
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;
      final message =
          e.code == 'unauthenticated'
              ? 'Oturum bulunamadi. Lutfen tekrar giris yap.'
              : 'Harita acilamadi: ${e.message ?? e.code}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Harita acilamadi: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _openingMapId = null);
      }
    }
  }

  Future<void> _openMultiMapFromHistory(UserMapRecord record) async {
    final roomId = _extractRoomIdFromHistory(record.mapId);
    if (roomId == null) {
      await _openFinishedMultiMapSnapshot(record);
      return;
    }

    try {
      var room = await _multiRoomService.fetchRoom(roomId);

      if (room == null) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Oda bulunamadi. Kayitli harita ozeti aciliyor.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        await _openFinishedMultiMapSnapshot(record);
        return;
      }

      if (!(room.isWaiting || room.isActive)) {
        await _openFinishedMultiMapSnapshot(record);
        return;
      }

      try {
        await _multiRoomService.ensureRoomMembership(room.id);
      } on FirebaseException catch (_) {
        // Membership set is best-effort. We can still try to continue.
      }

      room = await _multiRoomService.fetchRoom(room.id);
      if (room == null || room.isFinished) {
        await _openFinishedMultiMapSnapshot(record);
        return;
      }

      if (!mounted) {
        return;
      }

      if (room.isActive) {
        await Navigator.pushNamed(
          context,
          AppRouter.multiMap,
          arguments: MultiMapScreenArgs(roomId: room.id),
        );
        return;
      }

      await Navigator.pushNamed(
        context,
        AppRouter.waitingRoom,
        arguments: WaitingRoomScreenArgs(roomId: room.id),
      );
    } on FirebaseException catch (e) {
      if (!mounted) {
        return;
      }
      if (e.code == 'permission-denied') {
        try {
          await _multiRoomService.ensureRoomMembership(roomId);
          final room = await _multiRoomService.fetchRoom(roomId);
          if (room != null) {
            if (room.isActive) {
              if (!mounted) {
                return;
              }
              await Navigator.pushNamed(
                context,
                AppRouter.multiMap,
                arguments: MultiMapScreenArgs(roomId: room.id),
              );
              return;
            }
            if (room.isWaiting) {
              if (!mounted) {
                return;
              }
              await Navigator.pushNamed(
                context,
                AppRouter.waitingRoom,
                arguments: WaitingRoomScreenArgs(roomId: room.id),
              );
              return;
            }
          }
        } on FirebaseException catch (_) {
          // Ignore and fallback to snapshot.
        }

        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Bu odaya tekrar katilma yetkin yok. Kayitli harita ozeti aciliyor.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
        await _openFinishedMultiMapSnapshot(record);
        return;
      }
      rethrow;
    }
  }

  bool _isMultiHistoryRecord(UserMapRecord record) {
    final mapId = record.mapId.trim().toLowerCase();
    if (mapId.startsWith('multi_')) {
      return true;
    }

    final mapName = record.mapName.trim().toLowerCase();
    return mapName.contains('(coklu)') || mapName.contains('(çoklu)');
  }

  String? _extractRoomIdFromHistory(String mapId) {
    final normalized = mapId.trim();
    const prefix = 'multi_';
    if (!normalized.startsWith(prefix) || normalized.length <= prefix.length) {
      return null;
    }
    return normalized.substring(prefix.length);
  }

  Future<void> _openFinishedMultiMapSnapshot(UserMapRecord record) async {
    final resolvedAreaId = resolveMapArea(record.areaId).id;
    if (!mounted) {
      return;
    }

    await Navigator.pushNamed(
      context,
      AppRouter.cityMap,
      arguments: CityMapPageArgs(
        areaId: resolvedAreaId,
        mapId: record.mapId,
        mapName: record.mapName,
      ),
    );
  }

  Future<void> _deleteMap(UserMapRecord record) async {
    if (_pendingDeleteMapIds.contains(record.mapId) ||
        _deletingMapId == record.mapId) {
      return;
    }

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.bgBottom,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: AppColors.inputBorder.withValues(alpha: 0.4),
            ),
          ),
          title: const Text(
            'Haritayı Sil',
            style: TextStyle(color: AppColors.textMain),
          ),
          content: Text(
            '"${record.mapName}" aktif haritalarından kaldırılacak. '
            'Kazandığın pasaport pulları ve ziyaret tarihleri korunacak.',
            style: const TextStyle(color: AppColors.textMuted),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text(
                'Vazgeç',
                style: TextStyle(color: AppColors.textMuted),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Sil'),
            ),
          ],
        );
      },
    );

    if (!mounted || shouldDelete != true) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _pendingDeleteMapIds.add(record.mapId));

    messenger.hideCurrentSnackBar();
    final closedReason =
        await messenger
            .showSnackBar(
              SnackBar(
                duration: _deleteUndoDuration,
                behavior: SnackBarBehavior.floating,
                content: _DeleteUndoSnackBarContent(
                  itemLabel: record.mapName,
                  duration: _deleteUndoDuration,
                  onUndo:
                      () => messenger.hideCurrentSnackBar(
                        reason: SnackBarClosedReason.action,
                      ),
                ),
              ),
            )
            .closed;

    if (closedReason == SnackBarClosedReason.action) {
      if (mounted) {
        setState(() => _pendingDeleteMapIds.remove(record.mapId));
      }
      return;
    }

    if (mounted) {
      setState(() => _deletingMapId = record.mapId);
    }
    try {
      await _mapProgressService
          .deleteMap(uid: widget.uid, mapId: record.mapId)
          .timeout(const Duration(seconds: 10));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Harita kaldırıldı. Pasaport pulların korunmaya devam ediyor.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      debugPrint('[History] Harita silme hatası: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Harita silinemedi, lütfen tekrar dene.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _deletingMapId = null;
          _pendingDeleteMapIds.remove(record.mapId);
        });
      }
    }
  }

  void _shareMap(UserMapRecord record) {
    final visited =
        record.totalPois > 0
            ? '${record.visitedPois}/${record.totalPois}'
            : '${record.state.visitedPoiIds.length}';
    final earnedXp = record.earnedXp > 0 ? ' +${record.earnedXp} XP' : '';
    Share.share(
      'Keşfedio’da "${record.mapName}" haritasını tamamladım. '
      '$visited mekan gezildi$earnedXp.',
    );
  }

  Future<void> _openWalk(FreeWalkResult walk) async {
    if (_openingWalkId != null) return;
    setState(() => _openingWalkId = walk.id);
    try {
      final scene = walk.toShareScene();
      final mapSnapshot = await _shareMapSnapshotService.createSnapshot(
        scene,
        styleUri: MapboxStyles.OUTDOORS,
      );
      if (!mounted) return;
      await Navigator.push<bool>(
        context,
        MaterialPageRoute<bool>(
          builder:
              (_) => FreeWalkSharePreviewPage(
                result: walk,
                initialMapSnapshot: mapSnapshot,
                createMapSnapshot:
                    () => _shareMapSnapshotService.createSnapshot(
                      scene,
                      styleUri: MapboxStyles.OUTDOORS,
                    ),
              ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Yürüyüş kartı oluşturulamadı: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _openingWalkId = null);
    }
  }

  Future<void> _deleteWalk(FreeWalkResult walk) async {
    if (_pendingDeleteWalkIds.contains(walk.id) || _deletingWalkId == walk.id) {
      return;
    }

    final label =
        '${FreeWalkShareFormatting.shortDate(walk.startedAt)} yürüyüşü';
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.bgBottom,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: AppColors.inputBorder.withValues(alpha: 0.4),
            ),
          ),
          title: const Text(
            'Yürüyüşü Sil',
            style: TextStyle(color: AppColors.textMain),
          ),
          content: Text(
            '"$label" yürüyüş geçmişinden kaldırılacak.',
            style: const TextStyle(color: AppColors.textMuted),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text(
                'Vazgeç',
                style: TextStyle(color: AppColors.textMuted),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Sil'),
            ),
          ],
        );
      },
    );

    if (!mounted || shouldDelete != true) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _pendingDeleteWalkIds.add(walk.id));

    messenger.hideCurrentSnackBar();
    final closedReason =
        await messenger
            .showSnackBar(
              SnackBar(
                duration: _deleteUndoDuration,
                behavior: SnackBarBehavior.floating,
                content: _DeleteUndoSnackBarContent(
                  itemLabel: label,
                  duration: _deleteUndoDuration,
                  onUndo:
                      () => messenger.hideCurrentSnackBar(
                        reason: SnackBarClosedReason.action,
                      ),
                ),
              ),
            )
            .closed;

    if (closedReason == SnackBarClosedReason.action) {
      if (mounted) {
        setState(() => _pendingDeleteWalkIds.remove(walk.id));
      }
      return;
    }

    if (mounted) {
      setState(() => _deletingWalkId = walk.id);
    }
    try {
      await _freeWalkHistoryService
          .deleteWalk(uid: widget.uid, walkId: walk.id)
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('[History] Yürüyüş silme hatası: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Yürüyüş silinemedi, lütfen tekrar dene.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _deletingWalkId = null;
          _pendingDeleteWalkIds.remove(walk.id);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF130829),
      appBar: AppBar(
        title: const Text(
          'Geçmiş Haritalar',
          style: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.uid.isEmpty)
                const Text(
                  'Geçmişi görmek için oturum açmalısın.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 15),
                )
              else
                StreamBuilder<List<UserMapRecord>>(
                  stream: _mapProgressService.watchMapHistory(widget.uid),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      final error = snapshot.error;
                      final message =
                          error is FirebaseException &&
                                  error.code == 'permission-denied'
                              ? 'Geçmiş için yetki hatası: Firestore kurallarını deploy et.'
                              : 'Geçmiş yüklenemedi: $error';
                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: AppColors.inputBorder.withValues(
                              alpha: 0.45,
                            ),
                          ),
                        ),
                        child: Text(
                          message,
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 14,
                            height: 1.4,
                          ),
                        ),
                      );
                    }

                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: Center(
                          child: CircularProgressIndicator(
                            color: AppColors.primary,
                          ),
                        ),
                      );
                    }

                    final records = snapshot.data ?? const <UserMapRecord>[];
                    if (records.isEmpty) {
                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: AppColors.inputBorder.withValues(
                              alpha: 0.45,
                            ),
                          ),
                        ),
                        child: const Text(
                          'Henüz kayıtlı harita yok. Harita açarken isim verip oluşturabilirsin.',
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 15,
                            height: 1.4,
                          ),
                        ),
                      );
                    }

                    final activeRecords =
                        records
                            .where(
                              (record) =>
                                  !record.isCompleted &&
                                  !_pendingDeleteMapIds.contains(record.mapId),
                            )
                            .toList();
                    final completedRecords =
                        records
                            .where(
                              (record) =>
                                  record.isCompleted &&
                                  !_pendingDeleteMapIds.contains(record.mapId),
                            )
                            .toList();

                    return _HistoryTabbedList(
                      activeRecords: activeRecords,
                      completedRecords: completedRecords,
                      openingMapId: _openingMapId,
                      deletingMapId: _deletingMapId,
                      onOpen: (record) => unawaited(_openMap(record)),
                      onDelete: (record) => unawaited(_deleteMap(record)),
                      onShare: _shareMap,
                      walksStream: _freeWalkHistoryService.watchHistory(
                        widget.uid,
                      ),
                      pendingDeleteWalkIds: _pendingDeleteWalkIds,
                      openingWalkId: _openingWalkId,
                      deletingWalkId: _deletingWalkId,
                      onOpenWalk: (walk) => unawaited(_openWalk(walk)),
                      onDeleteWalk: (walk) => unawaited(_deleteWalk(walk)),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeleteUndoSnackBarContent extends StatelessWidget {
  const _DeleteUndoSnackBarContent({
    required this.itemLabel,
    required this.duration,
    required this.onUndo,
  });

  final String itemLabel;
  final Duration duration;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final seconds = duration.inSeconds;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 1, end: 0),
      duration: duration,
      builder: (context, value, _) {
        final remaining = (seconds * value).ceil().clamp(0, seconds);
        return Row(
          children: [
            Expanded(
              child: Text(
                '"$itemLabel" silinecek.',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),
            _UndoCountdownButton(
              remainingSeconds: remaining,
              progress: value,
              onPressed: onUndo,
            ),
          ],
        );
      },
    );
  }
}

class _UndoCountdownButton extends StatelessWidget {
  const _UndoCountdownButton({
    required this.remainingSeconds,
    required this.progress,
    required this.onPressed,
  });

  final int remainingSeconds;
  final double progress;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primary,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 7, 12, 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 2.4,
                      backgroundColor: Colors.white.withValues(alpha: 0.24),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Colors.white,
                      ),
                    ),
                    Text(
                      '$remainingSeconds',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 7),
              const Text(
                'GERİ AL',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryTabbedList extends StatefulWidget {
  const _HistoryTabbedList({
    required this.activeRecords,
    required this.completedRecords,
    required this.openingMapId,
    required this.deletingMapId,
    required this.onOpen,
    required this.onDelete,
    required this.onShare,
    required this.walksStream,
    required this.pendingDeleteWalkIds,
    required this.openingWalkId,
    required this.deletingWalkId,
    required this.onOpenWalk,
    required this.onDeleteWalk,
  });

  final List<UserMapRecord> activeRecords;
  final List<UserMapRecord> completedRecords;
  final String? openingMapId;
  final String? deletingMapId;
  final ValueChanged<UserMapRecord> onOpen;
  final ValueChanged<UserMapRecord> onDelete;
  final ValueChanged<UserMapRecord> onShare;
  final Stream<List<FreeWalkResult>> walksStream;
  final Set<String> pendingDeleteWalkIds;
  final String? openingWalkId;
  final String? deletingWalkId;
  final ValueChanged<FreeWalkResult> onOpenWalk;
  final ValueChanged<FreeWalkResult> onDeleteWalk;

  @override
  State<_HistoryTabbedList> createState() => _HistoryTabbedListState();
}

class _HistoryTabbedListState extends State<_HistoryTabbedList> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final isActiveTab = _selectedIndex == 0;
    final isCompletedTab = _selectedIndex == 1;
    final isWalksTab = _selectedIndex == 2;
    final records =
        isActiveTab ? widget.activeRecords : widget.completedRecords;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _HistoryTabButton(
                label: 'Aktif Haritalar (${widget.activeRecords.length}/5)',
                selected: isActiveTab,
                onTap: () => setState(() => _selectedIndex = 0),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _HistoryTabButton(
                label: 'Tamamlanan',
                selected: isCompletedTab,
                onTap: () => setState(() => _selectedIndex = 1),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _HistoryTabButton(
                label: 'Yürüyüş Geçmişi',
                selected: isWalksTab,
                onTap: () => setState(() => _selectedIndex = 2),
              ),
            ),
          ],
        ),
        if (isActiveTab && widget.activeRecords.length >= 5) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFB45309).withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.35),
              ),
            ),
            child: const Text(
              '5/5 aktif harita dolu. Yeni slot açmak için bir haritayı bitir veya sil.',
              style: TextStyle(
                color: AppColors.textMain,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        if (isWalksTab)
          StreamBuilder<List<FreeWalkResult>>(
            stream: widget.walksStream,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
                );
              }
              if (snapshot.hasError) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.inputBorder.withValues(alpha: 0.45),
                    ),
                  ),
                  child: Text(
                    'Yürüyüş geçmişi yüklenemedi: ${snapshot.error}',
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                );
              }
              final walks =
                  (snapshot.data ?? const <FreeWalkResult>[])
                      .where(
                        (walk) =>
                            !widget.pendingDeleteWalkIds.contains(walk.id),
                      )
                      .toList();
              if (walks.isEmpty) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.inputBorder.withValues(alpha: 0.45),
                    ),
                  ),
                  child: const Text(
                    'Henüz tamamlanmış bir serbest yürüyüşün yok.',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 15,
                      height: 1.4,
                    ),
                  ),
                );
              }
              return _FreeWalkAnimatedList(
                key: const ValueKey('walks'),
                walks: walks,
                openingWalkId: widget.openingWalkId,
                deletingWalkId: widget.deletingWalkId,
                onOpen: widget.onOpenWalk,
                onDelete: widget.onDeleteWalk,
              );
            },
          )
        else if (records.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.inputBorder.withValues(alpha: 0.45),
              ),
            ),
            child: Text(
              isActiveTab
                  ? 'Aktif haritan yok.'
                  : 'Henüz tamamlanan harita yok.',
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 15,
                height: 1.4,
              ),
            ),
          )
        else
          _AnimatedHistoryList(
            key: ValueKey(_selectedIndex),
            records: records,
            openingMapId: widget.openingMapId,
            deletingMapId: widget.deletingMapId,
            onOpen: widget.onOpen,
            onDelete: widget.onDelete,
            onShare: widget.onShare,
          ),
      ],
    );
  }
}

class _HistoryTabButton extends StatelessWidget {
  const _HistoryTabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primary : AppColors.inputFill,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: selected ? Colors.white : AppColors.textMuted,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _AnimatedHistoryList extends StatefulWidget {
  const _AnimatedHistoryList({
    super.key,
    required this.records,
    required this.openingMapId,
    required this.deletingMapId,
    required this.onOpen,
    required this.onDelete,
    required this.onShare,
  });

  final List<UserMapRecord> records;
  final String? openingMapId;
  final String? deletingMapId;
  final ValueChanged<UserMapRecord> onOpen;
  final ValueChanged<UserMapRecord> onDelete;
  final ValueChanged<UserMapRecord> onShare;

  @override
  State<_AnimatedHistoryList> createState() => _AnimatedHistoryListState();
}

class _AnimatedHistoryListState extends State<_AnimatedHistoryList>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(
        milliseconds: 300 + (widget.records.length * 80).clamp(0, 600),
      ),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.records.length;
    return Column(
      children: List.generate(count, (index) {
        final record = widget.records[index];
        final updatedAt = record.updatedAt ?? record.createdAt;
        final dateText = updatedAt == null ? '' : _formatDateTime(updatedAt);
        final completedAt = record.completedAt;
        final completedText =
            completedAt == null
                ? ''
                : 'Tamamlanma: ${_formatDateTime(completedAt)}';
        final durationText =
            record.createdAt != null && completedAt != null
                ? 'Süre: ${_formatDuration(completedAt.difference(record.createdAt!))}'
                : '';
        final progressText =
            record.totalPois > 0
                ? '${record.visitedPois.clamp(0, record.totalPois)}/${record.totalPois} mekan'
                : '${record.state.visitedPoiIds.length} mekan';
        final xpText = record.earnedXp > 0 ? '+${record.earnedXp} XP' : '';
        final subtitle =
            record.isCompleted
                ? [
                  completedText,
                  durationText,
                  [
                    progressText,
                    xpText,
                  ].where((part) => part.isNotEmpty).join(' • '),
                ].where((part) => part.isNotEmpty).join('\n')
                : [
                  'Aktif',
                  progressText,
                  dateText,
                ].where((part) => part.isNotEmpty).join(' • ');
        final isDeleting = widget.deletingMapId == record.mapId;
        final isOpening = widget.openingMapId == record.mapId;
        final iconColor =
            record.isCompleted ? AppColors.greenAccept : AppColors.primary;

        final start = (index / count).clamp(0.0, 1.0);
        final end = ((index + 1) / count).clamp(0.0, 1.0);
        final animation = CurvedAnimation(
          parent: _controller,
          curve: Interval(start, end, curve: Curves.easeOutCubic),
        );

        return AnimatedBuilder(
          animation: animation,
          builder: (context, child) {
            return Opacity(
              opacity: animation.value,
              child: Transform.translate(
                offset: Offset(0, 20 * (1 - animation.value)),
                child: child,
              ),
            );
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.inputBorder.withValues(alpha: 0.45),
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: ListTile(
                onTap:
                    (isDeleting || isOpening)
                        ? null
                        : () => widget.onOpen(record),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                leading: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.map_rounded, color: iconColor),
                ),
                title: Text(
                  record.mapName,
                  style: const TextStyle(
                    color: AppColors.textMain,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 13,
                    ),
                  ),
                ),
                trailing:
                    (isDeleting || isOpening)
                        ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary,
                          ),
                        )
                        : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (record.isCompleted)
                              IconButton(
                                tooltip: 'Paylaş',
                                onPressed: () => widget.onShare(record),
                                icon: const Icon(
                                  Icons.ios_share_rounded,
                                  color: AppColors.greenAccept,
                                ),
                              ),
                            IconButton(
                              tooltip: 'Haritayı sil',
                              onPressed: () => widget.onDelete(record),
                              icon: const Icon(
                                Icons.delete_outline_rounded,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
              ),
            ),
          ),
        );
      }),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final day = dateTime.day.toString().padLeft(2, '0');
    final month = dateTime.month.toString().padLeft(2, '0');
    final year = dateTime.year.toString();
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$day.$month.$year $hour:$minute';
  }

  String _formatDuration(Duration duration) {
    final days = duration.inDays;
    final hours = duration.inHours.remainder(24);
    final minutes = duration.inMinutes.remainder(60);
    if (days > 0) return '${days}g ${hours}s';
    if (hours > 0) return '${hours}s ${minutes}dk';
    return '${minutes.clamp(1, 59)}dk';
  }
}

class _FreeWalkAnimatedList extends StatefulWidget {
  const _FreeWalkAnimatedList({
    super.key,
    required this.walks,
    required this.openingWalkId,
    required this.deletingWalkId,
    required this.onOpen,
    required this.onDelete,
  });

  final List<FreeWalkResult> walks;
  final String? openingWalkId;
  final String? deletingWalkId;
  final ValueChanged<FreeWalkResult> onOpen;
  final ValueChanged<FreeWalkResult> onDelete;

  @override
  State<_FreeWalkAnimatedList> createState() => _FreeWalkAnimatedListState();
}

class _FreeWalkAnimatedListState extends State<_FreeWalkAnimatedList>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(
        milliseconds: 300 + (widget.walks.length * 80).clamp(0, 600),
      ),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.walks.length;
    return Column(
      children: List.generate(count, (index) {
        final walk = widget.walks[index];
        final distance = ExplorationShareFormatting.kilometers(
          walk.distanceMeters,
        );
        final duration = ExplorationShareFormatting.duration(
          walk.durationSeconds,
        );
        final pace = FreeWalkShareFormatting.pace(
          walk.distanceMeters,
          walk.durationSeconds,
        );
        final dateText =
            '${FreeWalkShareFormatting.shortDate(walk.startedAt)} · '
            '${FreeWalkShareFormatting.startTime(walk.startedAt)}';
        final isDeleting = widget.deletingWalkId == walk.id;
        final isOpening = widget.openingWalkId == walk.id;

        final start = (index / count).clamp(0.0, 1.0);
        final end = ((index + 1) / count).clamp(0.0, 1.0);
        final animation = CurvedAnimation(
          parent: _controller,
          curve: Interval(start, end, curve: Curves.easeOutCubic),
        );

        return AnimatedBuilder(
          animation: animation,
          builder: (context, child) {
            return Opacity(
              opacity: animation.value,
              child: Transform.translate(
                offset: Offset(0, 20 * (1 - animation.value)),
                child: child,
              ),
            );
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.inputBorder.withValues(alpha: 0.45),
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: ListTile(
                onTap:
                    (isDeleting || isOpening) ? null : () => widget.onOpen(walk),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                leading: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.directions_walk_rounded,
                    color: AppColors.primary,
                  ),
                ),
                title: Text(
                  dateText,
                  style: const TextStyle(
                    color: AppColors.textMain,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    '$distance • $duration • $pace/km',
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 13,
                    ),
                  ),
                ),
                trailing:
                    (isDeleting || isOpening)
                        ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary,
                          ),
                        )
                        : IconButton(
                          tooltip: 'Yürüyüşü sil',
                          onPressed: () => widget.onDelete(walk),
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            color: AppColors.textMuted,
                          ),
                        ),
              ),
            ),
          ),
        );
      }),
    );
  }
}
