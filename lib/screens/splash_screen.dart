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
            Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: AppColors.accent.withOpacity(0.15),
                    blurRadius: 40,
                    spreadRadius: 8,
                  ),
                ],
              ),
              child: Image.asset('assets/images/sail_logo.png', fit: BoxFit.contain),
            ),
            const SizedBox(height: 36),
            const BrandTitle(size: 38),
            const SizedBox(height: 10),
            const Text('SAIL · IS 14489',
              style: TextStyle(color: AppColors.text4, fontSize: 12, letterSpacing: 3, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 60),
            const SizedBox(
              width: 36, height: 36,
              child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.accent),
            ),
          ],
        ),
      ),
    );
  }
}
