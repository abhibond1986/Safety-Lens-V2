import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'services/local_db.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocalDB.init();
  runApp(const SafetyLensApp());
}

class AppColors {
  // Dark theme palette
  static const bg = Color(0xFF0A0E1A);
  static const bg2 = Color(0xFF0F1629);
  static const card = Color(0xFF131A2E);
  static const card2 = Color(0xFF1C2540);
  static const card3 = Color(0xFF242D4A);
  static const border = Color(0xFF2A4570);
  static const text1 = Color(0xFFF1F5F9);
  static const text2 = Color(0xFFCBD5E1);
  static const text3 = Color(0xFF94A3B8);
  static const text4 = Color(0xFF64748B);
  static const accent = Color(0xFF2196F3);
  static const accentDark = Color(0xFF1976D2);
  static const red = Color(0xFFEF4444);
  static const crit = Color(0xFFDC2626);
  static const amber = Color(0xFFF59E0B);
  static const green = Color(0xFF10B981);
  static const cyan = Color(0xFF00BCD4);
  static const purple = Color(0xFF8B5CF6);
}

class SafetyLensApp extends StatefulWidget {
  const SafetyLensApp({super.key});
  @override
  State<SafetyLensApp> createState() => _SafetyLensAppState();
}

class _SafetyLensAppState extends State<SafetyLensApp> {
  ThemeMode _themeMode = ThemeMode.dark;

  void toggleTheme() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    });
  }

  @override
  Widget build(BuildContext context) {
    final dark = ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.accent,
        surface: AppColors.card,
      ),
      textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
      cardColor: AppColors.card,
      dividerColor: AppColors.border,
    );

    final light = ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: const Color(0xFFF8FAFC),
      colorScheme: const ColorScheme.light(
        primary: AppColors.accentDark,
        surface: Colors.white,
      ),
      textTheme: GoogleFonts.interTextTheme(ThemeData.light().textTheme),
      cardColor: Colors.white,
    );

    return MaterialApp(
      title: 'Safety Lens',
      debugShowCheckedModeBanner: false,
      theme: light,
      darkTheme: dark,
      themeMode: _themeMode,
      home: SplashScreen(toggleTheme: toggleTheme),
    );
  }
}

class BrandTitle extends StatelessWidget {
  final double size;
  const BrandTitle({super.key, this.size = 19});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ShaderMask(
          shaderCallback: (b) => const LinearGradient(
            colors: [Color(0xFF2196F3), Color(0xFF00BCD4)],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ).createShader(b),
          child: Text('Safety',
            style: GoogleFonts.merriweather(
              fontSize: size, fontWeight: FontWeight.w700, color: Colors.white,
              letterSpacing: 0.5,
            ),
          ),
        ),
        ShaderMask(
          shaderCallback: (b) => const LinearGradient(
            colors: [Color(0xFFF59E0B), Color(0xFFEF4444)],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ).createShader(b),
          child: Text(' Lens',
            style: GoogleFonts.merriweather(
              fontSize: size, fontWeight: FontWeight.w700, color: Colors.white,
              letterSpacing: 0.5, fontStyle: FontStyle.italic,
            ),
          ),
        ),
      ],
    );
  }
}

class SailLogoTile extends StatelessWidget {
  final double size;
  const SailLogoTile({super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size, height: size,
      padding: EdgeInsets.all(size * 0.08),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(size * 0.22),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Image.asset('assets/images/sail_logo.png', fit: BoxFit.contain),
    );
  }
}
