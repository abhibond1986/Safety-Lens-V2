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

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Timer(const Duration(seconds: 2), () async {
      final user = await LocalDB.getCurrentUser();
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(
        builder: (_) => user != null
            ? HomeScreen(toggleTheme: widget.toggleTheme)
            : LoginScreen(toggleTheme: widget.toggleTheme),
      ));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SailLogoTile(size: 120),
            const SizedBox(height: 24),
            const BrandTitle(size: 32),
            const SizedBox(height: 8),
            Text('SAIL · IS 14489',
              style: TextStyle(color: AppColors.text4, fontSize: 11, letterSpacing: 2.5, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 48),
            const SizedBox(
              width: 32, height: 32,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.accent),
            ),
          ],
        ),
      ),
    );
  }
}
