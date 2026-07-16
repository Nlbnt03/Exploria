import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../auth/domain/models/user_map_record.dart';
import '../models/passport_models.dart';
import '../services/passport_service.dart';

class PassportScreen extends StatefulWidget {
  const PassportScreen({
    super.key,
    required this.uid,
    required this.userName,
    required this.records,
    required this.active,
    this.initialAreaId,
  });

  final String uid;
  final String userName;
  final List<UserMapRecord> records;
  final bool active;
  final String? initialAreaId;

  @override
  State<PassportScreen> createState() => _PassportScreenState();
}

class _PassportScreenState extends State<PassportScreen> {
  final PassportService _service = PassportService();
  PassportCollection? _collection;
  Object? _error;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    if (widget.active) unawaited(_loadCollection());
  }

  @override
  void didUpdateWidget(covariant PassportScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final userChanged = oldWidget.uid != widget.uid;
    final becameActive = widget.active && !oldWidget.active;
    final recordsChanged = !identical(oldWidget.records, widget.records);
    if (userChanged) {
      _collection = null;
      _error = null;
    }
    if (widget.active && (userChanged || becameActive || recordsChanged)) {
      unawaited(_loadCollection());
    }
  }

  Future<void> _loadCollection() async {
    final generation = ++_loadGeneration;
    if (widget.uid.isEmpty) {
      if (!mounted) return;
      setState(() {
        _collection = const PassportCollection(pages: <PassportRegionPage>[]);
        _error = null;
      });
      return;
    }
    try {
      final collection = await _service.buildCollection(
        uid: widget.uid,
        records: widget.records,
      );
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _collection = collection;
        _error = null;
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final collection = _collection;
    return ColoredBox(
      color: const Color(0xFF100A1E),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Keşif Pasaportu',
                  style: TextStyle(
                    color: AppColors.textMain,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.8,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  collection == null
                      ? 'Pasaportun hazırlanıyor…'
                      : '${collection.stampCount} pul  •  ${collection.regionCount} bölge',
                  key: const ValueKey('passport-summary'),
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.menu_book_rounded,
                color: AppColors.textMuted,
                size: 48,
              ),
              const SizedBox(height: 12),
              const Text(
                'Pasaport şu anda açılamadı.',
                style: TextStyle(
                  color: AppColors.textMain,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _loadCollection,
                child: const Text('Tekrar Dene'),
              ),
            ],
          ),
        ),
      );
    }
    final collection = _collection;
    if (collection == null) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }
    return PassportBookView(
      collection: collection,
      userName: widget.userName,
      initialAreaId: widget.initialAreaId,
    );
  }
}

class PassportBookView extends StatefulWidget {
  const PassportBookView({
    super.key,
    required this.collection,
    required this.userName,
    this.initialAreaId,
  });

  final PassportCollection collection;
  final String userName;
  final String? initialAreaId;

  @override
  State<PassportBookView> createState() => _PassportBookViewState();
}

