// lib/screens/contractor_home_screen.dart
//
// Limited home screen for contractual employees.
// Only provides access to AI Scan and Near Miss sections.
// No login required. No LanguageFab (language is in UniversalAppBar).

import 'dart:ui';
import 'package:flutter/material.dart';
import '../main.dart';
import 'login_screen.dart';
import 'ai_scan_tab.dart';
import 'near_miss_tab.dart';

class ContractorHomeScreen extends StatefulWidget {
  final VoidCallback toggleTheme;
  const ContractorHomeScreen({super.key, required this.toggleTheme});

  @override
  State<ContractorHomeScreen> createState() => _ContractorHomeScreenState();
}

class _ContractorHomeScreenState extends State<ContractorHomeScreen> {
  int _tabIndex = 0;

  // Contractor user placeholder (no real login)
  final Map<String, dynamic> _contractorUser = {
    'name': 'Contractor',
    'username': 'contractor',
    'designation': 'Contractual Employee',
    'plant': '',
    'role': 'contractor',
  };

  void _exitToLogin() {
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, a, __) =>
            LoginScreen(toggleTheme: widget.toggleTheme),
        transitionsBuilder: (_, a, __, child) =>
            FadeTransition(opacity: a, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sl = SL.of(context);
    final isDark = sl.isDark;

    final tabs = <Widget>[
      // 0 — AI Scan
      AIScanTab(
        user: _contractorUser,
        toggleTheme: widget.toggleTheme,
        onSignOut: _exitToLogin,
        isDark: isDark,
      ),
      // 1 — Near Miss
      NearMissTab(
        user: _contractorUser,
        toggleTheme: widget.toggleTheme,
        onSignOut: _exitToLogin,
        isDark: isDark,
      ),
    ];

    return Scaffold(
      extendBody: true,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: sl.bgGradient,
          ),
        ),
        child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: sl.text1),
          onPressed: _exitToLogin,
          tooltip: 'Back to Login',
        ),
        title: Row(
          children: [
            Image.asset(
              'assets/images/app_icon.png',
              width: 28,
              height: 28,
              errorBuilder: (_, __, ___) => Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.accent),
                child: const Icon(Icons.shield, color: Colors.white, size: 14)),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SAIL Safety Lens',
                  style: TextStyle(
                    color: sl.text1,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'Contractor Access',
                  style: TextStyle(
                    color: AppColors.accent,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
              color: sl.text3,
              size: 20,
            ),
            onPressed: widget.toggleTheme,
          ),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: KeyedSubtree(
          key: ValueKey(_tabIndex),
          child: tabs[_tabIndex],
        ),
      ),
      bottomNavigationBar: _bottomNav(sl),
    ),
      ),
    );
  }

  Widget _bottomNav(SL sl) {
    final items = [
      _NavItem(Icons.document_scanner_outlined,
          Icons.document_scanner_rounded, 'AI Scan'),
      _NavItem(Icons.warning_amber_outlined,
          Icons.warning_amber_rounded, 'Near Miss'),
    ];

    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
      decoration: BoxDecoration(
        color: sl.glassColor,
        border: Border(
          top: BorderSide(color: sl.glassBorder, width: 0.5),
        ),
      ),
      child: SafeArea(
        child: SizedBox(
          height: 60,
          child: Row(
            children: List.generate(items.length, (i) {
              final sel = _tabIndex == i;
              final item = items[i];
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _tabIndex = i),
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 4),
                        decoration: BoxDecoration(
                          color: sel
                              ? AppColors.accent.withOpacity(0.15)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Icon(
                          sel ? item.activeIcon : item.icon,
                          size: 22,
                          color: sel ? AppColors.accent : sl.text4,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight:
                              sel ? FontWeight.w700 : FontWeight.w500,
                          color: sel ? AppColors.accent : sl.text4,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon, activeIcon;
  final String label;
  const _NavItem(this.icon, this.activeIcon, this.label);
}
