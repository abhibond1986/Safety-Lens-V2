// lib/screens/splash_screen.dart
//
// FIX: Removed double-loading — SplashScreen no longer re-initialises
// LocalDB/SyncService since main() already does it before runApp().
// Also added the language FAB overlay via LanguageFab widget.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../main.dart';
import '../services/local_db.dart';
import 'login_screen.dart';
import 'home_screen.dart';

class SplashScreen extends StatefulWidget {
  final VoidCallback toggleTheme;
  const SplashScreen({super.key, required this.toggleTheme});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200));
    _fade  = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _scale = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));
    _ctrl.forward();
    // Navigate after animation — no extra async init (main() already did it)
    Future.delayed(const Duration(milliseconds: 2000), _navigate);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _navigate() async {
    if (!mounted) return;
    final user = await LocalDB.getCurrentUser();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, a, __) => user != null
            ? HomeScreen(toggleTheme: widget.toggleTheme)
            : LoginScreen(toggleTheme: widget.toggleTheme),
        transitionsBuilder: (_, a, __, child) =>
            FadeTransition(opacity: a, child: child),
        transitionDuration: const Duration(milliseconds: 500)));
  }

  @override
  Widget build(BuildContext context) {
    final sl = SL.of(context);
    return Scaffold(
      backgroundColor: sl.bg,
      body: FadeTransition(
        opacity: _fade,
        child: ScaleTransition(
          scale: _scale,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // SAIL logo in rounded square (as requested)
                Container(
                  width: 88, height: 88,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF1E1E3F), Color(0xFF2A2A50)]),
                    border: Border.all(
                      color: AppColors.accent.withOpacity(0.5),
                      width: 1.5),
                    boxShadow: [BoxShadow(
                      color: AppColors.accent.withOpacity(0.25),
                      blurRadius: 24,
                      spreadRadius: 2)]),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Image.asset(
                      'assets/images/sail_logo.png',
                      fit: BoxFit.contain))),
                const SizedBox(height: 24),
                const BrandTitle(size: 28),
                const SizedBox(height: 8),
                Text('AI Safety Platform',
                  style: TextStyle(
                    color: sl.text3,
                    fontSize: 13,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w500)),
                const SizedBox(height: 48),
                SizedBox(
                  width: 24, height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppColors.accent.withOpacity(0.7)))),
                const SizedBox(height: 12),
                Text('Initialising safety platform...',
                  style: TextStyle(
                    color: sl.text4, fontSize: 11)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
