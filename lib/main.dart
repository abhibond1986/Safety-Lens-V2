import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'services/locale_service.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'services/local_db.dart';
import 'services/sync_service.dart';
import 'screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocaleService().load();
  await LocalDB.init();
  await SyncService.init();
  SyncService.drainPendingQueue().catchError((_) => 0);
  runApp(const SafetyLensApp());
}

// ─── DESIGN TOKENS ────────────────────────────────────────────────────────────
class AppColors {
  static const bg     = darkBg;
  static const bg2    = darkBg2;
  static const card   = darkCard;
  static const card2  = darkCard2;
  static const card3  = darkCard3;
  static const border = darkBorder;
  static const text1  = Color(0xFFF1F5F9);
  static const text2  = Color(0xFFCBD5E1);
  static const text3  = Color(0xFF94A3B8);
  static const text4  = Color(0xFF64748B);

  static const accent     = Color(0xFF6C63FF);
  static const accentDark = Color(0xFF5A52E0);
  static const accentGlow = Color(0xFF8B83FF);
  static const cyan       = Color(0xFF00D4FF);
  static const purple     = Color(0xFFBB86FC);
  static const pink       = Color(0xFFFF6584);

  static const crit  = Color(0xFFFF3B3B);
  static const red   = Color(0xFFFF6B6B);
  static const amber = Color(0xFFFFB84C);
  static const green = Color(0xFF22C55E);

  static const darkBg     = Color(0xFF0D0D1A);
  static const darkBg2    = Color(0xFF13132B);
  static const darkCard   = Color(0xFF1A1A35);
  static const darkCard2  = Color(0xFF22224A);
  static const darkCard3  = Color(0xFF2A2A5A);
  static const darkBorder = Color(0xFF3A3A6A);

  static const lightBg     = Color(0xFFF0F0FF);
  static const lightBg2    = Color(0xFFE8E8FF);
  static const lightCard   = Color(0xFFFFFFFF);
  static const lightCard2  = Color(0xFFF5F4FF);
  static const lightBorder = Color(0xFFD0CFFF);
}

// ─── THEME HELPER ─────────────────────────────────────────────────────────────
class SL {
  final bool isDark;
  const SL(this.isDark);

  static SL of(BuildContext context) =>
      SL(Theme.of(context).brightness == Brightness.dark);

  Color get bg     => isDark ? AppColors.darkBg    : AppColors.lightBg;
  Color get bg2    => isDark ? AppColors.darkBg2   : AppColors.lightBg2;
  Color get card   => isDark ? AppColors.darkCard   : AppColors.lightCard;
  Color get card2  => isDark ? AppColors.darkCard2  : AppColors.lightCard2;
  Color get card3  => isDark ? AppColors.darkCard3  : const Color(0xFFECEBFF);
  Color get border => isDark ? AppColors.darkBorder : AppColors.lightBorder;
  Color get text1  => isDark ? const Color(0xFFF1F5F9) : const Color(0xFF1A1A3E);
  Color get text2  => isDark ? const Color(0xFFCBD5E1) : const Color(0xFF3A3A6A);
  Color get text3  => isDark ? const Color(0xFF94A3B8) : const Color(0xFF6B6B9A);
  Color get text4  => isDark ? const Color(0xFF64748B) : const Color(0xFF9898C0);
  Color get surface => isDark ? AppColors.darkCard  : Colors.white;

  List<Color> get bgGradient => isDark
      ? [const Color(0xFF0D0D1A), const Color(0xFF13132B)]
      : [const Color(0xFFF0F0FF), const Color(0xFFE8E8FF)];

  Gradient get cardGradient => isDark
      ? LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [AppColors.darkCard, AppColors.darkCard2])
      : LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Colors.white, const Color(0xFFF5F4FF)]);

  BoxShadow get cardShadow => BoxShadow(
      color: isDark
          ? Colors.black.withOpacity(0.4)
          : AppColors.accent.withOpacity(0.08),
      blurRadius: 20,
      offset: const Offset(0, 4));

  BoxShadow get glowShadow => BoxShadow(
      color: AppColors.accent.withOpacity(isDark ? 0.2 : 0.12),
      blurRadius: 24,
      spreadRadius: 0);
}