class _PassportBookViewState extends State<PassportBookView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flipController;
  late final Animation<double> _flipAnimation;
  int _currentIndex = 0;
  int? _targetIndex;
  bool _forward = true;

  int get _pageCount => widget.collection.pages.length + 1;
  bool get _isAnimating => _targetIndex != null;

  @override
  void initState() {
    super.initState();
    _currentIndex = _indexForArea(widget.initialAreaId);
    _flipController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );
    _flipAnimation = CurvedAnimation(
      parent: _flipController,
      curve: const Cubic(0.22, 0.72, 0.18, 1),
    );
    _flipController.addStatusListener((status) {
      if (status != AnimationStatus.completed || !mounted) return;
      setState(() {
        final requestedIndex = _targetIndex ?? _currentIndex;
        _currentIndex = math.min(
          math.max(0, requestedIndex),
          math.max(0, _pageCount - 1),
        );
        _targetIndex = null;
        _flipController.reset();
      });
    });
  }

  @override
  void didUpdateWidget(covariant PassportBookView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialAreaId != oldWidget.initialAreaId && !_isAnimating) {
      _currentIndex = _indexForArea(widget.initialAreaId);
    }

    final maxIndex = math.max(0, _pageCount - 1);
    if (_targetIndex case final targetIndex? when targetIndex > maxIndex) {
      _flipController.stop();
      _flipController.reset();
      _targetIndex = null;
    }
    _currentIndex = math.min(math.max(0, _currentIndex), maxIndex);
  }

  int _indexForArea(String? areaId) {
    if (areaId == null) return 0;
    final regionIndex = widget.collection.pages.indexWhere(
      (page) => page.areaId == areaId,
    );
    return regionIndex < 0 ? 0 : regionIndex + 1;
  }

  @override
  void dispose() {
    _flipController.dispose();
    super.dispose();
  }

  void _turnForward() {
    if (_isAnimating || _currentIndex >= _pageCount - 1) return;
    setState(() {
      _forward = true;
      _targetIndex = _currentIndex + 1;
    });
    unawaited(_flipController.forward(from: 0));
  }

  void _turnBack() {
    if (_isAnimating || _currentIndex <= 0) return;
    setState(() {
      _forward = false;
      _targetIndex = _currentIndex - 1;
    });
    unawaited(_flipController.forward(from: 0));
  }

  @override
  Widget build(BuildContext context) {
    final pageLabel =
        _currentIndex == 0
            ? 'Kapak'
            : widget.collection.pages[_currentIndex - 1].regionName;
    return Column(
      key: const ValueKey('passport-book-view'),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  pageLabel,
                  key: const ValueKey('passport-page-label'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${_currentIndex + 1} / $_pageCount',
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: (details) {
                        if (details.localPosition.dx >
                            constraints.maxWidth / 2) {
                          _turnForward();
                        } else {
                          _turnBack();
                        }
                      },
                      child: ClipRect(child: _buildPageStack()),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey('passport-previous-button'),
                  onPressed:
                      _currentIndex > 0 && !_isAnimating ? _turnBack : null,
                  icon: const Icon(Icons.chevron_left_rounded),
                  label: const Text('Önceki'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textMain,
                    disabledForegroundColor: AppColors.textMuted.withValues(
                      alpha: 0.82,
                    ),
                    side: BorderSide(
                      color: AppColors.inputBorder.withValues(alpha: 0.5),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  key: const ValueKey('passport-next-button'),
                  onPressed:
                      _currentIndex < _pageCount - 1 && !_isAnimating
                          ? _turnForward
                          : null,
                  icon: const Icon(Icons.auto_stories_rounded),
                  label: const Text('Sayfayı Çevir'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: AppColors.inputFill,
                    disabledForegroundColor: AppColors.textMuted.withValues(
                      alpha: 0.9,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    textStyle: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPageStack() {
    if (!_isAnimating) {
      return RepaintBoundary(child: _pageAt(_currentIndex));
    }
    final targetIndex = _targetIndex;
    if (targetIndex == null || targetIndex < 0 || targetIndex >= _pageCount) {
      return RepaintBoundary(child: _pageAt(_currentIndex));
    }
    final currentPage = RepaintBoundary(child: _pageAt(_currentIndex));
    final targetPage = RepaintBoundary(child: _pageAt(targetIndex));
    return AnimatedBuilder(
      animation: _flipAnimation,
      builder: (context, _) {
        final progress = _flipAnimation.value;
        if (_forward) {
          return Stack(
            fit: StackFit.expand,
            children: [
              targetPage,
              _flippingSheet(angle: -math.pi * progress, front: currentPage),
            ],
          );
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            currentPage,
            _flippingSheet(angle: -math.pi * (1 - progress), front: targetPage),
          ],
        );
      },
    );
  }

  Widget _flippingSheet({required double angle, required Widget front}) {
    final showFront = math.cos(angle) >= 0;
    final face =
        showFront
            ? front
            : Transform(
              alignment: Alignment.center,
              transform: Matrix4.rotationY(math.pi),
              child: const _PassportPaperBack(),
            );
    final transform =
        Matrix4.identity()
          ..setEntry(3, 2, 0.0016)
          ..rotateY(angle);
    return IgnorePointer(
      child: Transform(
        alignment: Alignment.centerLeft,
        transform: transform,
        child: DecoratedBox(
          decoration: BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: 0.18 + math.sin(angle.abs()) * 0.38,
                ),
                blurRadius: 14,
                offset: const Offset(8, 0),
              ),
            ],
          ),
          child: face,
        ),
      ),
    );
  }

  Widget _pageAt(int index) {
    if (index <= 0 || index > widget.collection.pages.length) {
      return PassportCoverPage(
        userName: widget.userName,
        stampCount: widget.collection.stampCount,
        regionCount: widget.collection.regionCount,
      );
    }
    return PassportRegionPageView(page: widget.collection.pages[index - 1]);
  }
}

class PassportCoverPage extends StatelessWidget {
  const PassportCoverPage({
    super.key,
    required this.userName,
    required this.stampCount,
    required this.regionCount,
  });

  final String userName;
  final int stampCount;
  final int regionCount;

  @override
  Widget build(BuildContext context) {
    final displayName = userName.trim().isEmpty ? 'KAŞİF' : userName.trim();
    return Container(
      key: const ValueKey('passport-cover-page'),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1030),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF3C275D), width: 2),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(19),
          border: Border.all(color: const Color(0xFF855B39), width: 1.4),
        ),
        padding: const EdgeInsets.all(9),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: const Color(0xFF855B39).withValues(alpha: 0.58),
            ),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(painter: _PassportGridPainter(dark: true)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 28, 16, 18),
                child: Column(
                  children: [
                    const Spacer(flex: 2),
                    SizedBox(
                      height: 116,
                      child: CustomPaint(
                        painter: _PassportEmblemPainter(),
                        child: Center(child: const _PassportEmblemCenter()),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'K E Ş F E D İ O',
                      style: TextStyle(
                        color: Color(0xFFF6B73C),
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2.6,
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'KEŞİF\nPASAPORTU',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 34,
                        height: 1.03,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.8,
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      '${displayName.toUpperCase()}  •  ${DateTime.now().year}',
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFB9A8D0),
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.8,
                      ),
                    ),
                    const Spacer(flex: 3),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('$stampCount PUL', style: _coverFooterStyle),
                        Text('$regionCount BÖLGE', style: _coverFooterStyle),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static const TextStyle _coverFooterStyle = TextStyle(
    color: Color(0xFF8F7BA7),
    fontSize: 11,
    fontWeight: FontWeight.w800,
    letterSpacing: 1,
  );
}

class _PassportEmblemCenter extends StatelessWidget {
  const _PassportEmblemCenter();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFFF47C58),
        border: Border.all(color: const Color(0xFFFFB13B), width: 3),
      ),
      alignment: Alignment.center,
      child: Container(
        width: 13,
        height: 13,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFFFFB13B),
          border: Border.all(color: Colors.white, width: 2),
        ),
      ),
    );
  }
}

