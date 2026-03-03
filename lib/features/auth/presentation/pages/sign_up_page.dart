import 'package:flutter/material.dart';

import '../../../../app/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/repositories/auth_repository.dart';
import '../../domain/exceptions/auth_flow_exception.dart';
import '../widgets/auth_field.dart';
import '../widgets/auth_footer.dart';
import '../widgets/auth_scaffold.dart';
import '../widgets/primary_button.dart';

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  static final RegExp _usernamePattern = RegExp(r'^[a-z0-9._-]{3,30}$');

  AuthRepository? _authRepository;
  final _nameController = TextEditingController();
  final _surnameController = TextEditingController();
  final _emailController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _surnameController.dispose();
    _emailController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submitSignUp() async {
    FocusScope.of(context).unfocus();

    final name = _nameController.text.trim();
    final surname = _surnameController.text.trim();
    final email = _emailController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    if (name.isEmpty ||
        surname.isEmpty ||
        email.isEmpty ||
        username.isEmpty ||
        password.isEmpty) {
      _showMessage('Tüm alanlar zorunludur.');
      return;
    }
    if (!email.contains('@')) {
      _showMessage('Geçerli bir e-posta adresi girin.');
      return;
    }
    if (password.length < 6) {
      _showMessage('Şifre en az 6 karakter olmalı.');
      return;
    }
    if (!_usernamePattern.hasMatch(username.toLowerCase())) {
      _showMessage(
        'Kullanıcı adı sadece küçük harf, rakam, nokta, alt çizgi ve tire içerebilir.',
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      await (_authRepository ??= AuthRepository()).signUp(
        name: name,
        surname: surname,
        username: username,
        email: email,
        password: password,
      );

      if (!mounted) return;
      _showMessage(
        'Kayıt tamamlandı. E-posta doğrulamasını tamamlayıp giriş yapın.',
      );
      Navigator.pushReplacementNamed(context, AppRouter.login);
    } on AuthFlowException catch (e) {
      if (!mounted) return;
      _showMessage(e.message);
    } catch (e) {
      if (!mounted) return;
      _showMessage('Beklenmeyen bir hata oluştu: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
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
      title: "Exploria'ya Katıl",
      subtitle: 'Kendi kaşif kimliğini oluştur',
      titleFontSize: 33,
      subtitleFontSize: 15,
      footer: AuthFooter(
        text: 'Zaten bir hesabın var mı?',
        actionText: 'Girişe Dön',
        textFontSize: 14,
        actionFontSize: 15,
        onTap: () {
          if (Navigator.canPop(context)) {
            Navigator.pop(context);
            return;
          }
          Navigator.pushReplacementNamed(context, AppRouter.login);
        },
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AuthField(
            label: 'Ad',
            hintText: 'Ahmet',
            icon: Icons.person_outline,
            controller: _nameController,
            enabled: !_isLoading,
            labelFontSize: 14,
            inputFontSize: 14,
            hintFontSize: 14,
          ),
          const SizedBox(height: 16),
          AuthField(
            label: 'Soyad',
            hintText: 'Yılmaz',
            icon: Icons.badge_outlined,
            controller: _surnameController,
            enabled: !_isLoading,
            labelFontSize: 14,
            inputFontSize: 14,
            hintFontSize: 14,
          ),
          const SizedBox(height: 16),
          AuthField(
            label: 'E-posta Adresi',
            hintText: 'ahmet@ornek.com',
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            controller: _emailController,
            enabled: !_isLoading,
            labelFontSize: 14,
            inputFontSize: 14,
            hintFontSize: 14,
          ),
          const SizedBox(height: 16),
          AuthField(
            label: 'Kullanıcı Adı',
            hintText: 'ahmety',
            icon: Icons.alternate_email_rounded,
            controller: _usernameController,
            enabled: !_isLoading,
            labelFontSize: 14,
            inputFontSize: 14,
            hintFontSize: 14,
          ),
          const SizedBox(height: 16),
          AuthField(
            label: 'Şifre',
            hintText: '••••••••',
            icon: Icons.lock_outline,
            obscureText: _obscurePassword,
            controller: _passwordController,
            enabled: !_isLoading,
            labelFontSize: 14,
            inputFontSize: 14,
            hintFontSize: 14,
            suffix: IconButton(
              onPressed:
                  _isLoading
                      ? null
                      : () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(height: 20),
          PrimaryButton(
            text: 'HESAP OLUŞTUR',
            icon: Icons.auto_awesome_outlined,
            fontSize: 15,
            isLoading: _isLoading,
            onPressed: _submitSignUp,
          ),
        ],
      ),
    );
  }
}
