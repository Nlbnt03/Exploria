import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../app/router/app_router.dart';
import '../core/theme/app_colors.dart';
import '../features/auth/data/services/map_progress_service.dart';
import '../features/multi_room/services/multi_room_firestore_service.dart';
import '../features/auth/presentation/map/map_areas.dart';
import '../features/auth/presentation/pages/city_map_page.dart';
import '../features/multi_room/presentation/screens/waiting_room_screen.dart';
import '../features/multi_room/presentation/screens/multi_map_screen.dart';
import '../features/auth/domain/models/user_map_record.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({required this.uid});

  final String uid;

  @override
  State<HistoryPage> createState() => HistoryPageState();
}

class HistoryPageState extends State<HistoryPage> {
  final MapProgressService _mapProgressService = MapProgressService();
  final MultiRoomFirestoreService _multiRoomService =
      MultiRoomFirestoreService();
  String? _deletingMapId;
  String? _openingMapId;

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
            '"${record.mapName}" haritası geçmişten silinsin mi?',
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
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Sil'),
            ),
          ],
        );
      },
    );

    if (!mounted || shouldDelete != true) return;

    setState(() => _deletingMapId = record.mapId);
    try {
      await _mapProgressService
          .deleteMap(uid: widget.uid, mapId: record.mapId)
          .timeout(const Duration(seconds: 10));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Harita silindi.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Harita silinemedi, lütfen tekrar dene.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _deletingMapId = null);
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

                    return _AnimatedHistoryList(
                      records: records,
                      openingMapId: _openingMapId,
                      deletingMapId: _deletingMapId,
                      onOpen: (record) => unawaited(_openMap(record)),
                      onDelete: (record) => unawaited(_deleteMap(record)),
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

class _AnimatedHistoryList extends StatefulWidget {
  const _AnimatedHistoryList({
    required this.records,
    required this.openingMapId,
    required this.deletingMapId,
    required this.onOpen,
    required this.onDelete,
  });

  final List<UserMapRecord> records;
  final String? openingMapId;
  final String? deletingMapId;
  final ValueChanged<UserMapRecord> onOpen;
  final ValueChanged<UserMapRecord> onDelete;

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
        final subtitle =
            updatedAt == null ? '' : _formatDateTime(updatedAt);
        final isDeleting = widget.deletingMapId == record.mapId;
        final isOpening = widget.openingMapId == record.mapId;

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
                  color: AppColors.primary.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.map_rounded, color: AppColors.primary),
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
                      : IconButton(
                        tooltip: 'Haritayı sil',
                        onPressed: () => widget.onDelete(record),
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          color: AppColors.textMuted,
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
}