class PassportRegionPageView extends StatelessWidget {
  const PassportRegionPageView({super.key, required this.page});

  final PassportRegionPage page;

  @override
  Widget build(BuildContext context) {
    final color = _colorFromHex(page.colorHex);
    return Container(
      key: ValueKey('passport-region-${page.areaId}'),
      decoration: BoxDecoration(
        color: const Color(0xFF211632),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withValues(alpha: 0.42), width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: Colors.black45,
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _PassportGridPainter())),
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 30),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.only(right: page.sealed ? 104 : 0),
                  child: Text(
                    page.regionName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textMain,
                      fontSize: 24,
                      height: 1.05,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  '${page.visitedPoiCount} / ${page.totalPoiCount} mekân',
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Stack(
                    children: [
                      Container(height: 8, color: Colors.white10),
                      FractionallySizedBox(
                        widthFactor: page.completion,
                        child: Container(
                          height: 8,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                color.withValues(alpha: 0.55),
                                color,
                                Colors.white.withValues(alpha: 0.85),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 7),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '%${page.completionPercent}',
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.78,
                  ),
                  itemCount: page.slots.length,
                  itemBuilder:
                      (context, index) => PassportStampWidget(
                        slot: page.slots[index],
                        regionColor: color,
                      ),
                ),
                if (page.slots.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(
                      child: Text(
                        'Bu bölgede henüz pul yuvası yok.',
                        style: TextStyle(color: AppColors.textMuted),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (page.sealed)
            Positioned(
              top: 10,
              right: 8,
              child: Transform.rotate(
                angle: -0.12,
                child: PassportCompletionSeal(page: page, color: color),
              ),
            ),
        ],
      ),
    );
  }
}

class PassportStampWidget extends StatelessWidget {
  const PassportStampWidget({
    super.key,
    required this.slot,
    required this.regionColor,
  });

