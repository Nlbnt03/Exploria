import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../../app/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/services/map_progress_service.dart';
import '../map/gtu_boundary.dart';
import '../map/location_service.dart';
import 'city_map_page.dart';
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

  String _selectedAreaId = defaultCampusAreaId;
  bool _isOpeningMap = false;

  CampusAreaConfig get _selectedArea => resolveCampusArea(_selectedAreaId);

  @override
  void initState() {
    super.initState();
    unawaited(_restoreLastOpenedMapSelection());
  }

  Future<void> _restoreLastOpenedMapSelection() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      final lastAreaId = await _mapProgressService.fetchLastOpenedAreaId(uid);
      if (!mounted || lastAreaId == null || lastAreaId == _selectedAreaId) {
        return;
      }

      final exists = selectableCampusAreas.any((area) => area.id == lastAreaId);
      if (!exists) return;

      setState(() => _selectedAreaId = lastAreaId);
    } catch (_) {
      // Last opened map lookup is best-effort.
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

    if (widget.mode == 'multi') {
      setState(() => _isOpeningMap = true);
      try {
        await Navigator.pushNamed(
          context,
          AppRouter.createMultiRoom,
          arguments: CreateRoomScreenArgs(
            cityId: 'istanbul',
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
      final accessResult = await LocationService.requestSinglePosition();
      if (!mounted) return;

      if (!accessResult.isGranted) {
        _showGateMessage(accessResult.status);
        return;
      }

      final currentPosition = accessResult.position!;
      final isInsideArea = isPointInsidePolygon(
        currentPosition,
        selectedArea.boundary,
      );
      if (!isInsideArea) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${selectedArea.title} icinde degilsin. Haritayi acmak icin secilen alanin icine gir.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
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
        ),
      );
    } finally {
      if (mounted) setState(() => _isOpeningMap = false);
    }
  }

  Future<String?> _askMapName(String areaTitle) async {
    final rawName = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        fullscreenDialog: true,
        builder: (_) => _MapNameEntryPage(initialName: '$areaTitle Haritası'),
      ),
    );

    if (!mounted || rawName == null) return null;

    final name = rawName.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Harita adı boş olamaz.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return null;
    }

    return name;
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
        'Konum servisleri kapali. Haritayi acmak icin konumu etkinlestir.',
      LocationAccessStatus.permissionDenied =>
        'Konum izni gerekli. Lutfen izin verip tekrar dene.',
      LocationAccessStatus.permissionDeniedForever =>
        'Konum izni kalici olarak reddedildi. Ayarlardan izin vermen gerekiyor.',
      LocationAccessStatus.unavailable =>
        'Konum bilgisi alinamadi. Uygulamayi yeniden baslatip tekrar dene.',
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
                      'Kampus Haritalari',
                      style: TextStyle(
                        color: AppColors.textMain,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView.separated(
                        itemCount: selectableCampusAreas.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final area = selectableCampusAreas[index];
                          final isSelected = area.id == _selectedAreaId;
                          final icon =
                              area.id == campusAreaGtu
                                  ? Icons.school_rounded
                                  : Icons.apartment_rounded;
                          return InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap:
                                () => setState(() => _selectedAreaId = area.id),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color:
                                    isSelected
                                        ? AppColors.primary.withValues(
                                          alpha: 0.16,
                                        )
                                        : AppColors.card,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color:
                                      isSelected
                                          ? AppColors.primary
                                          : AppColors.inputBorder.withValues(
                                            alpha: 0.45,
                                          ),
                                  width: isSelected ? 1.5 : 1,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 52,
                                        height: 52,
                                        decoration: BoxDecoration(
                                          color: AppColors.primary.withValues(
                                            alpha: 0.22,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: Icon(
                                          icon,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              area.title,
                                              style: const TextStyle(
                                                color: AppColors.textMain,
                                                fontSize: 18,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              area.subtitle,
                                              style: const TextStyle(
                                                color: AppColors.textMuted,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Icon(
                                        isSelected
                                            ? Icons.check_circle_rounded
                                            : Icons
                                                .radio_button_unchecked_rounded,
                                        color:
                                            isSelected
                                                ? AppColors.primary
                                                : AppColors.textMuted,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 14),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: SizedBox(
                                      height: 180,
                                      width: double.infinity,
                                      child: Container(
                                        decoration: const BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                            colors: [
                                              Color(0xFF1B1A2F),
                                              Color(0xFF0E0D1A),
                                            ],
                                          ),
                                        ),
                                        child: Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            Positioned(
                                              right: -26,
                                              top: -30,
                                              child: Container(
                                                width: 140,
                                                height: 140,
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  color: AppColors.primary
                                                      .withValues(alpha: 0.16),
                                                ),
                                              ),
                                            ),
                                            Positioned(
                                              left: 14,
                                              right: 14,
                                              bottom: 14,
                                              child: Row(
                                                children: [
                                                  const Icon(
                                                    Icons.map_rounded,
                                                    color: AppColors.primary,
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Text(
                                                      area.subtitle,
                                                      style: const TextStyle(
                                                        color:
                                                            AppColors.textMain,
                                                        fontSize: 13,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
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
                                    widget.mode == 'multi'
                                        ? 'Coklu Oda Olustur'
                                        : '${_selectedArea.title} Haritasini Ac',
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
  const _MapNameEntryPage({required this.initialName});

  final String initialName;

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
    Navigator.pop(context, _controller.text);
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
