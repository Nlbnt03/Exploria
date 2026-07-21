import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

const String kLocationDisclosureText =
    'Keşfedio, harita keşfi, serbest yürüyüş, sis açma, check-in ve çoklu oda canlı konum '
    'özelliklerini çalıştırmak için hassas konum verinizi toplar ve kullanır. '
    'Çoklu oda modunda konumunuz aynı odadaki kullanıcılarla paylaşılabilir. '
    'Arka plan takibini etkinleştirirseniz, uygulama kapalıyken veya ekran '
    'kilitliyken de konumunuz kullanılabilir. Devam ederek konum verinizin bu '
    'amaçlarla kullanılmasına izin vermiş olursunuz.';

Future<bool> showLocationDisclosureDialog(BuildContext context) async {
  if (Platform.isIOS) return true;
  final accepted = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder:
        (ctx) => AlertDialog(
          backgroundColor: AppColors.bgBottom,
          insetPadding: const EdgeInsets.symmetric(horizontal: 22),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(
              color: AppColors.inputBorder.withValues(alpha: 0.55),
            ),
          ),
          titlePadding: const EdgeInsets.fromLTRB(22, 22, 22, 8),
          contentPadding: const EdgeInsets.fromLTRB(22, 8, 22, 18),
          actionsPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          title: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.35),
                  ),
                ),
                child: const Icon(
                  Icons.location_on_rounded,
                  color: AppColors.primary,
                  size: 25,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Konum Verisi Kullanımı',
                  style: TextStyle(
                    color: AppColors.textMain,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          content: const SingleChildScrollView(
            child: _LocationDisclosureContent(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textMuted,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
              ),
              child: const Text(
                'Vazgeç',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Kabul ediyorum',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
  );

  return accepted == true;
}

class _LocationDisclosureContent extends StatelessWidget {
  const _LocationDisclosureContent();

  @override
  Widget build(BuildContext context) {
    const baseStyle = TextStyle(
      color: AppColors.textMuted,
      fontSize: 14.5,
      height: 1.42,
    );
    const strongStyle = TextStyle(
      color: AppColors.textMain,
      fontSize: 14.5,
      height: 1.42,
      fontWeight: FontWeight.w800,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: const TextSpan(
            style: baseStyle,
            children: [
              TextSpan(
                text:
                    'Keşfedio, harita keşfi, serbest yürüyüş, sis açma, check-in ve ',
              ),
              TextSpan(text: 'çoklu oda canlı konum', style: strongStyle),
              TextSpan(
                text:
                    ' özelliklerini çalıştırmak için hassas konum verinizi '
                    'toplar ve kullanır.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const _DisclosurePoint(
          icon: Icons.groups_rounded,
          textSpans: [
            TextSpan(text: 'Çoklu oda modunda ', style: strongStyle),
            TextSpan(
              text: 'konumunuz aynı odadaki kullanıcılarla paylaşılabilir.',
            ),
          ],
        ),
        const SizedBox(height: 10),
        const _DisclosurePoint(
          icon: Icons.lock_clock_rounded,
          textSpans: [
            TextSpan(text: 'Arka plan takibini ', style: strongStyle),
            TextSpan(
              text:
                  'etkinleştirirseniz, uygulama kapalıyken veya ekran '
                  'kilitliyken de konumunuz kullanılabilir.',
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.25),
            ),
          ),
          child: RichText(
            text: const TextSpan(
              style: baseStyle,
              children: [
                TextSpan(text: 'Devam ederek ', style: strongStyle),
                TextSpan(
                  text:
                      'konum verinizin bu amaçlarla kullanılmasına izin '
                      'vermiş olursunuz.',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DisclosurePoint extends StatelessWidget {
  const _DisclosurePoint({required this.icon, required this.textSpans});

  final IconData icon;
  final List<TextSpan> textSpans;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.primary, size: 18),
        const SizedBox(width: 9),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 14.5,
                height: 1.42,
              ),
              children: textSpans,
            ),
          ),
        ),
      ],
    );
  }
}
