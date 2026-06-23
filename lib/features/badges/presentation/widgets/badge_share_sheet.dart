import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/badge_share_service.dart';
import '../../domain/badge_definitions.dart';

class BadgeShareSheet extends StatefulWidget {
  const BadgeShareSheet({super.key, required this.definition});

  final BadgeDefinition definition;

  static Future<void> show(BuildContext context, BadgeDefinition definition) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => BadgeShareSheet(definition: definition),
    );
  }

  @override
  State<BadgeShareSheet> createState() => _BadgeShareSheetState();
}

class _BadgeShareSheetState extends State<BadgeShareSheet> {
  final BadgeShareService _shareService = const BadgeShareService();
  bool _isSharing = false;

  Future<void> _share() async {
    if (_isSharing) return;
    setState(() => _isSharing = true);
    try {
      await _shareService.share(context, widget.definition);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is StateError
                ? error.message.toString()
                : 'Rozet paylaşılırken bir hata oluştu.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl = widget.definition.socialCardImageUrl;

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        decoration: const BoxDecoration(
          color: AppColors.bgBottom,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textMuted.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              widget.definition.name,
              style: const TextStyle(
                color: AppColors.textMain,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 16),
            AspectRatio(
              aspectRatio: 290 / 162,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child:
                    imageUrl == null
                        ? const _MissingSocialCard()
                        : Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const _MissingSocialCard(),
                        ),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: imageUrl == null || _isSharing ? null : _share,
              icon:
                  _isSharing
                      ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                      : const Icon(Icons.ios_share_rounded),
              label: Text(
                _isSharing ? 'Hazırlanıyor...' : 'Sosyal Medyada Paylaş',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MissingSocialCard extends StatelessWidget {
  const _MissingSocialCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.card,
      alignment: Alignment.center,
      child: const Text(
        'Bu rozet için paylaşım kartı bulunamadı.',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.textMuted),
      ),
    );
  }
}