// ─── APP ──────────────────────────────────────────────────────────────────────
class SafetyLensApp extends StatefulWidget {
  const SafetyLensApp({super.key});
  @override
  State<SafetyLensApp> createState() => _SafetyLensAppState();
}

class _SafetyLensAppState extends State<SafetyLensApp> {
  ThemeMode _mode = ThemeMode.dark;

  void toggleTheme() =>
      setState(() => _mode = _mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);

  ThemeData _buildTheme(bool dark) {
    final base = dark ? ThemeData.dark() : ThemeData.light();
    return base.copyWith(
      brightness: dark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: dark ? AppColors.darkBg : AppColors.lightBg,
      colorScheme: (dark
              ? const ColorScheme.dark(
                  primary: AppColors.accent, surface: AppColors.darkCard)
              : const ColorScheme.light(
                  primary: AppColors.accent, surface: Colors.white))
          .copyWith(secondary: AppColors.cyan),
      textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(
        bodyColor: dark ? const Color(0xFFCBD5E1) : const Color(0xFF3A3A6A),
        displayColor: dark ? const Color(0xFFF1F5F9) : const Color(0xFF1A1A3E),
      ),
      cardColor: dark ? AppColors.darkCard : Colors.white,
      dividerColor: dark ? AppColors.darkBorder : AppColors.lightBorder,
      appBarTheme: AppBarTheme(
        backgroundColor: dark ? AppColors.darkBg2 : AppColors.lightBg2,
        elevation: 0,
        titleTextStyle: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: dark ? const Color(0xFFF1F5F9) : const Color(0xFF1A1A3E)),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: dark ? AppColors.darkBg2 : AppColors.lightBg,
        selectedItemColor: AppColors.accent,
        unselectedItemColor:
            dark ? const Color(0xFF64748B) : const Color(0xFF9898C0),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? AppColors.darkCard2 : const Color(0xFFF5F4FF),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
                color: dark ? AppColors.darkBorder : AppColors.lightBorder)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
                color: dark ? AppColors.darkBorder : AppColors.lightBorder)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.accent, width: 2)),
        labelStyle: TextStyle(
            color: dark ? const Color(0xFF94A3B8) : const Color(0xFF6B6B9A)),
        hintStyle: TextStyle(
            color: dark ? const Color(0xFF64748B) : const Color(0xFF9898C0)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 20),
        textStyle:
            const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      )),
      snackBarTheme: SnackBarThemeData(
          backgroundColor: dark ? AppColors.darkCard2 : Colors.white,
          contentTextStyle: TextStyle(
              color: dark
                  ? const Color(0xFFF1F5F9)
                  : const Color(0xFF1A1A3E))),
    );
  }

  // ── FIXED build() — was using => { instead of proper function body ────────
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: LocaleService(),
      builder: (context, _) {
        return MaterialApp(
          title: 'SAIL Safety Lens',
          debugShowCheckedModeBanner: false,
          locale: LocaleService().locale,
          supportedLocales: LocaleService.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          themeMode: _mode,
          theme: _buildTheme(false),
          darkTheme: _buildTheme(true),
          home: SplashScreen(onToggleTheme: toggleTheme),
        );
      },
    );
  }
}

// ─── SHARED WIDGETS ───────────────────────────────────────────────────────────
class BrandTitle extends StatelessWidget {
  final double size;
  const BrandTitle({super.key, this.size = 19});
  @override
  Widget build(BuildContext context) {
    final sl = SL.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          Text('SAIL ',
              style: GoogleFonts.poppins(
                  fontSize: size,
                  fontWeight: FontWeight.w900,
                  color: sl.isDark ? Colors.white : const Color(0xFF1A1A3E))),
          ShaderMask(
              shaderCallback: (b) => const LinearGradient(
                      colors: [AppColors.accent, AppColors.cyan])
                  .createShader(b),
              child: Text('Safety',
                  style: GoogleFonts.poppins(
                      fontSize: size,
                      fontWeight: FontWeight.w800,
                      color: Colors.white))),
          ShaderMask(
              shaderCallback: (b) => const LinearGradient(
                      colors: [AppColors.pink, AppColors.amber])
                  .createShader(b),
              child: Text(' Lens',
                  style: GoogleFonts.poppins(
                      fontSize: size,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      fontStyle: FontStyle.italic))),
        ]),
      ],
    );
  }
}

