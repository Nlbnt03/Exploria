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
  bool _kvkkAccepted = false;

  static const String _kvkkText = '''
KEŞFEDİO UYGULAMASI KİŞİSEL VERİLERİN İŞLENMESİNE İLİŞKİN AYDINLATMA METNİ VE AÇIK RIZA BEYANI

1. VERİ SORUMLUSU
Keşfedio ("Uygulama"), kişisel verilerinizin 6698 sayılı Kişisel Verilerin Korunması Kanunu ("KVKK") kapsamında veri sorumlusu sıfatıyla işlenmesinden sorumludur.

2. İŞLENEN KİŞİSEL VERİLERİNİZ
Uygulamamıza kayıt olmanız ve hizmetlerimizi kullanmanız kapsamında aşağıdaki kişisel verileriniz işlenmektedir:
• Kimlik Bilgileri: Ad, soyad, kullanıcı adı.
• İletişim Bilgileri: E-posta adresi.
• Konum Bilgileri: Uygulama içi harita, sis ("fog") mekaniği, çoklu oyuncu (multiplayer) modları ve konum tabanlı görevler için anlık GPS/konum veriniz.
• İşlem Güvenliği Bilgileri: Şifre, oturum bilgileri (IP adresi, cihaz bilgileri vb.).

3. KİŞİSEL VERİLERİN İŞLENME AMAÇLARI
Kişisel verileriniz aşağıdaki amaçlarla işlenmektedir:
• Kullanıcı kaydının oluşturulması ve hesap yönetimi süreçlerinin yürütülmesi,
• Uygulamanın temel işlevi olan "keşif ve sis açma" mekaniğinin çalışabilmesi için konumunuzun anlık olarak takip edilmesi,
• Çoklu oda (multiplayer) modlarında, konumunuzun aynı odadaki diğer oyuncularla eş zamanlı olarak paylaşılması,
• Uygulama içi iletişim, hata tespiti, destek hizmetleri ve güvenliğin sağlanması.

4. KİŞİSEL VERİLERİN AKTARILMASI
Kişisel verileriniz, yasal zorunluluklar haricinde ve hizmetin gerektirdiği bulut sunucu altyapıları (ör. Firebase) dışında üçüncü şahıslarla paylaşılmamaktadır. Çoklu oda modunu kullandığınızda, anlık konum bilginiz ve kullanıcı adınız yalnızca sizinle aynı odaya katılan diğer kullanıcılarla paylaşılır.

5. KİŞİSEL VERİLERİNİZİN İŞLENMESİNİN HUKUKİ SEBEBİ
Kişisel verileriniz, KVKK Madde 5/2(c) kapsamında "Bir sözleşmenin kurulması veya ifasıyla doğrudan doğruya ilgili olması" ve KVKK Madde 5/1 kapsamında verdiğiniz "Açık Rıza" hukuki sebeplerine dayalı olarak toplanmakta ve işlenmektedir. Özellikle anlık konum verisi ve diğer kullanıcılarla konum paylaşımı, bu açık rızaya istinaden gerçekleştirilir.

6. HAKLARINIZ
KVKK'nın 11. maddesi uyarınca; kişisel verilerinizin işlenip işlenmediğini öğrenme, işlenmişse bilgi talep etme, işlenme amacını öğrenme, yurt içinde/yurt dışında aktarıldığı kişileri bilme, eksik/yanlış işlenmişse düzeltilmesini isteme, silinmesini veya yok edilmesini talep etme haklarına sahipsiniz.

AÇIK RIZA BEYANI
Yukarıda yer alan "Aydınlatma Metni"ni okuduğumu, anladığımı ve Keşfedio uygulamasının temel mekaniklerinin (harita keşfi ve çoklu oyuncu modu) çalışabilmesi için kimlik, iletişim ve asıl olarak "Anlık Konum" verilerimin işlenmesine, kaydedilmesine ve çoklu odalarda diğer oyuncularla paylaşılmasına özgür irademle açık rıza gösterdiğimi kabul ve beyan ederim.
''';

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
    if (!_kvkkAccepted) {
      _showMessage("Kayıt olabilmek için KVKK metnini onaylamanız gerekmektedir.");
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
      _showVerificationDialog(email);
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

  void _showVerificationDialog(String email) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(
          children: [
            Icon(Icons.mark_email_read_outlined, color: AppColors.primary, size: 26),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Doğrulama Maili Gönderildi',
                style: TextStyle(
                  color: AppColors.textMain,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        content: RichText(
          text: TextSpan(
            style: const TextStyle(
              color: AppColors.textMain,
              fontSize: 14,
              height: 1.55,
            ),
            children: [
              TextSpan(text: '$email '),
              const TextSpan(
                text: 'adresine bir doğrulama maili gönderdik.\n\n',
              ),
              const TextSpan(
                text: '⚠️ Mail gelmedi mi? ',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const TextSpan(
                text: 'Spam / Gereksiz klasörünü kontrol etmeyi unutma.',
              ),
            ],
          ),
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.pushReplacementNamed(context, AppRouter.login);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Giriş Sayfasına Git',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
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

  void _showKvkkText() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bgBottom,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.8,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 20),
              width: 48,
              height: 5,
              decoration: BoxDecoration(
                color: AppColors.inputBorder,
                borderRadius: BorderRadius.circular(2.5),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'KVKK Aydınlatma Metni\nve Açık Rıza Beyanı',
                style: TextStyle(
                  color: AppColors.textMain,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  height: 1.3,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: Scrollbar(
                controller: scrollController,
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  children: const [
                    Text(
                      _kvkkText,
                      style: TextStyle(
                        color: AppColors.textMain,
                        fontSize: 14,
                        height: 1.6,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Anladım, Kapat',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: "Keşfedio'ya Katıl",
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
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: Checkbox(
                  value: _kvkkAccepted,
                  onChanged:
                      _isLoading
                          ? null
                          : (val) {
                            setState(() => _kvkkAccepted = val ?? false);
                          },
                  activeColor: AppColors.primary,
                  side: BorderSide(
                    color: AppColors.textMuted.withValues(alpha: 0.5),
                    width: 1.5,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: _showKvkkText,
                  child: Text.rich(
                    TextSpan(
                      text: "Kayıt olarak ",
                      style: TextStyle(
                        color: AppColors.textMuted.withValues(alpha: 0.9),
                        fontSize: 13,
                        height: 1.4,
                      ),
                      children: const [
                        TextSpan(
                          text: "KVKK Aydınlatma Metni ve Açık Rıza Beyanı'nı",
                          style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                        TextSpan(
                          text: " okuduğumu ve kabul ettiğimi onaylıyorum.",
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
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
