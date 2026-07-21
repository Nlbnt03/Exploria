import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Shown once, before a new map is created, so the user picks whether this
/// session should run the fog-of-war system or behave like a plain walking
/// tracker. The choice is fixed for the lifetime of the map — see
/// `CampusMapController.fogEnabled`.
class ExplorationModePage extends StatefulWidget {
  const ExplorationModePage({super.key, required this.areaTitle});

  final String areaTitle;

  @override
  State<ExplorationModePage> createState() => _ExplorationModePageState();
}

class _ExplorationModePageState extends State<ExplorationModePage> {
  bool? _fogEnabled;

  void _submit() {
    final selected = _fogEnabled;
    if (selected == null) return;
    Navigator.pop(context, selected);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBottom,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back, color: AppColors.textMain),
              ),
              const SizedBox(height: 10),
              const Text(
                'Nasıl gezmek istersin?',
                style: TextStyle(
                  color: AppColors.textMain,
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.areaTitle,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 24),
              _ModeCard(
                emoji: '🌫️',
                title: 'Keşif Modu',
                subtitle:
                    'Harita sisle kaplı başlar. Gezdikçe sisi dağıt, '
                    'adım adım haritayı ortaya çıkar.',
                isSelected: _fogEnabled == true,
                onTap: () => setState(() => _fogEnabled = true),
              ),
              const SizedBox(height: 14),
              _ModeCard(
                emoji: '🚶',
                title: 'Yürüyüş Modu',
                subtitle:
                    'Sis yok — sade bir yürüyüş takibi. Rotanı kaydet, '
                    'yeni yerler bul, XP kazanmaya devam et.',
                isSelected: _fogEnabled == false,
                onTap: () => setState(() => _fogEnabled = false),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _fogEnabled == null ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    disabledBackgroundColor: AppColors.primary.withValues(
                      alpha: 0.35,
                    ),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Devam',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
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

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
  });

  final String emoji;
  final String title;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withValues(alpha: 0.14) : AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color:
                isSelected
                    ? AppColors.primary.withValues(alpha: 0.7)
                    : AppColors.inputBorder.withValues(alpha: 0.35),
            width: isSelected ? 1.4 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(emoji, style: const TextStyle(fontSize: 24)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppColors.textMain,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
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
