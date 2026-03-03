import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../../app/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../services/multi_room_firestore_service.dart';
import 'waiting_room_screen.dart';

class CreateRoomScreenArgs {
  const CreateRoomScreenArgs({this.cityId = 'istanbul', this.initialRoomName});

  final String cityId;
  final String? initialRoomName;
}

class CreateRoomScreen extends StatefulWidget {
  const CreateRoomScreen({
    super.key,
    this.cityId = 'istanbul',
    this.initialRoomName,
  });

  final String cityId;
  final String? initialRoomName;

  @override
  State<CreateRoomScreen> createState() => _CreateRoomScreenState();
}

class _CreateRoomScreenState extends State<CreateRoomScreen> {
  final MultiRoomFirestoreService _service = MultiRoomFirestoreService();
  late final TextEditingController _roomNameController;

  bool _isCreating = false;
  late final String _cityId;

  @override
  void initState() {
    super.initState();
    _cityId = widget.cityId.trim().isEmpty ? 'istanbul' : widget.cityId;
    _roomNameController = TextEditingController(
      text: widget.initialRoomName ?? 'Yeni Kesif Odasi',
    );
  }

  @override
  void dispose() {
    _roomNameController.dispose();
    super.dispose();
  }

  Future<void> _createRoom() async {
    if (_isCreating) {
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Oturum bulunamadi. Tekrar giris yap.')),
      );
      return;
    }

    final roomName = _roomNameController.text.trim();
    if (roomName.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Oda adi bos olamaz.')));
      return;
    }

    setState(() => _isCreating = true);

    try {
      final roomId = await _service.createRoom(roomName, _cityId);
      if (!mounted) {
        return;
      }

      Navigator.pushReplacementNamed(
        context,
        AppRouter.waitingRoom,
        arguments: WaitingRoomScreenArgs(roomId: roomId),
      );
    } on Exception catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Oda olusturulamadi: $e')));
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBottom,
      appBar: AppBar(
        backgroundColor: AppColors.bgTop,
        foregroundColor: AppColors.textMain,
        title: const Text('Çoklu Oda Oluştur'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Coklu Oda Olustur',
                style: TextStyle(
                  color: AppColors.textMain,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Kesif baslamadan once lobi olusur. En az 2 kisi olunca host baslatir.',
                style: TextStyle(color: AppColors.textMuted),
              ),
              const SizedBox(height: 16),
              const Text(
                'Oda Adi',
                style: TextStyle(
                  color: AppColors.textMain,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _roomNameController,
                maxLength: 60,
                autofocus: true,
                style: const TextStyle(color: AppColors.textMain),
                decoration: InputDecoration(
                  hintText: 'Orn: Aksam GTU Kesif Ekibi',
                  hintStyle: const TextStyle(color: AppColors.textMuted),
                  filled: true,
                  fillColor: AppColors.inputFill,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.inputBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: AppColors.inputBorder.withValues(alpha: 0.8),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: AppColors.primary,
                      width: 1.6,
                    ),
                  ),
                ),
                onSubmitted: (_) => _createRoom(),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isCreating ? null : _createRoom,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child:
                      _isCreating
                          ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                          : const Text(
                            'Lobiyi Olustur',
                            style: TextStyle(fontWeight: FontWeight.w700),
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
