import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/services/firestore_user_service.dart';

class EditProfilePage extends StatefulWidget {
  final Map<String, dynamic> initialData;
  final String uid;
  final VoidCallback? onSignOut;
  final bool isSigningOut;

  const EditProfilePage({
    super.key,
    required this.initialData,
    required this.uid,
    this.onSignOut,
    this.isSigningOut = false,
  });

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  static final RegExp _usernamePattern = RegExp(r'^[a-z0-9._-]{3,30}$');
  final FirestoreUserService _firestoreUserService = FirestoreUserService();

  late TextEditingController _nameController;
  late TextEditingController _surnameController;
  late TextEditingController _usernameController;
  late TextEditingController _emailController;

  bool _isSaving = false;
  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: (widget.initialData['name'] as String?)?.trim() ?? '',
    );
    _surnameController = TextEditingController(
      text: (widget.initialData['surname'] as String?)?.trim() ?? '',
    );
    _usernameController = TextEditingController(
      text: (widget.initialData['username'] as String?)?.trim() ?? '',
    );
    _emailController = TextEditingController(
      text: FirebaseAuth.instance.currentUser?.email ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _surnameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    final name = _nameController.text.trim();
    final surname = _surnameController.text.trim();
    final username = _usernameController.text.trim();

    if (name.isEmpty || username.isEmpty) {
      _showMessage('Ad ve kullanıcı adı zorunludur.');
      return;
    }
    if (username.length < 3) {
      _showMessage('Kullanıcı adı en az 3 karakter olmalı.');
      return;
    }
    if (!_usernamePattern.hasMatch(username.toLowerCase())) {
      _showMessage(
        'Kullanıcı adı sadece küçük harf, rakam, nokta, alt çizgi ve tire içerebilir.',
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      await _firestoreUserService.updateEditableProfile(
        uid: widget.uid,
        name: name,
        surname: surname,
        username: username,
      );
      await FirebaseAuth.instance.currentUser?.updateDisplayName(
        surname.isEmpty ? name : '$name $surname',
      );
      _showMessage('Profil başarıyla güncellendi.');
    } on FirebaseException catch (e) {
      if (e.code == 'username-already-in-use') {
        _showMessage('Bu kullanıcı adı zaten kullanımda.');
      } else {
        _showMessage('Hata: ${e.code}');
      }
    } catch (e) {
      _showMessage('Güncelleme başarısız: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _confirmDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder:
          (context) => AlertDialog(
            backgroundColor: const Color(0xFF1E1040),
            title: const Text(
              'Hesabı Sil',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
            ),
            content: const Text(
              'Hesabınızı silmek istediğinizden emin misiniz? Bu işlem geri alınamaz ve tüm verileriniz kalıcı olarak silinir.',
              style: TextStyle(color: Colors.white70, height: 1.5),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text(
                  'Vazgeç',
                  style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  'Sil',
                  style: TextStyle(color: Colors.redAccent),
                ),
              ),
            ],
          ),
    );

    if (confirmed == true && mounted) {
      await _deleteAccount();
    }
  }

  Future<void> _deleteAccount() async {
    setState(() => _isDeleting = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await _firestoreUserService.deleteUser(widget.uid);
        await user.delete();
      }
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/login',
          (route) => false,
        );
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        _showMessage(
          'Güvenlik nedeniyle tekrar giriş yapmanız gerekmektedir. Lütfen çıkış yapıp tekrar giriş yapın ve hesabı silmeyi tekrar deneyin.',
        );
      } else {
        _showMessage('Hata: ${e.message}');
      }
    } catch (e) {
      _showMessage('Hesap silme başarısız: $e');
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBottom,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: AppColors.textMain,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Profil Ayarları',
          style: TextStyle(
            color: AppColors.textMain,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _EditField(
              label: 'Ad',
              controller: _nameController,
              enabled: !_isSaving && !_isDeleting,
            ),
            const SizedBox(height: 12),
            _EditField(
              label: 'Soyad',
              controller: _surnameController,
              enabled: !_isSaving && !_isDeleting,
            ),
            const SizedBox(height: 12),
            _EditField(
              label: 'Kullanıcı Adı',
              controller: _usernameController,
              enabled: !_isSaving && !_isDeleting,
            ),
            const SizedBox(height: 12),
            _EditField(
              label: 'E-posta (değiştirilemez)',
              controller: _emailController,
              enabled: false,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _isSaving || _isDeleting ? null : _saveProfile,
                icon:
                    _isSaving
                        ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                        : const Icon(Icons.save_rounded, color: Colors.white),
                label: Text(
                  _isSaving ? 'Kaydediliyor...' : 'Profili Güncelle',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            if (widget.onSignOut != null) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed:
                      widget.isSigningOut || _isDeleting || _isSaving
                          ? null
                          : widget.onSignOut,
                  icon:
                      widget.isSigningOut
                          ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                          : const Icon(
                            Icons.logout_rounded,
                            color: Colors.white,
                          ),
                  label: Text(
                    widget.isSigningOut ? 'Çıkış yapılıyor...' : 'Çıkış Yap',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orangeAccent.withValues(
                      alpha: 0.85,
                    ),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 32),
            const Divider(color: AppColors.inputBorder),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed:
                    _isDeleting || _isSaving ? null : _confirmDeleteAccount,
                icon:
                    _isDeleting
                        ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                        : const Icon(
                          Icons.person_remove_rounded,
                          color: Colors.white,
                        ),
                label: Text(
                  _isDeleting ? 'Siliniyor...' : 'Hesabı Sil',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent.withValues(alpha: 0.85),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditField extends StatelessWidget {
  const _EditField({
    required this.label,
    required this.controller,
    required this.enabled,
  });

  final String label;
  final TextEditingController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textMain,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          enabled: enabled,
          style: const TextStyle(color: AppColors.textMain),
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.inputFill,
            hintStyle: const TextStyle(color: AppColors.textMuted),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.inputBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.inputBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: AppColors.primary,
                width: 1.5,
              ),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: AppColors.inputBorder.withValues(alpha: 0.5),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
