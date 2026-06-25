import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/local_db.dart';
import 'services/sync_service.dart';
import 'services/app_updater.dart';
import 'services/i18n.dart';  // ← ADDED: fixes "I18n not defined" error
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocaleService().load();
  await LocalDB.init();
  await SyncService.init();
  SyncService.drainPendingQueue().catchError((_) => 0);
  // Silent auto-update: checks GitHub releases and installs APK in background
  AppUpdater.init();
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

  // Vibrant accent palette — Image 3 style
  static const accent     = Color(0xFF7C4DFF);   // deep violet-purple
  static const accentDark = Color(0xFF6534E0);
  static const accentGlow = Color(0xFF9B6BFF);
  static const cyan       = Color(0xFF00BCD4);   // teal-cyan
  static const purple     = Color(0xFFE040FB);   // bright magenta-purple
  static const pink       = Color(0xFFFF4081);   // vivid pink

  static const crit  = Color(0xFFFF1744);
  static const red   = Color(0xFFFF5252);
  static const amber = Color(0xFFFFAB00);
  static const green = Color(0xFF00E676);

  // Dark mode — Glassmorphism deep purple-blue base
  static const darkBg     = Color(0xFF0F0C29);   // deep purple-black
  static const darkBg2    = Color(0xFF1A1735);   // slightly lighter
  static const darkCard   = Color(0xFF1E1B3A);   // glass card base
  static const darkCard2  = Color(0xFF272450);   // elevated glass
  static const darkCard3  = Color(0xFF302B63);   // top-most surface
  static const darkBorder = Color(0xFF3D3870);   // subtle purple separator

  // Light mode — clean white with very subtle tint
  static const lightBg     = Color(0xFFF8F8F8);  // near-white, no tint
  static const lightBg2    = Color(0xFFEFEFEF);  // very light grey
  static const lightCard   = Color(0xFFFFFFFF);  // pure white cards
  static const lightCard2  = Color(0xFFF3F3F3);  // input field bg
  static const lightBorder = Color(0xFFE0E0E0);  // clear grey border
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
  Color get text1  => isDark ? const Color(0xFFF1F5F9) : const Color(0xFF111111);
  Color get text2  => isDark ? const Color(0xFFCBD5E1) : const Color(0xFF333333);
  Color get text3  => isDark ? const Color(0xFF94A3B8) : const Color(0xFF555555);
  Color get text4  => isDark ? const Color(0xFF64748B) : const Color(0xFF777777);
  Color get surface => isDark ? AppColors.darkCard  : Colors.white;

  // Glassmorphism properties
  Color get glassColor => isDark
      ? Colors.white.withOpacity(0.06)
      : Colors.white.withOpacity(0.55);
  Color get glassBorder => isDark
      ? Colors.white.withOpacity(0.12)
      : Colors.white.withOpacity(0.6);
  LinearGradient get meshGradient => isDark
      ? const LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFF0F0C29), Color(0xFF302B63), Color(0xFF24243E)])
      : const LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFFE8EAF6), Color(0xFFF3E5F5), Color(0xFFEDE7F6)]);

  List<Color> get bgGradient => isDark
      ? [const Color(0xFF0F0C29), const Color(0xFF302B63), const Color(0xFF24243E)]
      : [const Color(0xFFE8EAF6), const Color(0xFFF3E5F5), const Color(0xFFEDE7F6)];

  Gradient get cardGradient => isDark
      ? LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Colors.white.withOpacity(0.08), Colors.white.withOpacity(0.03)])
      : LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Colors.white.withOpacity(0.7), Colors.white.withOpacity(0.4)]);

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
  // ✅ FIX: Default to LIGHT mode instead of dark
  ThemeMode _mode = ThemeMode.light;

  @override
  void initState() {
    super.initState();
    I18n.instance.addListener(_onLocaleChanged);
  }

  @override
  void dispose() {
    I18n.instance.removeListener(_onLocaleChanged);
    super.dispose();
  }

  void _onLocaleChanged() {
    if (mounted) setState(() {});
  }

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
            dark ? const Color(0xFF64748B) : const Color(0xFF7070A0),
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
            color: dark ? const Color(0xFF94A3B8) : const Color(0xFF555555)),
        hintStyle: TextStyle(
            color: dark ? const Color(0xFF64748B) : const Color(0xFF7070A0)),
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
          // ✅ On web, skip Flutter splash — HTML splash (index.html) already
          // shows branding while Flutter loads. Going straight to login/home
          // avoids the double-splash (blue logo → badge logo → app).
          home: kIsWeb
              ? _WebEntry(toggleTheme: toggleTheme)
              : SplashScreen(toggleTheme: toggleTheme),
        );
      },
    );
  }
}

// ─── WEB ENTRY (skips splash on web) ──────────────────────────────────────────
class _WebEntry extends StatefulWidget {
  final VoidCallback toggleTheme;
  const _WebEntry({required this.toggleTheme});
  @override
  State<_WebEntry> createState() => _WebEntryState();
}

class _WebEntryState extends State<_WebEntry> {
  Widget? _destination;

  @override
  void initState() {
    super.initState();
    _resolveDestination();
  }

  Future<void> _resolveDestination() async {
    final user = await LocalDB.getCurrentUser();
    if (!mounted) return;
    setState(() {
      _destination = user != null
          ? HomeScreen(toggleTheme: widget.toggleTheme)
          : LoginScreen(toggleTheme: widget.toggleTheme);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Show a minimal container (same bg as HTML splash) until DB check finishes
    if (_destination == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF0A0E1A),
        body: SizedBox.shrink(),
      );
    }
    return _destination!;
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
      child: Image.asset('assets/images/app_icon.png', fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => Container(
          width: size, height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.accent),
          child: Icon(Icons.shield, color: Colors.white, size: size * 0.5))));
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

// ─── LOCALE SERVICE ─────────────────────────────────────────────────────────
class LocaleService extends ChangeNotifier {
  static const String _key = 'selected_locale';
  Locale _locale = const Locale('en');
  Locale get locale => _locale;

  static final LocaleService _instance = LocaleService._internal();
  factory LocaleService() => _instance;
  LocaleService._internal();

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_key) ?? 'en';
    _locale = Locale(code);
    notifyListeners();
  }

  Future<void> setLocale(Locale locale) async {
    if (_locale == locale) return;
    _locale = locale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, locale.languageCode);
    notifyListeners();
  }

  static const List<Locale> supportedLocales = [
    Locale('en'),
    Locale('hi'),
    Locale('bn'),
    Locale('or'),
  ];

  static const List<Map<String, String>> languages = [
    {'code': 'en', 'name': 'English', 'native': 'English', 'flag': '🇬🇧'},
    {'code': 'hi', 'name': 'Hindi',   'native': 'हिंदी',    'flag': '🇮🇳'},
    {'code': 'bn', 'name': 'Bengali', 'native': 'বাংলা',    'flag': '🇮🇳'},
    {'code': 'or', 'name': 'Odia',    'native': 'ଓଡ଼ିଆ',   'flag': '🇮🇳'},
  ];
}

