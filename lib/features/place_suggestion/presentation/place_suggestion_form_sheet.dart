import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../models/place_suggestion.dart';
import '../services/place_suggestion_service.dart';

const List<String> _kCategories = [
  'Kilise',
  'Sinagog',
  'Cami',
  'Tarihi Yapı',
  'Müze',
  'Diğer',
];

/// Bottom sheet form that lets the user fill in place suggestion details
/// after they have picked a pin on the map.
class PlaceSuggestionFormSheet extends StatefulWidget {
  const PlaceSuggestionFormSheet({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.mapAreaId,
    required this.onChangeLocation,
  });

  final double latitude;
  final double longitude;
  final String mapAreaId;

  /// Called when the user taps "Değiştir" — closes the sheet so they can
  /// pick a new pin on the map.
  final VoidCallback onChangeLocation;

  @override
  State<PlaceSuggestionFormSheet> createState() =>
      _PlaceSuggestionFormSheetState();
}

class _PlaceSuggestionFormSheetState
    extends State<PlaceSuggestionFormSheet> {
  bool _submitted = false;

  final PlaceSuggestionService _service = PlaceSuggestionService();

  Future<void> _handleSubmit(
    String name,
    String category,
    String description,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    final username =
        user?.displayName?.trim().isNotEmpty == true
            ? user!.displayName!.trim()
            : (user?.email?.split('@').first ?? 'Anonim');

    await _service.submitSuggestion(
      PlaceSuggestion(
        userId: user?.uid ?? '',
        username: username,
        latitude: widget.latitude,
        longitude: widget.longitude,
        name: name,
        category: category,
        description: description,
        mapAreaId: widget.mapAreaId,
      ),
    );

    if (mounted) {
      setState(() => _submitted = true);
      await Future<void>.delayed(const Duration(milliseconds: 1800));
      if (mounted) Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF130826),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: _submitted
          ? _SuccessView()
          : _FormView(
              latitude: widget.latitude,
              longitude: widget.longitude,
              mapAreaId: widget.mapAreaId,
              onChangeLocation: widget.onChangeLocation,
              onSubmit: _handleSubmit,
            ),
    );
  }
}

// ─── Success View ──────────────────────────────────────────────────────────────

