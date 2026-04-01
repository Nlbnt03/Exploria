import 'package:flutter/material.dart';
import 'weekly_quest.dart';

enum UserTitle {
  yolcu,
  gezgin,
  kasif,
  seyyah,
  ustaKasif,
  efsane
}

class UserXP {
  final int currentXP;
  final WeeklyQuests weeklyQuests;

  const UserXP({required this.currentXP, required this.weeklyQuests});

  UserTitle get currentTitle {
    if (currentXP >= 20000) return UserTitle.efsane;
    if (currentXP >= 9000) return UserTitle.ustaKasif;
    if (currentXP >= 4000) return UserTitle.seyyah;
    if (currentXP >= 1500) return UserTitle.kasif;
    if (currentXP >= 500) return UserTitle.gezgin;
    return UserTitle.yolcu;
  }

  String get titleName {
    switch (currentTitle) {
      case UserTitle.efsane:
        return 'Efsane';
      case UserTitle.ustaKasif:
        return 'Usta Kaşif';
      case UserTitle.seyyah:
        return 'Seyyah';
      case UserTitle.kasif:
        return 'Kaşif';
      case UserTitle.gezgin:
        return 'Gezgin';
      case UserTitle.yolcu:
        return 'Yolcu';
    }
  }
  
  String get titleEmoji {
    switch (currentTitle) {
      case UserTitle.efsane:
        return '🌟';
      case UserTitle.ustaKasif:
        return '🏛️';
      case UserTitle.seyyah:
        return '⚔️';
      case UserTitle.kasif:
        return '🧭';
      case UserTitle.gezgin:
        return '🗺️';
      case UserTitle.yolcu:
        return '🥾';
    }
  }

  Color get titleColor {
    switch (currentTitle) {
      case UserTitle.efsane:
        return const Color(0xFFFF1744); // Radiant Neon Red
      case UserTitle.ustaKasif:
        return const Color(0xFFF5A623); // Vibrant Amber/Gold
      case UserTitle.seyyah:
        return const Color(0xFFEC4899); // Neon Pink/Magenta
      case UserTitle.kasif:
        return Colors.blue; // Mavi uyumu korundu
      case UserTitle.gezgin:
        return const Color(0xFF10B981); // Emerald Green
      case UserTitle.yolcu:
        return const Color(0xFF94A3B8); // Cool Slate Gray
    }
  }

  int get xpForNextTitle {
    switch (currentTitle) {
      case UserTitle.efsane:
        return currentXP; // Max level reached
      case UserTitle.ustaKasif:
        return 20000;
      case UserTitle.seyyah:
        return 9000;
      case UserTitle.kasif:
        return 4000;
      case UserTitle.gezgin:
        return 1500;
      case UserTitle.yolcu:
        return 500;
    }
  }

  int get xpForCurrentTitle {
    switch (currentTitle) {
      case UserTitle.efsane:
        return 20000;
      case UserTitle.ustaKasif:
        return 9000;
      case UserTitle.seyyah:
        return 4000;
      case UserTitle.kasif:
        return 1500;
      case UserTitle.gezgin:
        return 500;
      case UserTitle.yolcu:
        return 0;
    }
  }

  int get xpToNext {
    if (currentTitle == UserTitle.efsane) return 0;
    return xpForNextTitle - currentXP;
  }

  double get progressPercentage {
    if (currentTitle == UserTitle.efsane) return 1.0;
    
    final xpInCurrentLevel = currentXP - xpForCurrentTitle;
    final xpRequiredForLevel = xpForNextTitle - xpForCurrentTitle;
    
    return (xpInCurrentLevel / xpRequiredForLevel).clamp(0.0, 1.0);
  }
}
