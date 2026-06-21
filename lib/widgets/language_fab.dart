// lib/widgets/language_fab.dart
//
// Floating language selector button — visible on every screen.
// Add to HomeScreen's Scaffold as a floatingActionButton.
//
// Usage in home_screen.dart:
//   Scaffold(
//     floatingActionButton: const LanguageFab(),
//     floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
//     body: ...,
//     bottomNavigationBar: ...,
//   )

import 'package:flutter/material.dart';
import '../main.dart';

class LanguageFab extends StatefulWidget {
  const LanguageFab({super.key});
  @override
  State<LanguageFab> createState() => _LanguageFabState();
}

class _LanguageFabState extends State<LanguageFab>
    with SingleTickerProviderStateMixin {
  bool _open = false;
  late AnimationController _ctrl;
  late Animation<double> _expand;

  static const _langs = [
    {'code': 'en', 'label': 'EN', 'name': 'English'},
    {'code': 'hi', 'label': 'HI', 'name': 'Hindi'},
    {'code': 'bn', 'label': 'BN', 'name': 'Bengali'},
    {'code': 'or', 'label': 'OR', 'name': 'Odia'},
  ];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200));
    _expand = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  void _toggle() {
    setState(() => _open = !_open);
    _open ? _ctrl.forward() : _ctrl.reverse();
  }

  Future<void> _select(String code) async {
    await LocaleService().setLocale(Locale(code));
    setState(() => _open = false);
    _ctrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final sl = SL.of(context);
    final current = LocaleService().locale.languageCode;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Language options — slide up when open
        ...List.generate(_langs.length, (i) {
          final lang = _langs[i];
          final isSelected = lang['code'] == current;
          return ScaleTransition(
            scale: _expand,
            child: FadeTransition(
              opacity: _expand,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GestureDetector(
                  onTap: () => _select(lang['code']!),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Label pill
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: isSelected
                            ? AppColors.accent
                            : sl.card2,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isSelected
                              ? AppColors.accent
                              : sl.border,
                            width: 1.5),
                          boxShadow: [BoxShadow(
                            color: Colors.black.withOpacity(0.15),
                            blurRadius: 8,
                            offset: const Offset(0, 2))]),
                        child: Text(lang['name']!,
                          style: TextStyle(
                            color: isSelected ? Colors.white : sl.text1,
                            fontSize: 12,
                            fontWeight: FontWeight.w600))),
                      const SizedBox(width: 8),
                      // Circle indicator
                      Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSelected
                            ? AppColors.accent
                            : sl.card,
                          border: Border.all(
                            color: isSelected
                              ? AppColors.accent
                              : sl.border,
                            width: 1.5),
                          boxShadow: [BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 6)]),
                        child: Center(child: Text(
                          lang['label']!,
                          style: TextStyle(
                            color: isSelected ? Colors.white : sl.text2,
                            fontSize: 13,
                            fontWeight: FontWeight.w700)))),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).reversed.toList(),

        const SizedBox(height: 4),

        // Main FAB button
        GestureDetector(
          onTap: _toggle,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 52, height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: _open
                ? null
                : const LinearGradient(
                    colors: [AppColors.accent, AppColors.cyan],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight),
              color: _open ? sl.card2 : null,
              border: Border.all(
                color: _open ? AppColors.accent : Colors.transparent,
                width: 1.5),
              boxShadow: [BoxShadow(
                color: AppColors.accent.withOpacity(_open ? 0.1 : 0.35),
                blurRadius: 16,
                offset: const Offset(0, 4))]),
            child: Center(child: _open
              ? Icon(Icons.close_rounded,
                  color: sl.text1, size: 22)
              : const Icon(Icons.language_rounded,
                  color: Colors.white, size: 24)),
          ),
        ),
      ],
    );
  }
}