class _SuccessView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 56),
          SizedBox(height: 16),
          Text(
            'Önerin gönderildi!',
            style: TextStyle(
              color: AppColors.textMain,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Admin inceleyip haritaya ekleyebilir.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ─── Form View ─────────────────────────────────────────────────────────────────

class _FormView extends StatefulWidget {
  const _FormView({
    required this.latitude,
    required this.longitude,
    required this.mapAreaId,
    required this.onChangeLocation,
    required this.onSubmit,
  });

  final double latitude;
  final double longitude;
  final String mapAreaId;
  final VoidCallback onChangeLocation;
  final Future<void> Function(String name, String category, String description)
      onSubmit;

  @override
  State<_FormView> createState() => _FormViewState();
}

class _FormViewState extends State<_FormView> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  String? _selectedCategory;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen bir kategori seçin.')),
      );
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      await widget.onSubmit(
        _nameController.text.trim(),
        _selectedCategory!,
        _descController.text.trim(),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gönderilirken bir hata oluştu: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lat = widget.latitude;
    final lng = widget.longitude;
    final latStr = '${lat.toStringAsFixed(4)}° ${lat >= 0 ? 'K' : 'G'}';
    final lngStr =
        '${lng.abs().toStringAsFixed(4)}° ${lng >= 0 ? 'D' : 'B'}';

    final canSubmit = !_isSubmitting && _selectedCategory != null;

    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 16),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textMuted.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // ── Location header ──────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF1E0F36),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppColors.inputBorder.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2E9688).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.location_on_rounded,
                        color: Color(0xFF2E9688),
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Konum işaretlendi',
                          style: TextStyle(
                            color: AppColors.textMain,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$latStr  $lngStr',
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      Navigator.of(context).pop();
                      widget.onChangeLocation();
                    },
                    child: const Text(
                      'Değiştir',
                      style: TextStyle(
                        color: Color(0xFF2E9688),
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── Mekan adı ─────────────────────────────────────────────────
            _Label('Mekan adı', required: true),
            const SizedBox(height: 8),
            _InputField(
              controller: _nameController,
              hint: 'Örn. Aya Yorgi Kilisesi',
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Mekan adı boş bırakılamaz.';
                }
                if (v.trim().length < 2) return 'En az 2 karakter olmalı.';
                return null;
              },
            ),

            const SizedBox(height: 20),

            // ── Kategori ──────────────────────────────────────────────────
            _Label('Kategori', required: true),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _kCategories
                  .map(
                    (cat) => _CategoryChip(
                      label: cat,
                      isSelected: _selectedCategory == cat,
                      color: _categoryColor(cat),
                      onTap: () => setState(() => _selectedCategory = cat),
                    ),
                  )
                  .toList(),
            ),

            const SizedBox(height: 20),

            // ── Neden önermelisin ─────────────────────────────────────────
            const _Label('Neden önermelisin?', required: false),
            const SizedBox(height: 8),
            _InputField(
              controller: _descController,
              hint:
                  'Bu yeri kısaca anlat — ne olduğunu, neden keşfedilmeye değer olduğunu…',
              maxLines: 4,
            ),

            const SizedBox(height: 24),

            // ── XP banner ─────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFD97706).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: const Color(0xFFD97706).withValues(alpha: 0.35),
                ),
              ),
              child: const Row(
                children: [
                  Icon(Icons.bolt_rounded, color: Color(0xFFD97706), size: 22),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        text: 'Önerin onaylanıp haritaya eklenirse ',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 13,
                        ),
                        children: [
                          TextSpan(
                            text: '+100 XP',
                            style: TextStyle(
                              color: Color(0xFFD97706),
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                          TextSpan(text: ' kazanırsın.'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── Submit button ─────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 54,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: canSubmit
                      ? const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [AppColors.primary, AppColors.secondary],
                        )
                      : null,
                  color: canSubmit
                      ? null
                      : AppColors.textMuted.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: ElevatedButton(
                  onPressed: canSubmit ? _handleSubmit : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    disabledBackgroundColor: Colors.transparent,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          'Admine Gönder',
                          style: TextStyle(
                            color: canSubmit
                                ? Colors.white
                                : AppColors.textMuted,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
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
}

// ─── Small helper widgets ──────────────────────────────────────────────────────

class _Label extends StatelessWidget {
  const _Label(this.text, {this.required = false});

  final String text;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          text,
          style: const TextStyle(
            color: AppColors.textMain,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
        if (required)
          const Text(
            ' *',
            style: TextStyle(color: AppColors.primary, fontSize: 14),
          ),
      ],
    );
  }
}

class _InputField extends StatelessWidget {
  const _InputField({
    required this.controller,
    required this.hint,
    this.maxLines = 1,
    this.validator,
  });

  final TextEditingController controller;
  final String hint;
  final int maxLines;
  final FormFieldValidator<String>? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      validator: validator,
      style: const TextStyle(color: AppColors.textMain, fontSize: 15),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 14),
        filled: true,
        fillColor: const Color(0xFF1E0F36),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:
              BorderSide(color: AppColors.inputBorder.withValues(alpha: 0.4)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:
              BorderSide(color: AppColors.inputBorder.withValues(alpha: 0.4)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.isSelected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color:
              isSelected ? color.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected
                ? color
                : AppColors.textMuted.withValues(alpha: 0.35),
            width: isSelected ? 1.8 : 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: isSelected ? color : AppColors.textMuted,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? color : AppColors.textMuted,
                fontWeight:
                    isSelected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Color _categoryColor(String category) {
  switch (category) {
    case 'Kilise':
      return const Color(0xFFEC4899);
    case 'Sinagog':
      return const Color(0xFF8B5CF6);
    case 'Cami':
      return const Color(0xFF10B981);
    case 'Tarihi Yapı':
      return const Color(0xFFF59E0B);
    case 'Müze':
      return const Color(0xFF3B82F6);
    default:
      return AppColors.textMuted;
  }
}
