import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

class AuthField extends StatelessWidget {
  const AuthField({
    super.key,
    required this.label,
    required this.hintText,
    required this.icon,
    this.controller,
    this.obscureText = false,
    this.suffix,
    this.keyboardType,
    this.enabled = true,
    this.labelFontSize = 16,
    this.inputFontSize = 16,
    this.hintFontSize = 16,
  });

  final String label;
  final String hintText;
  final IconData icon;
  final TextEditingController? controller;
  final bool obscureText;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final bool enabled;
  final double labelFontSize;
  final double inputFontSize;
  final double hintFontSize;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: AppColors.textMain,
            fontSize: labelFontSize,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: controller,
          enabled: enabled,
          obscureText: obscureText,
          keyboardType: keyboardType,
          style: TextStyle(color: AppColors.textMain, fontSize: inputFontSize),
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.inputFill,
            hintText: hintText,
            hintStyle: TextStyle(
              color: AppColors.textMuted,
              fontSize: hintFontSize,
            ),
            prefixIcon: Icon(icon, color: AppColors.primary),
            suffixIcon: suffix,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.inputBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.inputBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(
                color: AppColors.primary,
                width: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
