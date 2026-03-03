import 'package:flutter/material.dart';

import '../../../../app/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/repositories/auth_repository.dart';
import '../../domain/exceptions/auth_flow_exception.dart';
import '../widgets/auth_field.dart';
import '../widgets/auth_footer.dart';
import '../widgets/auth_scaffold.dart';
import '../widgets/primary_button.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  AuthRepository? _authRepository;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submitLogin() async {
    FocusScope.of(context).unfocus();

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showMessage('E-posta ve şifre zorunludur.');
      return;
    }
    if (!email.contains('@')) {
      _showMessage('Geçerli bir e-posta adresi girin.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final result = await (_authRepository ??= AuthRepository()).signInAndSync(
        email: email,
        password: password,
      );
      if (!mounted) return;

      if (result.status == SignInStatus.emailNotVerified) {
        _showMessage(result.message ?? 'E-posta doğrulanmamış.');
        return;
      }
      Navigator.pushReplacementNamed(context, AppRouter.home);
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
      title: "Exploria'ya Hoş Geldin",
      subtitle: 'Yeni maceran seni bekliyor',
      titleFontSize: 33,
      subtitleFontSize: 15,
      footer: AuthFooter(
        text: 'Yolculuğa yeni mi başlıyorsun?',
        actionText: 'Loncaya Katıl',
        textFontSize: 14,
        actionFontSize: 15,
        onTap: () => Navigator.pushNamed(context, AppRouter.signUp),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () {},
              child: const Text(
                'Şifremi unuttum?',
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          PrimaryButton(
            text: 'KEŞFE BAŞLA',
            icon: Icons.rocket_launch_outlined,
            fontSize: 15,
            isLoading: _isLoading,
            onPressed: _submitLogin,
          ),
        ],
      ),
    );
  }
}
