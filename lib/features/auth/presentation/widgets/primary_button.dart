import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.text,
    required this.icon,
    required this.onPressed,
    this.isLoading = false,
    this.fontSize = 18,
  });

  final String text;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool isLoading;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 58,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.primary, AppColors.secondary],
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: ElevatedButton.icon(
          onPressed: isLoading ? null : onPressed,
          icon:
              isLoading
                  ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                  : Icon(icon, color: Colors.white),
          label: Text(
            isLoading ? 'LÜTFEN BEKLEYİN' : text,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: fontSize,
              color: Colors.white,
            ),
          ),
          style: ElevatedButton.styleFrom(
            elevation: 0,
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ),
    );
  }
}
