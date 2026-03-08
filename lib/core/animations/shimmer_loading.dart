import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Shimmer efektli dikdörtgen placeholder.
class ShimmerBox extends StatelessWidget {
  const ShimmerBox({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 12.0,
  });

  final double width;
  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}

/// Shimmer efektli yuvarlak placeholder (avatar vb.).
class ShimmerCircle extends StatelessWidget {
  const ShimmerCircle({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(size / 3.5),
      ),
    );
  }
}

/// Profil sayfasının shimmer iskelet görünümü.
class ProfileShimmer extends StatefulWidget {
  const ProfileShimmer({super.key});

  @override
  State<ProfileShimmer> createState() => _ProfileShimmerState();
}

class _ProfileShimmerState extends State<ProfileShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: const [
                Color(0x33FFFFFF),
                Color(0x88FFFFFF),
                Color(0x33FFFFFF),
              ],
              stops: [
                (_controller.value - 0.3).clamp(0.0, 1.0),
                _controller.value,
                (_controller.value + 0.3).clamp(0.0, 1.0),
              ],
            ).createShader(bounds);
          },
          blendMode: BlendMode.srcATop,
          child: child!,
        );
      },
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
        child: Column(
          children: [
            // App bar geri butonu + başlık
            Row(
              children: [
                const ShimmerBox(width: 42, height: 42),
                const SizedBox(width: 14),
                const ShimmerBox(width: 80, height: 22, borderRadius: 8),
              ],
            ),
            const SizedBox(height: 36),

            // Avatar
            const ShimmerCircle(size: 88),
            const SizedBox(height: 16),

            // İsim
            const ShimmerBox(width: 180, height: 26, borderRadius: 8),
            const SizedBox(height: 8),

            // Username
            const ShimmerBox(width: 120, height: 16, borderRadius: 6),
            const SizedBox(height: 28),

            // İstatistik kartı
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.inputBorder.withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _shimmerStat(),
                  Container(
                    width: 1,
                    height: 40,
                    color: AppColors.inputBorder.withValues(alpha: 0.2),
                  ),
                  _shimmerStat(),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Rozet kartları
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.inputBorder.withValues(alpha: 0.25),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const ShimmerBox(width: 22, height: 22, borderRadius: 6),
                      const SizedBox(width: 8),
                      const ShimmerBox(
                        width: 90,
                        height: 18,
                        borderRadius: 6,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _shimmerBadge(),
                  const SizedBox(height: 10),
                  _shimmerBadge(),
                  const SizedBox(height: 10),
                  _shimmerBadge(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _shimmerStat() {
    return const Column(
      children: [
        ShimmerBox(width: 24, height: 24, borderRadius: 6),
        SizedBox(height: 6),
        ShimmerBox(width: 36, height: 22, borderRadius: 6),
        SizedBox(height: 4),
        ShimmerBox(width: 52, height: 13, borderRadius: 4),
      ],
    );
  }

  Widget _shimmerBadge() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.inputFill.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        children: [
          ShimmerBox(width: 44, height: 44),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShimmerBox(width: 120, height: 15, borderRadius: 6),
                SizedBox(height: 6),
                ShimmerBox(width: 180, height: 13, borderRadius: 4),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
