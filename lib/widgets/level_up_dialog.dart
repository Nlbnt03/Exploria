import 'package:flutter/material.dart';
import '../models/user_xp.dart';

class LevelUpDialog extends StatefulWidget {
  final UserTitle newTitle;

  const LevelUpDialog({super.key, required this.newTitle});

  static void show(BuildContext context, UserTitle title) {
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      transitionDuration: const Duration(milliseconds: 600),
      pageBuilder: (context, anim1, anim2) {
        return LevelUpDialog(newTitle: title);
      },
      transitionBuilder: (context, anim1, anim2, child) {
        return ScaleTransition(
          scale: CurvedAnimation(
            parent: anim1,
            curve: Curves.elasticOut,
          ),
          child: child,
        );
      },
    );
  }

  @override
  State<LevelUpDialog> createState() => _LevelUpDialogState();
}

class _LevelUpDialogState extends State<LevelUpDialog> with SingleTickerProviderStateMixin {
  late final AnimationController _glowController;
  late final Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _glowAnimation = Tween<double>(begin: 0.2, end: 0.8).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // To handle the static property helper for ui since we need colors
    // I will mock an empty userxp and copy just to get getters, or just recreate the logic

    Color titleColor = Colors.grey;
    String titleName = 'Yolcu';
    String titleEmoji = '🥾';
    
    switch (widget.newTitle) {
      case UserTitle.efsane:
        titleColor = Colors.red;
        titleName = 'Efsane';
        titleEmoji = '🌟';
        break;
      case UserTitle.ustaKasif:
        titleColor = Colors.amber;
        titleName = 'Usta Kaşif';
        titleEmoji = '🏛️';
        break;
      case UserTitle.seyyah:
        titleColor = const Color(0xFF7B2FBE);
        titleName = 'Seyyah';
        titleEmoji = '⚔️';
        break;
      case UserTitle.kasif:
        titleColor = Colors.blue;
        titleName = 'Kaşif';
        titleEmoji = '🧭';
        break;
      case UserTitle.gezgin:
        titleColor = Colors.green;
        titleName = 'Gezgin';
        titleEmoji = '🗺️';
        break;
      case UserTitle.yolcu:
        titleColor = Colors.grey;
        titleName = 'Yolcu';
        titleEmoji = '🥾';
        break;
    }

    return Material(
      color: Colors.transparent,
      child: Center(
        child: AnimatedBuilder(
          animation: _glowAnimation,
          builder: (context, child) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 60),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1040),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: titleColor.withValues(alpha: _glowAnimation.value),
                    blurRadius: 100,
                    spreadRadius: 20,
                  ),
                ],
              ),
              child: child,
            );
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                titleEmoji,
                style: const TextStyle(fontSize: 80),
              ),
              const SizedBox(height: 20),
              const Text(
                'SEVİYE ATLANDI!',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Yeni Unvan:\n$titleName',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: titleColor,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  shadows: [
                    Shadow(color: titleColor.withValues(alpha: 0.5), blurRadius: 10),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: titleColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  elevation: 10,
                ),
                child: const Text(
                  'Harika! 🎉',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
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