// ─── APP LOCALIZATIONS ──────────────────────────────────────────────────────
//
// Hand-written localizations — NO code generation required.
// No flutter_gen, no build_runner.
class AppLocalizations {
  final Locale locale;
  AppLocalizations(this.locale);

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)
        ?? AppLocalizations(const Locale('en'));
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  // ── All strings ────────────────────────────────────────────────────────
  String get appName          => _t('appName');
  String get selectLanguage   => _t('selectLanguage');
  String get languageSaved    => _t('languageSaved');
  // Auth
  String get login            => _t('login');
  String get register         => _t('register');
  String get logout           => _t('logout');
  String get username         => _t('username');
  String get password         => _t('password');
  String get name             => _t('name');
  String get designation      => _t('designation');
  String get plant            => _t('plant');
  String get employeeNo       => _t('employeeNo');
  String get loginBtn         => _t('loginBtn');
  String get registerBtn      => _t('registerBtn');
  String get loginFailed      => _t('loginFailed');
  String get fillAllFields    => _t('fillAllFields');
  // Dashboard
  String get dashboard        => _t('dashboard');
  String get safetyScore      => _t('safetyScore');
  String get totalIncidents   => _t('totalIncidents');
  String get openIncidents    => _t('openIncidents');
  String get criticalIncidents => _t('criticalIncidents');
  String get aiScans          => _t('aiScans');
  String get quickActions     => _t('quickActions');
  String get reportNearMiss   => _t('reportNearMiss');
  String get startAiScan      => _t('startAiScan');
  String get viewReports      => _t('viewReports');
  String get askAi            => _t('askAi');
  String get plantSummary     => _t('plantSummary');
  String get recentActivity   => _t('recentActivity');
  String get noRecentActivity => _t('noRecentActivity');
  String get good             => _t('good');
  String get needsAttention   => _t('needsAttention');
  String get critical         => _t('critical');
  // Near Miss
  String get nearMissTitle        => _t('nearMissTitle');
  String get nearMissSubtitle     => _t('nearMissSubtitle');
  String get incidentDate         => _t('incidentDate');
  String get incidentTime         => _t('incidentTime');
  String get location             => _t('location');
  String get department           => _t('department');
  String get incidentDescription  => _t('incidentDescription');
  String get incidentDescHint     => _t('incidentDescHint');
  String get immediateAction      => _t('immediateAction');
  String get immediateActionHint  => _t('immediateActionHint');
  String get injuryOccurred       => _t('injuryOccurred');
  String get yes                  => _t('yes');
  String get no                   => _t('no');
  String get injuryDetails        => _t('injuryDetails');
  String get injuryDetailsHint    => _t('injuryDetailsHint');
  String get witnesses            => _t('witnesses');
  String get witnessesHint        => _t('witnessesHint');
  String get submitReport         => _t('submitReport');
  String get reportSubmitted      => _t('reportSubmitted');
  String get reportFailed         => _t('reportFailed');
  String get voiceInput           => _t('voiceInput');
  String get listening            => _t('listening');
  String get tapToSpeak           => _t('tapToSpeak');
  String get severityLevel        => _t('severityLevel');
  String get selectSeverity       => _t('selectSeverity');
  String get wsaCause             => _t('wsaCause');
  String get selectWsa            => _t('selectWsa');
  String get attachPhoto          => _t('attachPhoto');
  String get photoAttached        => _t('photoAttached');
  String get rootCause            => _t('rootCause');
  String get rootCauseHint        => _t('rootCauseHint');
  String get correctiveAction     => _t('correctiveAction');
  String get correctiveActionHint => _t('correctiveActionHint');
  // AI Scan
  String get aiScanTitle       => _t('aiScanTitle');
  String get aiScanSubtitle    => _t('aiScanSubtitle');
  String get takePhoto         => _t('takePhoto');
  String get uploadPhoto       => _t('uploadPhoto');
  String get analysing         => _t('analysing');
  String get analysisComplete  => _t('analysisComplete');
  String get hazardsFound      => _t('hazardsFound');
  String get noHazardsFound    => _t('noHazardsFound');
  String get riskScore         => _t('riskScore');
  String get confidence        => _t('confidence');
  String get hazardType        => _t('hazardType');
  String get summary           => _t('summary');
  String get hazards           => _t('hazards');
  String get correctiveActions => _t('correctiveActions');
  String get preventiveActions => _t('preventiveActions');
  String get regulations       => _t('regulations');
  String get exportPdf         => _t('exportPdf');
  String get shareReport       => _t('shareReport');
  String get scanAnother       => _t('scanAnother');
  // Reports
  String get reportsTitle   => _t('reportsTitle');
  String get filterAll      => _t('filterAll');
  String get filterCritical => _t('filterCritical');
  String get filterHigh     => _t('filterHigh');
  String get filterMedium   => _t('filterMedium');
  String get filterLow      => _t('filterLow');
  String get filterOpen     => _t('filterOpen');
  String get filterClosed   => _t('filterClosed');
  String get noReports      => _t('noReports');
  String get reportDate     => _t('reportDate');
  String get reportSeverity => _t('reportSeverity');
  String get reportStatus   => _t('reportStatus');
  String get reportType     => _t('reportType');
  String get viewDetail     => _t('viewDetail');
  String get markClosed     => _t('markClosed');
  String get deleteReport   => _t('deleteReport');
  String get confirmDelete  => _t('confirmDelete');
  String get deleteWarning  => _t('deleteWarning');
  String get cancel         => _t('cancel');
  String get confirm        => _t('confirm');
  // Chat
  String get chatTitle    => _t('chatTitle');
  String get chatHint     => _t('chatHint');
  String get chatSend     => _t('chatSend');
  String get chatWelcome  => _t('chatWelcome');
  String get chatOffline  => _t('chatOffline');
  String get chatThinking => _t('chatThinking');
  String get chatNoAnswer => _t('chatNoAnswer');
  // Settings
  String get settingsTitle       => _t('settingsTitle');
  String get settingsBackend     => _t('settingsBackend');
  String get settingsSyncNow     => _t('settingsSyncNow');
  String get settingsTheme       => _t('settingsTheme');
  String get settingsLanguage    => _t('settingsLanguage');
  String get settingsDark        => _t('settingsDark');
  String get settingsLight       => _t('settingsLight');
  String get settingsVersion     => _t('settingsVersion');
  String get settingsSyncSuccess => _t('settingsSyncSuccess');
  String get settingsSyncFail    => _t('settingsSyncFail');
  // Admin
  String get adminTitle        => _t('adminTitle');
  String get adminKnowledge    => _t('adminKnowledge');
  String get adminUsers        => _t('adminUsers');
  String get adminAnalytics    => _t('adminAnalytics');
  String get adminAddText      => _t('adminAddText');
  String get adminSyncCloud    => _t('adminSyncCloud');
  String get adminEbook        => _t('adminEbook');
  String get adminEbookSubtitle => _t('adminEbookSubtitle');
  String get adminSelectPdf    => _t('adminSelectPdf');
  String get adminGenerateKb   => _t('adminGenerateKb');
  String get adminKbGenerated  => _t('adminKbGenerated');
  String get adminCopyCode     => _t('adminCopyCode');
  String get adminCopied       => _t('adminCopied');
  String get adminProcessing   => _t('adminProcessing');
  String get adminNoDocuments  => _t('adminNoDocuments');
  String get adminNoUsers      => _t('adminNoUsers');
  // Severity / Status
  String get severityCritical  => _t('severity_critical');
  String get severityHigh      => _t('severity_high');
  String get severityMedium    => _t('severity_medium');
  String get severityLow       => _t('severity_low');
  String get statusOpen        => _t('status_open');
  String get statusClosed      => _t('status_closed');
  String get statusInProgress  => _t('status_inprogress');
  // Common
  String get loading  => _t('loading');
  String get retry    => _t('retry');
  String get save     => _t('save');
  String get update   => _t('update');
  String get delete   => _t('delete');
  String get edit     => _t('edit');
  String get close    => _t('close');
  String get back     => _t('back');
  String get next     => _t('next');
  String get submit   => _t('submit');
  String get reset    => _t('reset');
  String get search   => _t('search');
  String get noData   => _t('noData');
  String get error    => _t('error');
  String get success  => _t('success');
  String get warning  => _t('warning');
  String get info     => _t('info');

  // ── Translation lookup ─────────────────────────────────────────────────
  String _t(String key) {
    final lang = locale.languageCode;
    if (lang == 'hi') return _hi[key] ?? _en[key] ?? key;
    if (lang == 'bn') return _bn[key] ?? _en[key] ?? key;
    if (lang == 'or') return _or[key] ?? _en[key] ?? key;
    return _en[key] ?? key;
  }

  // ── English ───────────────────────────────────────────────────────────
  static const Map<String, String> _en = {
    'appName': 'SAIL Safety Lens',
    'selectLanguage': 'Select Language', 'languageSaved': 'Language updated',
    'login': 'Login', 'register': 'Register', 'logout': 'Logout',
    'username': 'Username', 'password': 'Password', 'name': 'Name',
    'designation': 'Designation', 'plant': 'Plant / Unit', 'employeeNo': 'Employee No.',
    'loginBtn': 'Login', 'registerBtn': 'Create Account',
    'loginFailed': 'Invalid credentials', 'fillAllFields': 'Please fill all fields',
    'dashboard': 'Dashboard', 'safetyScore': 'Safety Score',
    'totalIncidents': 'Total Incidents', 'openIncidents': 'Open',
    'criticalIncidents': 'Critical', 'aiScans': 'AI Scans',
    'quickActions': 'Quick Actions', 'reportNearMiss': 'Report Near Miss',
    'startAiScan': 'Start AI Scan', 'viewReports': 'View Reports',
    'askAi': 'Ask AI', 'plantSummary': 'Plant Summary',
    'recentActivity': 'Recent Activity', 'noRecentActivity': 'No recent activity',
    'good': 'Good', 'needsAttention': 'Needs Attention', 'critical': 'Critical',
    'nearMissTitle': 'Near Miss Report',
    'nearMissSubtitle': 'Report unsafe conditions or near miss incidents',
    'incidentDate': 'Incident Date', 'incidentTime': 'Incident Time',
    'location': 'Location / Area', 'department': 'Department',
    'incidentDescription': 'Incident Description',
    'incidentDescHint': 'Describe what happened, what you saw, or what could have gone wrong...',
    'immediateAction': 'Immediate Action Taken',
    'immediateActionHint': 'What was done immediately after the incident?',
    'injuryOccurred': 'Did any injury occur?', 'yes': 'Yes', 'no': 'No',
    'injuryDetails': 'Injury Details',
    'injuryDetailsHint': 'Describe the nature and extent of injury...',
    'witnesses': 'Witnesses (if any)', 'witnessesHint': 'Names of witnesses present...',
    'submitReport': 'Submit Report', 'reportSubmitted': 'Report submitted successfully',
    'reportFailed': 'Failed to submit report. Try again.',
    'voiceInput': 'Tap mic to speak', 'listening': 'Listening...', 'tapToSpeak': 'Tap to speak',
    'severityLevel': 'Severity Level', 'selectSeverity': 'Select Severity',
    'wsaCause': 'WSA Cause Category', 'selectWsa': 'Select WSA Cause',
    'attachPhoto': 'Attach Photo', 'photoAttached': 'Photo attached',
    'rootCause': 'Root Cause', 'rootCauseHint': 'What was the underlying cause?',
    'correctiveAction': 'Corrective Action',
    'correctiveActionHint': 'What action is recommended to prevent recurrence?',
    'aiScanTitle': 'AI Hazard Scan',
    'aiScanSubtitle': 'Take or upload a photo for AI hazard analysis',
    'takePhoto': 'Take Photo', 'uploadPhoto': 'Upload from Gallery',
    'analysing': 'Analysing image...', 'analysisComplete': 'Analysis Complete',
    'hazardsFound': 'Hazard(s) Found', 'noHazardsFound': 'No hazards detected',
    'riskScore': 'Risk Score', 'confidence': 'Confidence', 'hazardType': 'Hazard Type',
    'summary': 'Summary', 'hazards': 'Hazards',
    'correctiveActions': 'Corrective Actions', 'preventiveActions': 'Preventive Actions',
    'regulations': 'Applicable Regulations', 'exportPdf': 'Export PDF Report',
    'shareReport': 'Share Report', 'scanAnother': 'Scan Another',
    'reportsTitle': 'Incident Reports', 'filterAll': 'All',
    'filterCritical': 'Critical', 'filterHigh': 'High',
    'filterMedium': 'Medium', 'filterLow': 'Low',
    'filterOpen': 'Open', 'filterClosed': 'Closed',
    'noReports': 'No reports found', 'reportDate': 'Date',
    'reportSeverity': 'Severity', 'reportStatus': 'Status', 'reportType': 'Type',
    'viewDetail': 'View Detail', 'markClosed': 'Mark as Closed',
    'deleteReport': 'Delete', 'confirmDelete': 'Confirm Delete',
    'deleteWarning': 'This action cannot be undone.',
    'cancel': 'Cancel', 'confirm': 'Confirm',
    'chatTitle': 'Ask AI', 'chatHint': 'Ask about safety procedures, regulations...',
    'chatSend': 'Send',
    'chatWelcome': 'Hello! Ask me about PPE, LOTO, working at height, fire safety, gas hazards, or any SAIL safety topic.',
    'chatOffline': 'Offline Mode — Using local knowledge base',
    'chatThinking': 'Thinking...',
    'chatNoAnswer': 'Ask me about: PPE, LOTO, confined space, working at height, hot work, electrical, gas safety.',
    'settingsTitle': 'Settings', 'settingsBackend': 'Backend URL',
    'settingsSyncNow': 'Sync Now', 'settingsTheme': 'Theme',
    'settingsLanguage': 'Language', 'settingsDark': 'Dark', 'settingsLight': 'Light',
    'settingsVersion': 'Version', 'settingsSyncSuccess': 'Sync complete',
    'settingsSyncFail': 'Sync failed',
    'adminTitle': 'Admin Control Panel', 'adminKnowledge': 'Knowledge Base',
    'adminUsers': 'Users', 'adminAnalytics': 'Analytics',
    'adminAddText': 'Add Text Entry', 'adminSyncCloud': 'Sync from Cloud',
    'adminEbook': 'eBook → Local AI KB',
    'adminEbookSubtitle': 'Upload a safety PDF to auto-generate KB entries',
    'adminSelectPdf': 'Tap to select PDF eBook...',
    'adminGenerateKb': 'Generate KB', 'adminKbGenerated': 'KB Code Generated!',
    'adminCopyCode': 'Copy Code', 'adminCopied': 'Copied!',
    'adminProcessing': 'Processing...', 'adminNoDocuments': 'No knowledge documents yet',
    'adminNoUsers': 'No registered users',
    'severity_critical': 'CRITICAL', 'severity_high': 'HIGH',
    'severity_medium': 'MEDIUM', 'severity_low': 'LOW',
    'status_open': 'OPEN', 'status_closed': 'CLOSED', 'status_inprogress': 'IN PROGRESS',
    'loading': 'Loading...', 'retry': 'Retry', 'save': 'Save', 'update': 'Update',
    'delete': 'Delete', 'edit': 'Edit', 'close': 'Close', 'back': 'Back',
    'next': 'Next', 'submit': 'Submit', 'reset': 'Reset', 'search': 'Search',
    'noData': 'No data available', 'error': 'Error', 'success': 'Success',
    'warning': 'Warning', 'info': 'Info',
  };

  // ── Hindi ─────────────────────────────────────────────────────────────
  static const Map<String, String> _hi = {
    'appName': 'SAIL सेफ्टी लेंस',
    'selectLanguage': 'भाषा चुनें', 'languageSaved': 'भाषा अपडेट हो गई',
    'login': 'लॉगिन', 'register': 'पंजीकरण', 'logout': 'लॉगआउट',
    'username': 'उपयोगकर्ता नाम', 'password': 'पासवर्ड', 'name': 'नाम',
    'designation': 'पदनाम', 'plant': 'प्लांट / यूनिट', 'employeeNo': 'कर्मचारी संख्या',
    'loginBtn': 'लॉगिन करें', 'registerBtn': 'खाता बनाएं',
    'loginFailed': 'गलत क्रेडेंशियल', 'fillAllFields': 'कृपया सभी फ़ील्ड भरें',
    'dashboard': 'डैशबोर्ड', 'safetyScore': 'सुरक्षा स्कोर',
    'totalIncidents': 'कुल घटनाएं', 'openIncidents': 'खुली',
    'criticalIncidents': 'गंभीर', 'aiScans': 'AI स्कैन',
    'quickActions': 'त्वरित कार्य', 'reportNearMiss': 'नियर मिस रिपोर्ट करें',
    'startAiScan': 'AI स्कैन शुरू करें', 'viewReports': 'रिपोर्ट देखें',
    'askAi': 'AI से पूछें', 'plantSummary': 'प्लांट सारांश',
    'recentActivity': 'हालिया गतिविधि', 'noRecentActivity': 'कोई हालिया गतिविधि नहीं',
    'good': 'अच्छा', 'needsAttention': 'ध्यान चाहिए', 'critical': 'गंभीर',
    'nearMissTitle': 'नियर मिस रिपोर्ट',
    'nearMissSubtitle': 'असुरक्षित स्थिति या नियर मिस घटना की रिपोर्ट करें',
    'incidentDate': 'घटना की तारीख', 'incidentTime': 'घटना का समय',
    'location': 'स्थान / क्षेत्र', 'department': 'विभाग',
    'incidentDescription': 'घटना का विवरण',
    'incidentDescHint': 'बताएं क्या हुआ, क्या देखा, या क्या गलत हो सकता था...',
    'immediateAction': 'तत्काल की गई कार्रवाई',
    'immediateActionHint': 'घटना के बाद तुरंत क्या किया गया?',
    'injuryOccurred': 'क्या कोई चोट लगी?', 'yes': 'हाँ', 'no': 'नहीं',
    'injuryDetails': 'चोट का विवरण',
    'injuryDetailsHint': 'चोट की प्रकृति और सीमा बताएं...',
    'witnesses': 'गवाह (यदि कोई हो)', 'witnessesHint': 'उपस्थित गवाहों के नाम...',
    'submitReport': 'रिपोर्ट जमा करें', 'reportSubmitted': 'रिपोर्ट सफलतापूर्वक जमा हो गई',
    'reportFailed': 'रिपोर्ट जमा नहीं हो सकी। पुनः प्रयास करें।',
    'voiceInput': 'बोलने के लिए माइक दबाएं', 'listening': 'सुन रहा है...',
    'tapToSpeak': 'बोलने के लिए दबाएं',
    'severityLevel': 'गंभीरता स्तर', 'selectSeverity': 'गंभीरता चुनें',
    'wsaCause': 'WSA कारण श्रेणी', 'selectWsa': 'WSA कारण चुनें',
    'attachPhoto': 'फ़ोटो संलग्न करें', 'photoAttached': 'फ़ोटो संलग्न हो गई',
    'rootCause': 'मूल कारण', 'rootCauseHint': 'मूल कारण क्या था?',
    'correctiveAction': 'सुधारात्मक कार्रवाई',
    'correctiveActionHint': 'पुनरावृत्ति रोकने के लिए क्या कदम उठाए जाएं?',
    'aiScanTitle': 'AI हजार्ड स्कैन',
    'aiScanSubtitle': 'AI हजार्ड विश्लेषण के लिए फ़ोटो लें या अपलोड करें',
    'takePhoto': 'फ़ोटो लें', 'uploadPhoto': 'गैलरी से अपलोड करें',
    'analysing': 'छवि का विश्लेषण हो रहा है...', 'analysisComplete': 'विश्लेषण पूर्ण',
    'hazardsFound': 'खतरा मिला', 'noHazardsFound': 'कोई खतरा नहीं मिला',
    'riskScore': 'जोखिम स्कोर', 'confidence': 'विश्वसनीयता', 'hazardType': 'खतरे का प्रकार',
    'summary': 'सारांश', 'hazards': 'खतरे',
    'correctiveActions': 'सुधारात्मक कार्रवाइयां', 'preventiveActions': 'निवारक कार्रवाइयां',
    'regulations': 'लागू विनियम', 'exportPdf': 'PDF रिपोर्ट निर्यात करें',
    'shareReport': 'रिपोर्ट शेयर करें', 'scanAnother': 'दूसरा स्कैन करें',
    'reportsTitle': 'घटना रिपोर्ट', 'filterAll': 'सभी',
    'filterCritical': 'गंभीर', 'filterHigh': 'उच्च',
    'filterMedium': 'मध्यम', 'filterLow': 'कम',
    'filterOpen': 'खुली', 'filterClosed': 'बंद',
    'noReports': 'कोई रिपोर्ट नहीं मिली', 'reportDate': 'तारीख',
    'reportSeverity': 'गंभीरता', 'reportStatus': 'स्थिति', 'reportType': 'प्रकार',
    'viewDetail': 'विवरण देखें', 'markClosed': 'बंद के रूप में चिह्नित करें',
    'deleteReport': 'हटाएं', 'confirmDelete': 'हटाने की पुष्टि करें',
    'deleteWarning': 'यह क्रिया पूर्ववत नहीं की जा सकती।',
    'cancel': 'रद्द करें', 'confirm': 'पुष्टि करें',
    'chatTitle': 'AI से पूछें', 'chatHint': 'सुरक्षा प्रक्रियाओं के बारे में पूछें...',
    'chatSend': 'भेजें',
    'chatWelcome': 'नमस्ते! PPE, LOTO, ऊंचाई पर काम, अग्नि सुरक्षा के बारे में पूछें।',
    'chatOffline': 'ऑफलाइन मोड — स्थानीय ज्ञान आधार',
    'chatThinking': 'सोच रहा है...', 'chatNoAnswer': 'PPE, LOTO, सुरक्षा विषय पूछें।',
    'settingsTitle': 'सेटिंग्स', 'settingsBackend': 'बैकएंड URL',
    'settingsSyncNow': 'अभी सिंक करें', 'settingsTheme': 'थीम',
    'settingsLanguage': 'भाषा', 'settingsDark': 'डार्क', 'settingsLight': 'लाइट',
    'settingsVersion': 'संस्करण', 'settingsSyncSuccess': 'सिंक पूर्ण', 'settingsSyncFail': 'सिंक विफल',
    'adminTitle': 'एडमिन कंट्रोल पैनल', 'adminKnowledge': 'ज्ञान आधार',
    'adminUsers': 'उपयोगकर्ता', 'adminAnalytics': 'विश्लेषण',
    'adminAddText': 'टेक्स्ट एंट्री जोड़ें', 'adminSyncCloud': 'क्लाउड से सिंक करें',
    'adminEbook': 'ई-बुक → लोकल AI KB', 'adminEbookSubtitle': 'KB एंट्री बनाने के लिए PDF अपलोड करें',
    'adminSelectPdf': 'PDF ई-बुक चुनने के लिए दबाएं...',
    'adminGenerateKb': 'KB बनाएं', 'adminKbGenerated': 'KB कोड तैयार!',
    'adminCopyCode': 'कोड कॉपी करें', 'adminCopied': 'कॉपी हो गया!',
    'adminProcessing': 'प्रक्रिया हो रही है...', 'adminNoDocuments': 'अभी तक कोई दस्तावेज़ नहीं',
    'adminNoUsers': 'कोई पंजीकृत उपयोगकर्ता नहीं',
    'severity_critical': 'गंभीर', 'severity_high': 'उच्च',
    'severity_medium': 'मध्यम', 'severity_low': 'कम',
    'status_open': 'खुली', 'status_closed': 'बंद', 'status_inprogress': 'प्रगति में',
    'loading': 'लोड हो रहा है...', 'retry': 'पुनः प्रयास', 'save': 'सहेजें',
    'update': 'अपडेट करें', 'delete': 'हटाएं', 'edit': 'संपादित करें',
    'close': 'बंद करें', 'back': 'वापस', 'next': 'अगला', 'submit': 'जमा करें',
    'reset': 'रीसेट', 'search': 'खोजें', 'noData': 'कोई डेटा उपलब्ध नहीं',
    'error': 'त्रुटि', 'success': 'सफल', 'warning': 'चेतावनी', 'info': 'जानकारी',
  };

  // ── Bengali ───────────────────────────────────────────────────────────
  static const Map<String, String> _bn = {
    'appName': 'SAIL সেফটি লেন্স',
    'selectLanguage': 'ভাষা নির্বাচন করুন', 'languageSaved': 'ভাষা আপডেট হয়েছে',
    'login': 'লগইন', 'register': 'নিবন্ধন', 'logout': 'লগআউট',
    'username': 'ব্যবহারকারীর নাম', 'password': 'পাসওয়ার্ড', 'name': 'নাম',
    'designation': 'পদবি', 'plant': 'প্ল্যান্ট / ইউনিট', 'employeeNo': 'কর্মচারী নম্বর',
    'loginBtn': 'লগইন করুন', 'registerBtn': 'অ্যাকাউন্ট তৈরি করুন',
    'loginFailed': 'ভুল তথ্য', 'fillAllFields': 'সমস্ত ক্ষেত্র পূরণ করুন',
    'dashboard': 'ড্যাশবোর্ড', 'safetyScore': 'নিরাপত্তা স্কোর',
    'totalIncidents': 'মোট ঘটনা', 'openIncidents': 'খোলা',
    'criticalIncidents': 'গুরুতর', 'aiScans': 'AI স্ক্যান',
    'quickActions': 'দ্রুত ক্রিয়া', 'reportNearMiss': 'নিয়ার মিস রিপোর্ট করুন',
    'startAiScan': 'AI স্ক্যান শুরু করুন', 'viewReports': 'রিপোর্ট দেখুন',
    'askAi': 'AI কে জিজ্ঞেস করুন', 'plantSummary': 'প্ল্যান্ট সারসংক্ষেপ',
    'recentActivity': 'সাম্প্রতিক কার্যক্রম', 'noRecentActivity': 'কোনো সাম্প্রতিক কার্যক্রম নেই',
    'good': 'ভালো', 'needsAttention': 'মনোযোগ প্রয়োজন', 'critical': 'গুরুতর',
    'nearMissTitle': 'নিয়ার মিস রিপোর্ট',
    'nearMissSubtitle': 'অনিরাপদ পরিস্থিতি বা নিয়ার মিস ঘটনার রিপোর্ট করুন',
    'incidentDate': 'ঘটনার তারিখ', 'incidentTime': 'ঘটনার সময়',
    'location': 'স্থান / এলাকা', 'department': 'বিভাগ',
    'incidentDescription': 'ঘটনার বিবরণ',
    'incidentDescHint': 'কী হয়েছিল, কী দেখেছিলেন বা কী ভুল হতে পারত তা বর্ণনা করুন...',
    'immediateAction': 'তাৎক্ষণিক ব্যবস্থা',
    'immediateActionHint': 'ঘটনার পরপরই কী করা হয়েছিল?',
    'injuryOccurred': 'কোনো আঘাত হয়েছে কি?', 'yes': 'হ্যাঁ', 'no': 'না',
    'injuryDetails': 'আঘাতের বিবরণ', 'injuryDetailsHint': 'আঘাতের ধরন ও মাত্রা বর্ণনা করুন...',
    'witnesses': 'সাক্ষী (যদি থাকে)', 'witnessesHint': 'উপস্থিত সাক্ষীদের নাম...',
    'submitReport': 'রিপোর্ট জমা দিন', 'reportSubmitted': 'রিপোর্ট সফলভাবে জমা হয়েছে',
    'reportFailed': 'রিপোর্ট জমা হয়নি। আবার চেষ্টা করুন।',
    'voiceInput': 'বলতে মাইক চাপুন', 'listening': 'শুনছি...', 'tapToSpeak': 'বলতে চাপুন',
    'severityLevel': 'গুরুত্বের মাত্রা', 'selectSeverity': 'গুরুত্ব নির্বাচন করুন',
    'wsaCause': 'WSA কারণ বিভাগ', 'selectWsa': 'WSA কারণ নির্বাচন করুন',
    'attachPhoto': 'ছবি সংযুক্ত করুন', 'photoAttached': 'ছবি সংযুক্ত হয়েছে',
    'rootCause': 'মূল কারণ', 'rootCauseHint': 'মূল কারণ কী ছিল?',
    'correctiveAction': 'সংশোধনমূলক ব্যবস্থা',
    'correctiveActionHint': 'পুনরাবৃত্তি রোধে কী পদক্ষেপ নেওয়া উচিত?',
    'aiScanTitle': 'AI হ্যাজার্ড স্ক্যান',
    'aiScanSubtitle': 'AI বিশ্লেষণের জন্য ছবি তুলুন বা আপলোড করুন',
    'takePhoto': 'ছবি তুলুন', 'uploadPhoto': 'গ্যালারি থেকে আপলোড করুন',
    'analysing': 'ছবি বিশ্লেষণ হচ্ছে...', 'analysisComplete': 'বিশ্লেষণ সম্পন্ন',
    'hazardsFound': 'বিপদ পাওয়া গেছে', 'noHazardsFound': 'কোনো বিপদ পাওয়া যায়নি',
    'riskScore': 'ঝুঁকি স্কোর', 'confidence': 'আস্থা', 'hazardType': 'বিপদের ধরন',
    'summary': 'সারসংক্ষেপ', 'hazards': 'বিপদসমূহ',
    'correctiveActions': 'সংশোধনমূলক ব্যবস্থা', 'preventiveActions': 'প্রতিরোধমূলক ব্যবস্থা',
    'regulations': 'প্রযোজ্য বিধিমালা', 'exportPdf': 'PDF রিপোর্ট রপ্তানি করুন',
    'shareReport': 'রিপোর্ট শেয়ার করুন', 'scanAnother': 'আরেকটি স্ক্যান করুন',
    'reportsTitle': 'ঘটনার রিপোর্ট', 'filterAll': 'সব',
    'filterCritical': 'গুরুতর', 'filterHigh': 'উচ্চ',
    'filterMedium': 'মাঝারি', 'filterLow': 'কম',
    'filterOpen': 'খোলা', 'filterClosed': 'বন্ধ',
    'noReports': 'কোনো রিপোর্ট পাওয়া যায়নি', 'reportDate': 'তারিখ',
    'reportSeverity': 'গুরুত্ব', 'reportStatus': 'অবস্থা', 'reportType': 'ধরন',
    'viewDetail': 'বিস্তারিত দেখুন', 'markClosed': 'বন্ধ হিসেবে চিহ্নিত করুন',
    'deleteReport': 'মুছুন', 'confirmDelete': 'মুছে ফেলার নিশ্চিত করুন',
    'deleteWarning': 'এই ক্রিয়াটি পূর্বাবস্থায় ফেরানো যাবে না।',
    'cancel': 'বাতিল', 'confirm': 'নিশ্চিত করুন',
    'chatTitle': 'AI কে জিজ্ঞেস করুন', 'chatHint': 'নিরাপত্তা বিষয়ে জিজ্ঞেস করুন...',
    'chatSend': 'পাঠান',
    'chatWelcome': 'নমস্কার! PPE, LOTO, উচ্চতায় কাজ সম্পর্কে জিজ্ঞেস করুন।',
    'chatOffline': 'অফলাইন মোড — স্থানীয় জ্ঞানভান্ডার',
    'chatThinking': 'ভাবছি...', 'chatNoAnswer': 'PPE, LOTO, নিরাপত্তা বিষয় জিজ্ঞেস করুন।',
    'settingsTitle': 'সেটিংস', 'settingsBackend': 'ব্যাকএন্ড URL',
    'settingsSyncNow': 'এখন সিঙ্ক করুন', 'settingsTheme': 'থিম',
    'settingsLanguage': 'ভাষা', 'settingsDark': 'ডার্ক', 'settingsLight': 'লাইট',
    'settingsVersion': 'সংস্করণ', 'settingsSyncSuccess': 'সিঙ্ক সম্পন্ন', 'settingsSyncFail': 'সিঙ্ক ব্যর্থ',
    'adminTitle': 'অ্যাডমিন কন্ট্রোল প্যানেল', 'adminKnowledge': 'জ্ঞানভান্ডার',
    'adminUsers': 'ব্যবহারকারী', 'adminAnalytics': 'বিশ্লেষণ',
    'adminAddText': 'টেক্সট এন্ট্রি যোগ করুন', 'adminSyncCloud': 'ক্লাউড থেকে সিঙ্ক করুন',
    'adminEbook': 'ই-বুক → লোকাল AI KB', 'adminEbookSubtitle': 'KB তৈরির জন্য PDF আপলোড করুন',
    'adminSelectPdf': 'PDF ই-বুক বেছে নিতে চাপুন...',
    'adminGenerateKb': 'KB তৈরি করুন', 'adminKbGenerated': 'KB কোড তৈরি!',
    'adminCopyCode': 'কোড কপি করুন', 'adminCopied': 'কপি হয়েছে!',
    'adminProcessing': 'প্রক্রিয়া হচ্ছে...', 'adminNoDocuments': 'এখনো কোনো নথি নেই',
    'adminNoUsers': 'কোনো নিবন্ধিত ব্যবহারকারী নেই',
    'severity_critical': 'গুরুতর', 'severity_high': 'উচ্চ',
    'severity_medium': 'মাঝারি', 'severity_low': 'কম',
    'status_open': 'খোলা', 'status_closed': 'বন্ধ', 'status_inprogress': 'চলমান',
    'loading': 'লোড হচ্ছে...', 'retry': 'আবার চেষ্টা করুন', 'save': 'সংরক্ষণ করুন',
    'update': 'আপডেট করুন', 'delete': 'মুছুন', 'edit': 'সম্পাদনা করুন',
    'close': 'বন্ধ করুন', 'back': 'পেছনে', 'next': 'পরবর্তী', 'submit': 'জমা দিন',
    'reset': 'রিসেট', 'search': 'খুঁজুন', 'noData': 'কোনো ডেটা পাওয়া যায়নি',
    'error': 'ত্রুটি', 'success': 'সফল', 'warning': 'সতর্কতা', 'info': 'তথ্য',
  };

  // ── Odia ──────────────────────────────────────────────────────────────
  static const Map<String, String> _or = {
    'appName': 'SAIL ସେଫ୍ଟି ଲେନ୍ସ',
    'selectLanguage': 'ଭାଷା ବାଛନ୍ତୁ', 'languageSaved': 'ଭାଷା ଅଦ୍ୟତନ ହୋଇଛି',
    'login': 'ଲଗଇନ', 'register': 'ପଞ୍ଜୀକରଣ', 'logout': 'ଲଗଆଉଟ',
    'username': 'ଉପଯୋଗକର୍ତ୍ତା ନାମ', 'password': 'ପାସୱାର୍ଡ', 'name': 'ନାମ',
    'designation': 'ପଦବୀ', 'plant': 'ପ୍ଲାଣ୍ଟ / ୟୁନିଟ', 'employeeNo': 'କର୍ମଚାରୀ ନଂ',
    'loginBtn': 'ଲଗଇନ କରନ୍ତୁ', 'registerBtn': 'ଖାତା ତିଆରି କରନ୍ତୁ',
    'loginFailed': 'ଭୁଲ ପ୍ରମାଣପତ୍ର', 'fillAllFields': 'ଦୟାକରି ସମସ୍ତ କ୍ଷେତ୍ର ପୂରଣ କରନ୍ତୁ',
    'dashboard': 'ଡ୍ୟାଶବୋର୍ଡ', 'safetyScore': 'ସୁରକ୍ଷା ସ୍କୋର',
    'totalIncidents': 'ମୋଟ ଘଟଣା', 'openIncidents': 'ଖୋଲା',
    'criticalIncidents': 'ଗୁରୁତ୍ୱପୂର୍ଣ୍ଣ', 'aiScans': 'AI ସ୍କ୍ୟାନ',
    'quickActions': 'ତ୍ୱରିତ କ୍ରିୟା', 'reportNearMiss': 'ନିୟର ମିସ ରିପୋର୍ଟ କରନ୍ତୁ',
    'startAiScan': 'AI ସ୍କ୍ୟାନ ଆରମ୍ଭ କରନ୍ତୁ', 'viewReports': 'ରିପୋର୍ଟ ଦେଖନ୍ତୁ',
    'askAi': 'AI କୁ ପଚାରନ୍ତୁ', 'plantSummary': 'ପ୍ଲାଣ୍ଟ ସାରାଂଶ',
    'recentActivity': 'ସଦ୍ୟତନ କାର୍ଯ୍ୟକଳାପ', 'noRecentActivity': 'କୌଣସି ସଦ୍ୟତନ କାର୍ଯ୍ୟକଳାପ ନାହିଁ',
    'good': 'ଭଲ', 'needsAttention': 'ଧ୍ୟାନ ଦରକାର', 'critical': 'ଗୁରୁତ୍ୱପୂର୍ଣ୍ଣ',
    'nearMissTitle': 'ନିୟର ମିସ ରିପୋର୍ଟ',
    'nearMissSubtitle': 'ଅସୁରକ୍ଷିତ ଅବସ୍ଥା ବା ନିୟର ମିସ ଘଟଣା ରିପୋର୍ଟ କରନ୍ତୁ',
    'incidentDate': 'ଘଟଣାର ତାରିଖ', 'incidentTime': 'ଘଟଣାର ସମୟ',
    'location': 'ସ୍ଥାନ / ଏଲାକା', 'department': 'ବିଭାଗ',
    'incidentDescription': 'ଘଟଣାର ବିବରଣୀ',
    'incidentDescHint': 'କ\'ଣ ହୋଇଥିଲା, କ\'ଣ ଦେଖିଥିଲେ ବା କ\'ଣ ଭୁଲ ହୋଇ ପାରିଥାନ୍ତା ବର୍ଣ୍ଣନା କରନ୍ତୁ...',
    'immediateAction': 'ତୁରନ୍ତ ଗ୍ରହଣ କରାଯାଇଥିବା ପଦକ୍ଷେପ',
    'immediateActionHint': 'ଘଟଣା ପରେ ତୁରନ୍ତ କ\'ଣ କରାଯାଇଥିଲା?',
    'injuryOccurred': 'କୌଣସି ଆଘାତ ଲାଗିଛି କି?', 'yes': 'ହଁ', 'no': 'ନା',
    'injuryDetails': 'ଆଘାତ ବିବରଣୀ', 'injuryDetailsHint': 'ଆଘାତର ପ୍ରକୃତି ଓ ମାତ୍ରା ବର୍ଣ୍ଣନା କରନ୍ତୁ...',
    'witnesses': 'ସାକ୍ଷୀ (ଯଦି ଥାଏ)', 'witnessesHint': 'ଉପସ୍ଥିତ ସାକ୍ଷୀଙ୍କ ନାମ...',
    'submitReport': 'ରିପୋର୍ଟ ଦାଖଲ କରନ୍ତୁ', 'reportSubmitted': 'ରିପୋର୍ଟ ସଫଳତାର ସହ ଦାଖଲ ହୋଇଛି',
    'reportFailed': 'ରିପୋର୍ଟ ଦାଖଲ ହୋଇ ପାରିଲା ନାହିଁ। ପୁଣି ଚେଷ୍ଟା କରନ୍ତୁ।',
    'voiceInput': 'କହିବା ପାଇଁ ମାଇକ୍ ଦବାନ୍ତୁ', 'listening': 'ଶୁଣୁଛି...', 'tapToSpeak': 'କହିବା ପାଇଁ ଦବାନ୍ତୁ',
    'severityLevel': 'ଗୁରୁତ୍ୱ ସ୍ତର', 'selectSeverity': 'ଗୁରୁତ୍ୱ ବାଛନ୍ତୁ',
    'wsaCause': 'WSA କାରଣ ବର୍ଗ', 'selectWsa': 'WSA କାରଣ ବାଛନ୍ତୁ',
    'attachPhoto': 'ଫଟୋ ସଂଲଗ୍ନ କରନ୍ତୁ', 'photoAttached': 'ଫଟୋ ସଂଲଗ୍ନ ହୋଇଛି',
    'rootCause': 'ମୂଳ କାରଣ', 'rootCauseHint': 'ମୂଳ କାରଣ କ\'ଣ ଥିଲା?',
    'correctiveAction': 'ସଂଶୋଧନମୂଳକ ପଦକ୍ଷେପ',
    'correctiveActionHint': 'ପୁନରାବୃତ୍ତି ରୋକିବା ପାଇଁ କ\'ଣ ପଦକ୍ଷେପ ନେବା ଉଚିତ?',
    'aiScanTitle': 'AI ହ୍ୟାଜାର୍ଡ ସ୍କ୍ୟାନ',
    'aiScanSubtitle': 'AI ବିଶ୍ଳେଷଣ ପାଇଁ ଫଟୋ ନିଅନ୍ତୁ ବା ଅପଲୋଡ କରନ୍ତୁ',
    'takePhoto': 'ଫଟୋ ନିଅନ୍ତୁ', 'uploadPhoto': 'ଗ୍ୟାଲେରୀରୁ ଅପଲୋଡ କରନ୍ତୁ',
    'analysing': 'ଛବି ବିଶ୍ଳେଷଣ ହେଉଛି...', 'analysisComplete': 'ବିଶ୍ଳେଷଣ ସମ୍ପୂର୍ଣ୍ଣ',
    'hazardsFound': 'ବିପଦ ମିଳିଛି', 'noHazardsFound': 'କୌଣସି ବିପଦ ମିଳିଲା ନାହିଁ',
    'riskScore': 'ଝୁଁକି ସ୍କୋର', 'confidence': 'ଆସ୍ଥା', 'hazardType': 'ବିପଦ ପ୍ରକାର',
    'summary': 'ସାରାଂଶ', 'hazards': 'ବିପଦ',
    'correctiveActions': 'ସଂଶୋଧନମୂଳକ ପଦକ୍ଷେପ', 'preventiveActions': 'ପ୍ରତିରୋଧମୂଳକ ପଦକ୍ଷେପ',
    'regulations': 'ପ୍ରଯୋଜ୍ୟ ନିୟମ', 'exportPdf': 'PDF ରିପୋର୍ଟ ରପ୍ତାନି କରନ୍ତୁ',
    'shareReport': 'ରିପୋର୍ଟ ଅଂଶୀଦାର କରନ୍ତୁ', 'scanAnother': 'ଆଉ ଗୋଟିଏ ସ୍କ୍ୟାନ କରନ୍ତୁ',
    'reportsTitle': 'ଘଟଣା ରିପୋର୍ଟ', 'filterAll': 'ସବୁ',
    'filterCritical': 'ଗୁରୁତ୍ୱପୂର୍ଣ୍ଣ', 'filterHigh': 'ଉଚ୍ଚ',
    'filterMedium': 'ମଧ୍ୟମ', 'filterLow': 'କମ',
    'filterOpen': 'ଖୋଲା', 'filterClosed': 'ବନ୍ଦ',
    'noReports': 'କୌଣସି ରିପୋର୍ଟ ମିଳିଲା ନାହିଁ', 'reportDate': 'ତାରିଖ',
    'reportSeverity': 'ଗୁରୁତ୍ୱ', 'reportStatus': 'ଅବସ୍ଥା', 'reportType': 'ପ୍ରକାର',
    'viewDetail': 'ବିବରଣୀ ଦେଖନ୍ତୁ', 'markClosed': 'ବନ୍ଦ ଭାବେ ଚିହ୍ନିତ କରନ୍ତୁ',
    'deleteReport': 'ଡିଲିଟ କରନ୍ତୁ', 'confirmDelete': 'ଡିଲିଟ ନିଶ୍ଚିତ କରନ୍ତୁ',
    'deleteWarning': 'ଏହି କ୍ରିୟା ପୂର୍ବାବସ୍ଥାକୁ ଫେରାଯାଇ ପାରିବ ନାହିଁ।',
    'cancel': 'ବାତିଲ', 'confirm': 'ନିଶ୍ଚିତ କରନ୍ତୁ',
    'chatTitle': 'AI କୁ ପଚାରନ୍ତୁ', 'chatHint': 'ସୁରକ୍ଷା ବିଷୟ ପଚାରନ୍ତୁ...',
    'chatSend': 'ପଠାନ୍ତୁ',
    'chatWelcome': 'ନମସ୍କାର! PPE, LOTO, ଉଚ୍ଚତାରେ କାର୍ଯ୍ୟ ବାବଦ ପଚାରନ୍ତୁ।',
    'chatOffline': 'ଅଫଲାଇନ ମୋଡ — ସ୍ଥାନୀୟ ଜ୍ଞାନ ଭଣ୍ଡାର',
    'chatThinking': 'ଭାବୁଛି...', 'chatNoAnswer': 'PPE, LOTO, ସୁରକ୍ଷା ବିଷୟ ପଚାରନ୍ତୁ।',
    'settingsTitle': 'ସେଟିଂ', 'settingsBackend': 'ବ୍ୟାକଏଣ୍ଡ URL',
    'settingsSyncNow': 'ଏବେ ସିଙ୍କ କରନ୍ତୁ', 'settingsTheme': 'ଥିମ',
    'settingsLanguage': 'ଭାଷା', 'settingsDark': 'ଅନ୍ଧାର', 'settingsLight': 'ଆଲୋକ',
    'settingsVersion': 'ସଂସ୍କରଣ', 'settingsSyncSuccess': 'ସିଙ୍କ ସମ୍ପୂର୍ଣ୍ଣ', 'settingsSyncFail': 'ସିଙ୍କ ବିଫଳ',
    'adminTitle': 'ଆଡमିନ କଣ୍ଟ୍ରୋଲ ପ୍ୟାନେଲ', 'adminKnowledge': 'ଜ୍ଞାନ ଭଣ୍ଡାର',
    'adminUsers': 'ଉପଯୋଗକର୍ତ୍ତା', 'adminAnalytics': 'ବିଶ୍ଳେଷଣ',
    'adminAddText': 'ଟେକ୍ସଟ ଏଣ୍ଟ୍ରି ଯୋଡନ୍ତୁ', 'adminSyncCloud': 'କ୍ଲାଉଡରୁ ସିଙ୍କ କରନ୍ତୁ',
    'adminEbook': 'ଇ-ବୁକ → ଲୋକାଲ AI KB', 'adminEbookSubtitle': 'KB ପାଇଁ PDF ଅପଲୋଡ କରନ୍ତୁ',
    'adminSelectPdf': 'PDF ଇ-ବୁକ ବାଛିବା ପାଇଁ ଦବାନ୍ତୁ...',
    'adminGenerateKb': 'KB ତିଆରି କରନ୍ତୁ', 'adminKbGenerated': 'KB କୋଡ ପ୍ରସ୍ତୁତ!',
    'adminCopyCode': 'କୋଡ କପି କରନ୍ତୁ', 'adminCopied': 'କପି ହୋଇଛି!',
    'adminProcessing': 'ପ୍ରକ୍ରିୟା ହେଉଛି...', 'adminNoDocuments': 'ଏ ପର୍ଯ୍ୟନ୍ତ କୌଣସି ଡକ୍ୟୁମେଣ୍ଟ ନାହିଁ',
    'adminNoUsers': 'କୌଣସି ପଞ୍ଜୀକୃତ ଉପଯୋଗକର୍ତ୍ତା ନାହିଁ',
    'severity_critical': 'ଗୁରୁତ୍ୱପୂର୍ଣ୍ଣ', 'severity_high': 'ଉଚ୍ଚ',
    'severity_medium': 'ମଧ୍ୟମ', 'severity_low': 'କମ',
    'status_open': 'ଖୋଲା', 'status_closed': 'ବନ୍ଦ', 'status_inprogress': 'ଚଲୁଛି',
    'loading': 'ଲୋଡ ହେଉଛି...', 'retry': 'ପୁଣି ଚେଷ୍ଟା କରନ୍ତୁ', 'save': 'ସଞ୍ଚୟ କରନ୍ତୁ',
    'update': 'ଅଦ୍ୟତନ କରନ୍ତୁ', 'delete': 'ଡିଲିଟ କରନ୍ତୁ', 'edit': 'ସଂପାଦନ କରନ୍ତୁ',
    'close': 'ବନ୍ଦ କରନ୍ତୁ', 'back': 'ପଛକୁ', 'next': 'ପରବର୍ତ୍ତୀ', 'submit': 'ଦାଖଲ କରନ୍ତୁ',
    'reset': 'ରିସେଟ', 'search': 'ଖୋଜନ୍ତୁ', 'noData': 'କୌଣସି ଡେଟା ଉପಲବ୍ଧ ନାହିଁ',
    'error': 'ତ୍ରୁଟି', 'success': 'ସଫଳ', 'warning': 'ଚେତାବନୀ', 'info': 'ସୂଚନା',
  };
}

// ── Delegate ──────────────────────────────────────────────────────────────────
class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();
  @override
  bool isSupported(Locale locale) =>
      ['en', 'hi', 'bn', 'or'].contains(locale.languageCode);
  @override
  Future<AppLocalizations> load(Locale locale) async =>
      AppLocalizations(locale);
  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
