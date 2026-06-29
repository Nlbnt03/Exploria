import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/services/rewarded_ad_manager.dart';

class DailyRewardStrip extends ConsumerStatefulWidget {
  const DailyRewardStrip({super.key});

  @override
  ConsumerState<DailyRewardStrip> createState() => _DailyRewardStripState();
}

class _DailyRewardStripState extends ConsumerState<DailyRewardStrip> {
  static const int _maxAds = 3;

  int _adsWatched = 0;
  bool _isLoading = false;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    RewardedAdManager.instance.init();
    _loadAdCount();
  }

  Future<void> _loadAdCount() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _initialized = true);
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      if (!mounted) return;

      int watched = 0;
      if (doc.exists) {
        final data = doc.data()!;
        final today = _todayStr();
        final storedDate = (data['dailyAdsResetDate'] as String?) ?? '';

        if (storedDate == today) {
          watched = (data['dailyAdsWatched'] as num?)?.toInt() ?? 0;
        } else {
          // Day rolled over — reset in Firestore (fire-and-forget)
          unawaited(
            FirebaseFirestore.instance.collection('users').doc(uid).update({
              'dailyAdsWatched': 0,
              'dailyAdsResetDate': today,
            }),
          );
        }
      }

      setState(() {
        _adsWatched = watched;
        _initialized = true;
      });
    } catch (_) {
      if (mounted) setState(() => _initialized = true);
    }
  }

  static String _todayStr() {
    final n = DateTime.now();
    return '${n.year}-'
        '${n.month.toString().padLeft(2, '0')}-'
        '${n.day.toString().padLeft(2, '0')}';
  }

  Future<void> _onWatchTapped() async {
    if (_adsWatched >= _maxAds || _isLoading) return;

    setState(() => _isLoading = true);

    final result = await RewardedAdManager.instance.show();
    if (!mounted) return;

    if (result != RewardResult.success) {
      setState(() => _isLoading = false);
      if (result == RewardResult.notLoaded) {
        _snack('Reklam yüklenemedi, tekrar dene', isError: true);
      }
      return;
    }

    // User earned reward → Cloud Function applies XP + increments counter
    try {
      final response = await FirebaseFunctions.instance
          .httpsCallable('claimDailyAdReward')
          .call<Map<Object?, Object?>>({});
      if (!mounted) return;

      final data = response.data;
      if (data['success'] == true) {
        final newWatched = (data['watchedToday'] as num).toInt();
        setState(() {
          _adsWatched = newWatched;
          _isLoading = false;
        });
        _snack('+25 XP kazandın! 🎉');
      } else {
        setState(() => _isLoading = false);
        _snack('Ödül alınamadı, tekrar dene', isError: true);
      }
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _snack(
        e.code == 'resource-exhausted'
            ? 'Günlük limitin doldu'
            : 'Ödül alınamadı, tekrar dene',
        isError: true,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _snack('Ödül alınamadı, tekrar dene', isError: true);
    }
  }

  void _snack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor:
            isError ? const Color(0xFFD32F2F) : const Color(0xFF39B89B),
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) return const SizedBox.shrink();

    final canWatch = _adsWatched < _maxAds;

    return Container(
      height: 56,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0xFF18102E), Color(0xFF0E1D20)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF5BD9C4)
              .withValues(alpha: canWatch ? 0.40 : 0.15),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 10),
          // Gift icon badge
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              gradient: canWatch
                  ? const LinearGradient(
                      colors: [Color(0xFF5BD9C4), Color(0xFF39B89B)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
              color: canWatch
                  ? null
                  : Colors.white.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Center(
              child: Text('🎁', style: TextStyle(fontSize: 18)),
            ),
          ),
          const SizedBox(width: 10),
          // Label + dot indicator
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Günlük Ödül · +25 XP',
                  style: TextStyle(
                    color: canWatch
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.45),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: List.generate(_maxAds, (i) {
                    // dots fill left-to-right for remaining uses
                    final active = i < (_maxAds - _adsWatched);
                    return Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: active
                              ? const Color(0xFF5BD9C4)
                              : Colors.white.withValues(alpha: 0.18),
                        ),
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
          // Action button
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _buildButton(canWatch),
          ),
        ],
      ),
    );
  }

  Widget _buildButton(bool canWatch) {
    if (_isLoading) {
      return Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: const AlwaysStoppedAnimation(Color(0xFF5BD9C4)),
              ),
            ),
            const SizedBox(width: 6),
            const Text(
              'Yükleniyor…',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    if (!canWatch) {
      return Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: const Center(
          child: Text(
            'Yarın tekrar gel',
            style: TextStyle(
              color: Colors.white30,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: _onWatchTapped,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF5BD9C4), Color(0xFF39B89B)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF5BD9C4).withValues(alpha: 0.28),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.play_arrow_rounded, color: Colors.white, size: 16),
            SizedBox(width: 4),
            Text(
              'İzle',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