  final PassportStampSlot slot;
  final Color regionColor;

  @override
  Widget build(BuildContext context) {
    if (!slot.isVisited) {
      return CustomPaint(
        key: ValueKey('passport-empty-${slot.poiId}'),
        painter: _DashedSlotPainter(),
        child: const Center(
          child: Text(
            '?',
            style: TextStyle(
              color: Color(0xFF786989),
              fontSize: 28,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      );
    }

    final rotationDegrees = (slot.poiId.hashCode.abs() % 7) - 3;
    return Transform.rotate(
      angle: rotationDegrees * math.pi / 180,
      child: Column(
        key: ValueKey('passport-stamp-${slot.poiId}'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: CustomPaint(
              painter: _StampPainter(color: regionColor),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned(
                    top: 15,
                    child: Icon(
                      _categoryIcon(slot.category),
                      color: regionColor,
                      size: 21,
                    ),
                  ),
                  Text(
                    slot.initial,
                    style: TextStyle(
                      color: regionColor,
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Positioned(
                    bottom: 12,
                    child: Text(
                      _formatDate(slot.visitedAt!),
                      style: TextStyle(
                        color: regionColor.withValues(alpha: 0.9),
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            slot.poiName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textMain,
              fontSize: 9,
              height: 1.1,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class PassportCompletionSeal extends StatelessWidget {
  const PassportCompletionSeal({
    super.key,
    required this.page,
    required this.color,
  });

  final PassportRegionPage page;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: ValueKey('passport-seal-${page.areaId}'),
      width: 112,
      height: 112,
      child: CustomPaint(
        painter: _CompletionSealPainter(
          color: color,
          circularText:
              '${page.regionName.toUpperCase()} • TAMAMLANDI • ${page.sealYear} • ${page.visitedPoiCount}/${page.totalPoiCount} • ',
        ),
      ),
    );
  }
}

class _PassportPaperBack extends StatelessWidget {
  const _PassportPaperBack();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF170F24),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF352444)),
      ),
      child: CustomPaint(painter: _PassportGridPainter(dark: true)),
    );
  }
}

class _PassportGridPainter extends CustomPainter {
  _PassportGridPainter({this.dark = false});

  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = (dark ? const Color(0xFF704D8A) : const Color(0xFF9B7AB8))
              .withValues(alpha: dark ? 0.06 : 0.045)
          ..strokeWidth = 0.7;
    const step = 22.0;
    for (double x = 0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PassportGridPainter oldDelegate) =>
      oldDelegate.dark != dark;
}

class _PassportEmblemPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const radius = 11.0;
    final dx = radius * 1.72;
    final dy = radius * 1.5;
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()..style = PaintingStyle.fill;
    for (var row = -2; row <= 2; row++) {
      for (var col = -2; col <= 2; col++) {
        if ((row.abs() + col.abs()) > 3) continue;
        final offset = Offset(
          center.dx + col * dx + (row.isOdd ? dx / 2 : 0),
          center.dy + row * dy,
        );
        final hot = row.abs() <= 1 && col.abs() <= 1;
        paint.color = hot ? const Color(0xFFDE3F87) : const Color(0xFF3A2855);
        canvas.drawPath(_hexPath(offset, radius), paint);
        canvas.drawPath(
          _hexPath(offset, radius),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.7
            ..color = Colors.white.withValues(alpha: 0.12),
        );
      }
    }
  }

  Path _hexPath(Offset center, double radius) {
    final path = Path();
    for (var i = 0; i < 6; i++) {
      final angle = math.pi / 3 * i - math.pi / 6;
      final point = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    return path..close();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _StampPainter extends CustomPainter {
  const _StampPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(4, 4, size.width - 8, size.height - 8);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(8)),
      Paint()..color = color.withValues(alpha: 0.12),
    );
    final border =
        Paint()
          ..color = color.withValues(alpha: 0.82)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6;
    _drawDashedRect(canvas, rect, border, dash: 5, gap: 3);
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      size.shortestSide * 0.27,
      Paint()
        ..color = color.withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      size.shortestSide * 0.22,
      Paint()
        ..color = color.withValues(alpha: 0.34)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _StampPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _DashedSlotPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = const Color(0xFF786989).withValues(alpha: 0.65)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3;
    _drawDashedRect(
      canvas,
      Rect.fromLTWH(4, 4, size.width - 8, size.height - 8),
      paint,
      dash: 6,
      gap: 5,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CompletionSealPainter extends CustomPainter {
  const _CompletionSealPainter({
    required this.color,
    required this.circularText,
  });

  final Color color;
  final String circularText;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 7;
    final ink =
        Paint()
          ..color = color.withValues(alpha: 0.82)
          ..style = PaintingStyle.stroke;
    ink.strokeWidth = 2.2;
    canvas.drawCircle(center, radius, ink);
    ink.strokeWidth = 1;
    canvas.drawCircle(center, radius - 8, ink);
    canvas.drawCircle(center, radius - 25, ink);
    _drawCircularText(canvas, center, radius - 4);

    final percent = TextPainter(
      text: TextSpan(
        text: '100%',
        style: TextStyle(
          color: color.withValues(alpha: 0.9),
          fontSize: 22,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    percent.paint(
      canvas,
      center - Offset(percent.width / 2, percent.height / 2),
    );
  }

  void _drawCircularText(Canvas canvas, Offset center, double radius) {
    final characters = circularText.characters.toList();
    if (characters.isEmpty) return;
    final angleStep = math.pi * 2 / characters.length;
    for (var i = 0; i < characters.length; i++) {
      final angle = -math.pi / 2 + i * angleStep;
      final painter = TextPainter(
        text: TextSpan(
          text: characters[i],
          style: TextStyle(
            color: color.withValues(alpha: 0.92),
            fontSize: 6.2,
            fontWeight: FontWeight.w900,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(angle + math.pi / 2);
      painter.paint(canvas, Offset(-painter.width / 2, -radius));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _CompletionSealPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.circularText != circularText;
}

void _drawDashedRect(
  Canvas canvas,
  Rect rect,
  Paint paint, {
  required double dash,
  required double gap,
}) {
  final path =
      Path()..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(8)));
  for (final metric in path.computeMetrics()) {
    var distance = 0.0;
    while (distance < metric.length) {
      canvas.drawPath(
        metric.extractPath(distance, math.min(distance + dash, metric.length)),
        paint,
      );
      distance += dash + gap;
    }
  }
}

Color _colorFromHex(String hex) {
  final normalized = hex.replaceFirst('#', '');
  final value = int.tryParse(normalized, radix: 16) ?? 0x8B5CF6;
  return Color(0xFF000000 | value);
}

String _formatDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';

IconData _categoryIcon(PassportPoiCategory category) => switch (category) {
  PassportPoiCategory.historic => Icons.account_balance_rounded,
  PassportPoiCategory.nature => Icons.landscape_rounded,
  PassportPoiCategory.beach => Icons.beach_access_rounded,
  PassportPoiCategory.religious => Icons.mosque_rounded,
  PassportPoiCategory.pier => Icons.directions_boat_filled_rounded,
  PassportPoiCategory.museum => Icons.museum_rounded,
  PassportPoiCategory.food => Icons.restaurant_rounded,
  PassportPoiCategory.park => Icons.park_rounded,
  PassportPoiCategory.other => Icons.place_rounded,
};
