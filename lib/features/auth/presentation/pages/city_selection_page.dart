import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../../../../app/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/services/map_area_firestore_service.dart';
import '../../data/services/map_progress_service.dart';
import '../map/map_areas.dart';
import '../map/location_service.dart';
import 'city_map_page.dart';
import 'map_preview_page.dart';
import '../../../multi_room/presentation/screens/create_room_screen.dart';

class CitySelectionPageArgs {
  const CitySelectionPageArgs({required this.mode});

  final String mode;
}

class CitySelectionPage extends StatefulWidget {
  const CitySelectionPage({super.key, required this.mode});

  final String mode;

  @override
  State<CitySelectionPage> createState() => _CitySelectionPageState();
}

class _CitySelectionPageState extends State<CitySelectionPage> {
  final MapProgressService _mapProgressService = MapProgressService();
  final MapAreaFirestoreService _mapAreaService = MapAreaFirestoreService();

  String _selectedAreaId = '';
  bool _isOpeningMap = false;
  bool _areasLoading = true;
  int _expandedGroupIndex = 0;
  List<MapAreaGroup> _dynamicGroups = [];

  List<MapAreaConfig> get _allAreas =>
      _dynamicGroups.expand((g) => g.areas).toList();

  MapAreaConfig? get _selectedArea =>
      _allAreas.where((a) => a.id == _selectedAreaId).firstOrNull;

  @override
  void initState() {
    super.initState();
    unawaited(_loadAreas());
  }

  Future<void> _loadAreas() async {
    try {
      final areas = await _mapAreaService.fetchAreas();
      if (!mounted) return;

      // Group published maps by their display city.
      final grouped = <String, List<MapAreaConfig>>{};
      for (final area in areas) {
        (grouped[area.city] ??= []).add(area);
      }

      final groups =
          grouped.entries
              .map(
                (e) => MapAreaGroup(
                  title: '${e.key} Haritaları',
                  icon: 0xe3ab, // Icons.location_city_rounded
                  areas: e.value,
                ),
              )
              .toList();

      setState(() {
        _dynamicGroups = groups;
        _areasLoading = false;
        if (areas.isNotEmpty) {
          _selectedAreaId = areas.first.id;
          _expandedGroupIndex = 0;
        }
      });

      unawaited(_restoreLastOpenedMapSelection());
    } catch (_) {
      if (mounted) {
        setState(() {
          _dynamicGroups = [];
          _areasLoading = false;
        });
      }
    }
  }

  Future<void> _restoreLastOpenedMapSelection() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      final lastAreaId = await _mapProgressService.fetchLastOpenedAreaId(uid);
      if (!mounted || lastAreaId == null || lastAreaId == _selectedAreaId) {
        return;
      }

