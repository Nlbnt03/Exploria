import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../widgets/auth_field.dart';
import '../widgets/auth_scaffold.dart';
import '../widgets/primary_button.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _emailController = TextEditingController();
  bool _isLoading = false;
  bool _emailSent = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendResetEmail() async {
    FocusScope.of(context).unfocus();

    final email = _emailController.text.trim();
    if (email.isEmpty) {
      _showMessage('Lütfen e-posta adresini gir.');
      return;
    }
    if (!email.contains('@')) {
      _showMessage('Geçerli bir e-posta adresi gir.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _emailSent = true;
      });
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      final message = switch (e.code) {
        'user-not-found' => 'Bu e-posta ile kayıtlı bir hesap bulunamadı.',
        'invalid-email' => 'Geçersiz e-posta adresi.',
        'too-many-requests' =>
          'Çok fazla deneme yaptın. Lütfen biraz bekle.',
        _ => 'Bir hata oluştu: ${e.message ?? e.code}',
      };
      _showMessage(message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showMessage('Beklenmeyen bir hata oluştu: $e');
    }
  }

  void _showMessage(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger != null) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
      return;
    }
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Şifreni Sıfırla',
      subtitle: 'Endişelenme, hemen halledelim',
      titleFontSize: 30,
      subtitleFontSize: 15,
      footer: const SizedBox.shrink(),
      child: _emailSent ? _buildSuccessContent() : _buildFormContent(),
    );
  }

  Widget _buildFormContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Hesabına bağlı e-posta adresini gir. Sana şifre sıfırlama bağlantısı göndereceğiz.',
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 14,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 20),
        AuthField(
          label: 'E-posta Adresi',
          hintText: 'explorer@world.com',
          icon: Icons.email_outlined,
          keyboardType: TextInputType.emailAddress,
          controller: _emailController,
          enabled: !_isLoading,
          labelFontSize: 14,
          inputFontSize: 14,
          hintFontSize: 14,
        ),
        const SizedBox(height: 20),
        PrimaryButton(
          text: 'SIFIRLAMA LİNKİ GÖNDER',
          icon: Icons.send_rounded,
          fontSize: 14,
          isLoading: _isLoading,
          onPressed: _sendResetEmail,
        ),
      ],
    );
  }

  Widget _buildSuccessContent() {
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(
            Icons.mark_email_read_rounded,
            color: AppColors.primary,
            size: 36,
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'E-posta Gönderildi!',
          style: TextStyle(
            color: AppColors.textMain,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          '${_emailController.text.trim()} adresine şifre sıfırlama bağlantısı gönderdik.\n\nE-postanı kontrol et ve bağlantıya tıklayarak yeni şifreni belirle.',
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 14,
            height: 1.6,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: OutlinedButton.icon(
            onPressed: () {
              setState(() => _emailSent = false);
            },
            icon: const Icon(Icons.refresh_rounded),
            label: const Text(
              'Tekrar Gönder',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.primary, AppColors.secondary],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: ElevatedButton.icon(
              onPressed: () {
                if (Navigator.canPop(context)) {
                  Navigator.pop(context);
                }
              },
              icon: const Icon(Icons.login_rounded, color: Colors.white),
              label: const Text(
                'Giriş Sayfasına Dön',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: ElevatedButton.styleFrom(
                elevation: 0,
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