class BrandTagline extends StatelessWidget {
  const BrandTagline({super.key});
  @override
  Widget build(BuildContext context) {
    final sl = SL.of(context);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text('Safety Starts with Me',
          style: TextStyle(
              color: sl.text3,
              fontSize: 9,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5)),
      Text(' · powered by ', style: TextStyle(color: sl.text4, fontSize: 9)),
      ShaderMask(
          shaderCallback: (b) => const LinearGradient(
                  colors: [AppColors.accent, AppColors.cyan])
              .createShader(b),
          child: const Text('AI',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w800))),
    ]);
  }
}

class SailLogoTile extends StatelessWidget {
  final double size;
  const SailLogoTile({super.key, this.size = 40});
  @override
  Widget build(BuildContext context) => SizedBox(
      width: size,
      height: size,
      child: Image.asset('assets/images/sail_logo.png', fit: BoxFit.contain));
}

// ─── GLASSMORPHISM CARD ───────────────────────────────────────────────────────
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? radius;
  final double opacity;
  final List<BoxShadow>? shadows;
  final Gradient? gradient;
  final Border? border;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.radius,
    this.opacity = 0.06,
    this.shadows,
    this.gradient,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final sl = SL.of(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        gradient: gradient ?? sl.cardGradient,
        borderRadius: radius ?? BorderRadius.circular(16),
        border: border ??
            Border.all(color: sl.border.withOpacity(0.6), width: 1),
        boxShadow: shadows ?? [sl.cardShadow],
      ),
      child: child,
    );
  }
}

// ─── SEVERITY BADGE ───────────────────────────────────────────────────────────
class SeverityBadge extends StatelessWidget {
  final String severity;
  final bool small;
  const SeverityBadge(this.severity, {super.key, this.small = false});

  static Color color(String s) {
    switch (s.toUpperCase()) {
      case 'CRITICAL': return AppColors.crit;
      case 'HIGH':     return AppColors.red;
      case 'MEDIUM':   return AppColors.amber;
      default:         return AppColors.green;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = color(severity);
    final label = severity.toUpperCase();
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: small ? 6 : 10, vertical: small ? 2 : 4),
      decoration: BoxDecoration(
          color: c.withOpacity(0.15),
          border: Border.all(color: c.withOpacity(0.6)),
          borderRadius: BorderRadius.circular(20)),
      child: Text(
          small && label.length > 4 ? label.substring(0, 4) : label,
          style: TextStyle(
              color: c,
              fontSize: small ? 8 : 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5)),
    );
  }
}

// ─── GRADIENT BUTTON ──────────────────────────────────────────────────────────
class GradientButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final List<Color> colors;
  final bool loading;

  const GradientButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.colors = const [AppColors.accent, AppColors.cyan],
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
            gradient: onTap == null
                ? null
                : LinearGradient(colors: colors),
            color: onTap == null
                ? (SL.of(context).isDark
                    ? AppColors.darkCard2
                    : AppColors.lightBorder)
                : null,
            borderRadius: BorderRadius.circular(14),
            boxShadow: onTap == null
                ? []
                : [
                    BoxShadow(
                        color: colors.first.withOpacity(0.4),
                        blurRadius: 16,
                        offset: const Offset(0, 6))
                  ]),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (loading)
            const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
          else if (icon != null) ...[
            Icon(icon, size: 16, color: Colors.white),
            const SizedBox(width: 8),
          ],
          Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3)),
        ]),
      ),
    );
  }
}

// ─── NEON DIVIDER ─────────────────────────────────────────────────────────────
class NeonDivider extends StatelessWidget {
  final Color color;
  const NeonDivider({super.key, this.color = AppColors.accent});
  @override
  Widget build(BuildContext context) => Container(
      height: 1,
      decoration: BoxDecoration(
          gradient: LinearGradient(colors: [
        Colors.transparent,
        color.withOpacity(0.6),
        Colors.transparent
      ])));
}
