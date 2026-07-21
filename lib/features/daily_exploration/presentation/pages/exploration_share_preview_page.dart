import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/services/daily_exploration_analytics.dart';
import '../../data/services/exploration_share_service.dart';
import '../../domain/models/daily_exploration.dart';
import '../widgets/exploration_share_card.dart';

class ExplorationSharePreviewPage extends StatefulWidget {
  const ExplorationSharePreviewPage({
    super.key,
    required this.exploration,
    required this.createMapSnapshot,
    this.initialMapSnapshot,
  });

  final DailyExploration exploration;
  final Future<Uint8List> Function() createMapSnapshot;
  final Uint8List? initialMapSnapshot;

  @override
  State<ExplorationSharePreviewPage> createState() =>
      _ExplorationSharePreviewPageState();
}

class _ExplorationSharePreviewPageState
    extends State<ExplorationSharePreviewPage> {
  final GlobalKey _shareCardKey = GlobalKey();
  final ExplorationShareService _shareService = const ExplorationShareService();
  final DailyExplorationAnalytics _analytics =
      const DailyExplorationAnalytics();

  Uint8List? _mapSnapshot;
  Object? _snapshotError;
  bool _isLoading = false;
  bool _isSharing = false;
  bool _terminalEventLogged = false;

  @override
  void initState() {
    super.initState();
    _mapSnapshot = widget.initialMapSnapshot;
    if (_mapSnapshot == null) {
      _loadSnapshot();
    }
  }

  Future<void> _loadSnapshot() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _snapshotError = null;
      });
    }
    try {
      final bytes = await widget.createMapSnapshot();
      if (!mounted) return;
      setState(() {
        _mapSnapshot = bytes;
        _isLoading = false;
      });
    } catch (error, stackTrace) {
      debugPrint(
        '[DailyShare] Kart görüntüsü oluşturulamadı: $error\n$stackTrace',
      );
      _analytics.failed(widget.exploration);
      if (!mounted) return;
      setState(() {
        _snapshotError = error;
        _isLoading = false;
      });
    }
  }

  Future<void> _captureAndShare(BuildContext buttonContext) async {
    if (_isSharing || _mapSnapshot == null) return;
    setState(() => _isSharing = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      final boundary =
          _shareCardKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null || !boundary.attached) {
        throw StateError('Paylaşım kartı henüz çizilmedi.');
      }
      final image = await boundary.toImage(pixelRatio: 3);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (byteData == null) {
        throw StateError('Paylaşım görseli oluşturulamadı.');
      }
      final pngBytes = byteData.buffer.asUint8List();
      if (!mounted || !buttonContext.mounted) return;
      final result = await _shareService.share(
        context: buttonContext,
        exploration: widget.exploration,
        pngBytes: pngBytes,
      );
      if (!mounted) return;
      _terminalEventLogged = true;
      if (result.status == ShareResultStatus.success) {
        _analytics.completed(widget.exploration);
      } else {
        _analytics.dismissed(widget.exploration);
      }
      Navigator.of(context).pop(result.status == ShareResultStatus.success);
    } catch (error) {
      _analytics.failed(widget.exploration);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Kart paylaşılamadı: $error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      setState(() => _isSharing = false);
    }
  }

  void _dismiss() {
    if (!_terminalEventLogged) {
      _terminalEventLogged = true;
      _analytics.dismissed(widget.exploration);
    }
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_isSharing) _dismiss();
      },
      child: Scaffold(
        backgroundColor: AppColors.bgBottom,
        appBar: AppBar(
          backgroundColor: AppColors.bgTop,
          foregroundColor: AppColors.textMain,
          automaticallyImplyLeading: false,
          leading: IconButton(
            onPressed: _isSharing ? null : _dismiss,
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Vazgeç',
          ),
          title: const Text('Keşif kartın'),
        ),
        body: SafeArea(
          child: Column(
            children: <Widget>[
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
                  child: Center(child: _buildPreview()),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
                child: Builder(
                  builder: (buttonContext) {
                    return FilledButton.icon(
                      onPressed:
                          _mapSnapshot == null || _isSharing
                              ? null
                              : () => _captureAndShare(buttonContext),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        minimumSize: const Size(double.infinity, 54),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      icon:
                          _isSharing
                              ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                              : const Icon(Icons.ios_share_rounded),
                      label: Text(_isSharing ? 'Hazırlanıyor…' : 'Paylaş'),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreview() {
    if (_isLoading) {
      return const Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          CircularProgressIndicator(color: AppColors.primary),
          SizedBox(height: 14),
          Text(
            'Harita görüntüsü hazırlanıyor…',
            style: TextStyle(color: AppColors.textMuted),
          ),
        ],
      );
    }
    if (_snapshotError != null || _mapSnapshot == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(
            Icons.broken_image_outlined,
            color: AppColors.textMuted,
            size: 44,
          ),
          const SizedBox(height: 12),
          const Text(
            'Harita görüntüsü oluşturulamadı.',
            style: TextStyle(color: AppColors.textMain),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _loadSnapshot,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Tekrar dene'),
          ),
        ],
      );
    }

    return AspectRatio(
      aspectRatio: 9 / 16,
      child: FittedBox(
        fit: BoxFit.contain,
        child: RepaintBoundary(
          key: _shareCardKey,
          child: SizedBox(
            width: ExplorationShareCard.logicalSize.width,
            height: ExplorationShareCard.logicalSize.height,
            child: ExplorationShareCard(
              exploration: widget.exploration,
              mapSnapshot: _mapSnapshot!,
            ),
          ),
        ),
      ),
    );
  }
}
