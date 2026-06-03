import 'dart:async';
import 'package:flutter/material.dart';
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
    with TickerProviderStateMixin {
  late AnimationController _fadeCtrl;
  late AnimationController _pulseCtrl;
  late AnimationController _progressCtrl;
  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;
  late Animation<double> _pulseAnim;
  late Animation<double> _progressAnim;

  // Fluorescent green
  static const Color _neonGreen = Color(0xFF39FF14);
  static const Color _neonGreenDim = Color(0xFF22C55E);

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this,
      duration: const Duration(milliseconds: 900));
    _pulseCtrl = AnimationController(vsync: this,
      duration: const Duration(milliseconds: 2200))..repeat(reverse: true);
    _progressCtrl = AnimationController(vsync: this,
      duration: const Duration(milliseconds: 2500));

    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _scaleAnim = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOutBack));
    _pulseAnim = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _progressAnim = CurvedAnimation(parent: _progressCtrl,
      curve: Curves.easeInOut);

    _fadeCtrl.forward();
    _progressCtrl.forward();

    Timer(const Duration(milliseconds: 2700), () async {
      final user = await LocalDB.getCurrentUser();
      if (!mounted) return;
      Navigator.pushReplacement(context, PageRouteBuilder(
        pageBuilder: (_, a, __) => user != null
            ? HomeScreen(toggleTheme: widget.toggleTheme)
            : LoginScreen(toggleTheme: widget.toggleTheme),
        transitionsBuilder: (_, a, __, child) =>
            FadeTransition(opacity: a, child: child),
        transitionDuration: const Duration(milliseconds: 500),
      ));
    });
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _pulseCtrl.dispose();
    _progressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg, // dark #0A0E1A
      body: Stack(children: [
        // Ambient orbs
        _ambientOrb(Alignment.topLeft, AppColors.accent, 0.07),
        _ambientOrb(Alignment.bottomRight, const Color(0xFF8B5CF6), 0.05),

        // Main glass card
        Center(
          child: FadeTransition(
            opacity: _fadeAnim,
            child: ScaleTransition(scale: _scaleAnim, child: _card()),
          ),
        ),
      ]),
    );
  }

  Widget _ambientOrb(Alignment align, Color color, double opacity) =>
    Positioned.fill(
      child: Align(alignment: align,
        child: AnimatedBuilder(
          animation: _pulseAnim,
          builder: (_, __) => Container(
            width: 320, height: 320,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                color.withOpacity(opacity * _pulseAnim.value),
                Colors.transparent,
              ]),
            ),
          ),
        ),
      ),
    );

  Widget _card() => Container(
    width: 280,
    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 44),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.04),
      borderRadius: BorderRadius.circular(32),
      border: Border.all(color: Colors.white.withOpacity(0.08), width: 1),
      boxShadow: [
        BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 40),
        BoxShadow(color: _neonGreen.withOpacity(0.04), blurRadius: 60, spreadRadius: 8),
      ],
    ),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      // Pulsing logo ring with green glow
      AnimatedBuilder(
        animation: _pulseAnim,
        builder: (_, child) => Container(
          width: 120, height: 120,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withOpacity(0.05),
            border: Border.all(
              color: _neonGreenDim.withOpacity(0.3 + 0.25 * _pulseAnim.value),
              width: 1.5),
            boxShadow: [
              BoxShadow(
                color: _neonGreen.withOpacity(0.10 + 0.15 * _pulseAnim.value),
                blurRadius: 24 + 16 * _pulseAnim.value,
                spreadRadius: 0),
            ],
          ),
          child: child,
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Image.asset('assets/images/sail_logo.png', fit: BoxFit.contain),
        ),
      ),

      const SizedBox(height: 24),

      // Brand title
      const BrandTitle(size: 32),

      const SizedBox(height: 8),

      const Text('SAIL  ·  IS 14489  ·  AI SAFETY',
        style: TextStyle(color: AppColors.text4, fontSize: 9,
          letterSpacing: 2.5, fontWeight: FontWeight.w600)),

      const SizedBox(height: 30),

      // Fluorescent green progress bar
      AnimatedBuilder(
        animation: _progressAnim,
        builder: (_, __) {
          final v = _progressAnim.value;
          return Column(children: [
            // Track
            Container(
              width: 160, height: 3,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(3)),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  width: 160 * v,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    gradient: LinearGradient(
                      colors: [_neonGreenDim, _neonGreen]),
                    boxShadow: [
                      BoxShadow(
                        color: _neonGreen.withOpacity(0.7),
                        blurRadius: 8,
                        spreadRadius: 1),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              v < 0.4 ? 'Initializing...'
                : v < 0.75 ? 'Loading modules...'
                : 'Almost ready...',
              style: TextStyle(
                color: v > 0.5
                    ? _neonGreenDim.withOpacity(0.8)
                    : AppColors.text4,
                fontSize: 10, letterSpacing: 0.8),
            ),
          ]);
        },
      ),
    ]),
  );
}
