import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

class AuthFooter extends StatelessWidget {
  const AuthFooter({
    super.key,
    required this.text,
    required this.actionText,
    required this.onTap,
    this.textFontSize = 18,
    this.actionFontSize = 20,
  });

  final String text;
  final String actionText;
  final VoidCallback onTap;
  final double textFontSize;
  final double actionFontSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          text,
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: textFontSize,
            fontWeight: FontWeight.w500,
          ),
        ),
        TextButton(
          onPressed: onTap,
          child: Text(
            actionText,
            style: TextStyle(
              color: AppColors.primary,
              fontSize: actionFontSize,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