      for (var i = 0; i < _dynamicGroups.length; i++) {
        final idx = _dynamicGroups[i].areas.indexWhere(
          (a) => a.id == lastAreaId,
        );
        if (idx != -1) {
          setState(() {
            _selectedAreaId = lastAreaId;
            _expandedGroupIndex = i;
          });
          return;
        }
      }
    } catch (_) {
      // Best-effort
    }
  }

  String get _modeLabel {
    switch (widget.mode) {
      case 'multi':
        return 'Çoklu';
      case 'solo':
      default:
        return 'Tekli';
    }
  }

  Future<void> _openSelectedMap() async {
    if (_isOpeningMap) return;
    final selectedArea = _selectedArea;
    if (selectedArea == null) return;

    // Show preview first – proceed only if user confirms.
    final confirmed = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        builder:
            (_) => MapPreviewPage(
              areaId: selectedArea.id,
              mode: widget.mode,
              mapAreaConfig: selectedArea,
            ),
      ),
    );
    if (confirmed != true || !mounted) return;

    if (widget.mode == 'multi') {
      setState(() => _isOpeningMap = true);
      try {
        await Navigator.pushNamed(
          context,
          AppRouter.createMultiRoom,
          arguments: CreateRoomScreenArgs(
            cityId: selectedArea.id,
            initialRoomName: '${selectedArea.title} Ekibi',
          ),
        );
      } finally {
        if (mounted) setState(() => _isOpeningMap = false);
      }
      return;
    }

    final mapName = await _askMapName(selectedArea.title);
    if (mapName == null || !mounted) return;

    setState(() => _isOpeningMap = true);
    try {
      Position? currentPosition;

      const kTestMode = false;

      if (!kTestMode && !selectedArea.skipLocationVerification) {
        final accessResult = await LocationService.requestSinglePosition();
        if (!mounted) return;

        if (!accessResult.isGranted) {
          _showGateMessage(accessResult.status);
          return;
        }

        currentPosition = accessResult.position!;
        final isInsideArea = isPointInsidePolygon(
          currentPosition,
          selectedArea.boundary,
        );
        if (!isInsideArea) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${selectedArea.title} içinde değilsin. Haritayı açmak için seçilen alanın içine gir.',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }
      }

      final mapId = await _createMapForSelection(
        areaId: selectedArea.id,
        mapName: mapName,
      );
      if (mapId == null || !mounted) return;

      await Navigator.pushNamed(
        context,
        AppRouter.cityMap,
        arguments: CityMapPageArgs(
          areaId: selectedArea.id,
          mapId: mapId,
          mapName: mapName,
          initialUserPosition: currentPosition,
          mapAreaConfig: selectedArea,
        ),
      );
    } finally {
      if (mounted) setState(() => _isOpeningMap = false);
    }
  }

  Future<String?> _askMapName(String areaTitle) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;

    setState(() => _isOpeningMap = true);
    List<String> existingNames = [];
    try {
      existingNames = await _mapProgressService.fetchAllMapNames(uid);
    } catch (_) {
      // Ignore errors when fetching existing map names
    } finally {
      if (mounted) setState(() => _isOpeningMap = false);
    }

    if (!mounted) return null;

    final rawName = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        fullscreenDialog: true,
        builder:
            (_) => _MapNameEntryPage(
              initialName: '$areaTitle Haritası',
              existingNames: existingNames,
            ),
      ),
    );

    if (!mounted || rawName == null) return null;

    return rawName;
  }

  Future<String?> _createMapForSelection({
    required String areaId,
    required String mapName,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Kullanıcı oturumu bulunamadı.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return null;
    }

    try {
      return await _mapProgressService.createMap(
        uid: uid,
        areaId: areaId,
        mapName: mapName,
      );
    } on FirebaseException catch (e) {
      if (!mounted) return null;
      final message = switch (e.code) {
        'permission-denied' =>
          'Harita oluşturma yetkisi yok. Firestore kurallarını deploy etmen gerekiyor.',
        'unauthenticated' =>
          'Oturum doğrulanamadı. Çıkış yapıp tekrar giriş yap.',
        _ => 'Harita oluşturulamadı (${e.code}).',
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
      return null;
    } catch (_) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Harita oluşturulamadı, lütfen tekrar dene.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return null;
    }
  }

  void _showGateMessage(LocationAccessStatus status) {
    final message = switch (status) {
      LocationAccessStatus.serviceDisabled =>
        'Konum servisleri kapalı. Haritayı açmak için konumu etkinleştir.',
      LocationAccessStatus.permissionDenied =>
        'Konum izni gerekli. Lütfen izin verip tekrar dene.',
      LocationAccessStatus.permissionDeniedForever =>
        'Konum izni kalıcı olarak reddedildi. Ayarlardan izin vermen gerekiyor.',
      LocationAccessStatus.unavailable =>
        'Konum bilgisi alınamadı. Uygulamayı yeniden başlatıp tekrar dene.',
      LocationAccessStatus.granted => '',
    };
    if (message.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBottom,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.bgTop, AppColors.bgBottom],
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(
                        Icons.arrow_back,
                        color: AppColors.textMain,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Harita Seçimi',
                      style: TextStyle(
                        color: AppColors.textMain,
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Mod: $_modeLabel',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 22),
                    const Text(
                      'Mevcut Haritalar',
                      style: TextStyle(
                        color: AppColors.textMain,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_areasLoading)
                      const Expanded(
                        child: Center(
                          child: CircularProgressIndicator(
                            color: AppColors.primary,
                          ),
                        ),
                      )
                    else if (_dynamicGroups.isEmpty)
                      const Expanded(
                        child: Center(
                          child: Text(
                            'Yayınlanmış harita bulunamadı.',
                            style: TextStyle(color: AppColors.textMuted),
                          ),
                        ),
                      )
                    else
                      Expanded(
                        child: ListView.separated(
                          itemCount: _dynamicGroups.length,
                          separatorBuilder:
                              (_, _) => const SizedBox(height: 14),
                          itemBuilder: (context, groupIndex) {
                            final group = _dynamicGroups[groupIndex];
                            final isExpanded =
                                _expandedGroupIndex == groupIndex;
                            final groupHasSelection = group.areas.any(
                              (a) => a.id == _selectedAreaId,
                            );

                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 220),
                              decoration: BoxDecoration(
                                color:
                                    isExpanded
                                        ? AppColors.card
                                        : AppColors.card.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color:
                                      groupHasSelection && isExpanded
                                          ? AppColors.primary.withValues(
                                            alpha: 0.5,
                                          )
                                          : AppColors.inputBorder.withValues(
                                            alpha: 0.35,
                                          ),
                                  width:
                                      groupHasSelection && isExpanded ? 1.3 : 1,
                                ),
                              ),
                              child: Column(
                                children: [
                                  // ── Group header ──
                                  InkWell(
                                    borderRadius: BorderRadius.circular(16),
                                    onTap:
                                        () => setState(() {
                                          _expandedGroupIndex =
                                              isExpanded ? -1 : groupIndex;
                                        }),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 14,
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 44,
                                            height: 44,
                                            decoration: BoxDecoration(
                                              color: AppColors.primary
                                                  .withValues(alpha: 0.18),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: Icon(
                                              IconData(
                                                group.icon,
                                                fontFamily: 'MaterialIcons',
                                              ),
                                              color: AppColors.primary,
                                              size: 22,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  group.title,
                                                  style: const TextStyle(
                                                    color: AppColors.textMain,
                                                    fontSize: 17,
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  '${group.areas.length} harita',
                                                  style: const TextStyle(
                                                    color: AppColors.textMuted,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          AnimatedRotation(
                                            turns: isExpanded ? 0.5 : 0,
                                            duration: const Duration(
                                              milliseconds: 220,
                                            ),
                                            child: Icon(
                                              Icons.keyboard_arrow_down_rounded,
                                              color:
                                                  isExpanded
                                                      ? AppColors.primary
                                                      : AppColors.textMuted,
                                              size: 26,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),

                                  // ── Expandable children ──
                                  AnimatedCrossFade(
                                    firstChild: const SizedBox.shrink(),
                                    secondChild: Column(
                                      children: [
                                        Container(
                                          margin: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                          ),
                                          height: 1,
                                          color: AppColors.inputBorder
                                              .withValues(alpha: 0.25),
                                        ),
                                        const SizedBox(height: 8),
                                        for (final area in group.areas)
                                          _AreaTile(
                                            area: area,
                                            isSelected:
                                                area.id == _selectedAreaId,
                                            onTap:
                                                () => setState(
                                                  () =>
                                                      _selectedAreaId = area.id,
                                                ),
                                          ),
                                        const SizedBox(height: 8),
                                      ],
                                    ),
                                    crossFadeState:
                                        isExpanded
                                            ? CrossFadeState.showSecond
                                            : CrossFadeState.showFirst,
                                    duration: const Duration(milliseconds: 220),
                                    sizeCurve: Curves.easeInOut,
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [AppColors.primary, AppColors.secondary],
                          ),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: ElevatedButton(
                          onPressed: _isOpeningMap ? null : _openSelectedMap,
                          style: ElevatedButton.styleFrom(
                            elevation: 0,
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child:
                              _isOpeningMap
                                  ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.3,
                                      color: Colors.white,
                                    ),
                                  )
                                  : Text(
                                    '${_selectedArea?.title ?? ''} Ön İzleme',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_isOpeningMap) ...[
            const ModalBarrier(dismissible: false, color: Color(0x99090B12)),
            const _MapOpeningSplash(),
          ],
        ],
      ),
    );
  }
}

class _MapOpeningSplash extends StatefulWidget {
  const _MapOpeningSplash();

  @override
  State<_MapOpeningSplash> createState() => _MapOpeningSplashState();
}

class _MapOpeningSplashState extends State<_MapOpeningSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat(reverse: true);
    _pulse = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Container(
            width: 220,
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
            decoration: BoxDecoration(
              color: const Color(0xEE171226),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: AppColors.inputBorder.withValues(alpha: 0.65),
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 24,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Transform.rotate(
                  angle: _controller.value * math.pi * 2,
                  child: Container(
                    width: 62 + (8 * _pulse.value),
                    height: 62 + (8 * _pulse.value),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [AppColors.primary, AppColors.secondary],
                      ),
                    ),
                    child: const Icon(
                      Icons.explore_rounded,
                      color: Colors.white,
                      size: 34,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Harita Hazırlanıyor',
                  style: TextStyle(
                    color: AppColors.textMain,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  'Lütfen bekle...',
                  style: TextStyle(
                    color: AppColors.textMuted.withValues(alpha: 0.9),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MapNameEntryPage extends StatefulWidget {
  const _MapNameEntryPage({
    required this.initialName,
    required this.existingNames,
  });

  final String initialName;
  final List<String> existingNames;

  @override
  State<_MapNameEntryPage> createState() => _MapNameEntryPageState();
}

class _MapNameEntryPageState extends State<_MapNameEntryPage> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Harita adı boş olamaz.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final exists = widget.existingNames.contains(name.toLowerCase());
    if (exists) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Bu isimde bir haritanız zaten var. Lütfen farklı bir isim girin.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBottom,
      appBar: AppBar(
        backgroundColor: AppColors.bgTop,
        foregroundColor: AppColors.textMain,
        title: const Text('Harita Adı'),
        actions: [
          TextButton(
            onPressed: _submit,
            child: const Text(
              'Devam',
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Haritana bir isim ver',
                style: TextStyle(
                  color: AppColors.textMain,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Bu isim geçmiş ekranında görünecek.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 14),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _controller,
                autofocus: true,
                maxLength: 60,
                style: const TextStyle(color: AppColors.textMain),
                decoration: InputDecoration(
                  hintText: 'Örn: Sabah Kampüs Yürüyüşü',
                  hintStyle: const TextStyle(color: AppColors.textMuted),
                  filled: true,
                  fillColor: AppColors.inputFill,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.inputBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.inputBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: AppColors.primary,
                      width: 1.5,
                    ),
                  ),
                ),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Haritayı Aç',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AreaTile extends StatelessWidget {
  const _AreaTile({
    required this.area,
    required this.isSelected,
    required this.onTap,
  });

  final MapAreaConfig area;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color:
              isSelected
                  ? AppColors.primary.withValues(alpha: 0.14)
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color:
                isSelected
                    ? AppColors.primary.withValues(alpha: 0.6)
                    : Colors.transparent,
            width: isSelected ? 1.2 : 0,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.map_rounded,
              color: isSelected ? AppColors.primary : AppColors.textMuted,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    area.title,
                    style: TextStyle(
                      color:
                          isSelected
                              ? AppColors.textMain
                              : AppColors.textMain.withValues(alpha: 0.85),
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    area.subtitle,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              isSelected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: isSelected ? AppColors.primary : AppColors.textMuted,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}
