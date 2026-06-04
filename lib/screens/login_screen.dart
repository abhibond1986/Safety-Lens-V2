import '../widgets/language_picker_widget.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../main.dart';
import '../services/local_db.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  final VoidCallback toggleTheme;
  const LoginScreen({super.key, required this.toggleTheme});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  bool _isLogin = true;
  bool _busy = false;
  bool _obscurePass = true;

  final _liUsername = TextEditingController(text: 'abhishek.kumar');
  final _liPassword = TextEditingController(text: 'demo');
  final _rgName     = TextEditingController(text: 'Abhishek Kumar');
  final _rgDesig    = TextEditingController(text: 'AGM');
  final _rgPlant    = TextEditingController(text: 'SAIL Safety Organisation');
  final _rgPno      = TextEditingController();
  final _rgMobile   = TextEditingController();
  final _rgEmail    = TextEditingController();
  final _rgPassword = TextEditingController();

  late AnimationController _orbCtrl;
  late AnimationController _cardCtrl;
  late Animation<double> _cardFade;
  late Animation<double> _cardSlide;

  @override
  void initState() {
    super.initState();
    _orbCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 8))
      ..repeat(reverse: true);
    _cardCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _cardFade  = CurvedAnimation(parent: _cardCtrl, curve: Curves.easeOut);
    _cardSlide = Tween<double>(begin: 30, end: 0).animate(
      CurvedAnimation(parent: _cardCtrl, curve: Curves.easeOutCubic));
    _cardCtrl.forward();
  }

  @override
  void dispose() {
    _orbCtrl.dispose();
    _cardCtrl.dispose();
    super.dispose();
  }

  void _switchTab(bool isLogin) {
    setState(() => _isLogin = isLogin);
    _cardCtrl.forward(from: 0);
  }

  Future<void> _doLogin() async {
    setState(() => _busy = true);
    final user = await LocalDB.signIn(_liUsername.text.trim(), _liPassword.text);
    setState(() => _busy = false);
    if (user != null && mounted) {
      Navigator.pushReplacement(context,
        PageRouteBuilder(
          pageBuilder: (_, a, __) => HomeScreen(toggleTheme: widget.toggleTheme),
          transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
          transitionDuration: const Duration(milliseconds: 400),
        ));
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid username or password'),
          backgroundColor: AppColors.red));
    }
  }

  Future<void> _doRegister() async {
    if (_rgName.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your name'),
          backgroundColor: AppColors.red));
      return;
    }
    if (_rgPassword.text.length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password must be at least 4 characters'),
          backgroundColor: AppColors.red));
      return;
    }
    setState(() => _busy = true);
    final user = await LocalDB.register({
      'username': _rgEmail.text.trim().isNotEmpty
          ? _rgEmail.text.trim().split('@').first
          : _rgName.text.trim().toLowerCase().replaceAll(' ', '.'),
      'password': _rgPassword.text,
      'name': _rgName.text.trim(),
      'designation': _rgDesig.text.trim(),
      'plant': _rgPlant.text.trim(),
      'pno': _rgPno.text.trim(),
      'mobile': _rgMobile.text.trim(),
      'email': _rgEmail.text.trim(),
      'isAdmin': false,
    });
    setState(() => _busy = false);
    if (user != null && mounted) {
      Navigator.pushReplacement(context,
        PageRouteBuilder(
          pageBuilder: (_, a, __) => HomeScreen(toggleTheme: widget.toggleTheme),
          transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
          transitionDuration: const Duration(milliseconds: 400),
        ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Light blueish-grey background
      backgroundColor: const Color(0xFFEEF2F7),
      body: Stack(children: [
        // Animated ambient orbs on light bg
        _orb(Alignment.topRight, const Color(0xFF3B82F6), 0.12),
        _orb(Alignment.bottomLeft, const Color(0xFF8B5CF6), 0.10),
        _orb(Alignment.topLeft, const Color(0xFF06B6D4), 0.07),

        SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: AnimatedBuilder(
              animation: _cardCtrl,
              builder: (_, child) => Transform.translate(
                offset: Offset(0, _cardSlide.value),
                child: FadeTransition(opacity: _cardFade, child: child),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _logoHeader(),
                  const SizedBox(height: 20),
                  _glassCard(),
                ],
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _orb(Alignment align, Color color, double opacity) {
    return Positioned.fill(
      child: Align(
        alignment: align,
        child: AnimatedBuilder(
          animation: _orbCtrl,
          builder: (_, __) {
            final v = _orbCtrl.value;
            return Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  color.withOpacity(opacity * (0.7 + 0.3 * v)),
                  Colors.transparent,
                ]),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _logoHeader() {
    return Column(children: [
      // SAIL logo in frosted circle
      Container(
        width: 80, height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(0.7),
          border: Border.all(color: Colors.white.withOpacity(0.9), width: 2),
          boxShadow: [
            BoxShadow(color: const Color(0xFF3B82F6).withOpacity(0.2),
              blurRadius: 20, spreadRadius: 2),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Image.asset('assets/images/sail_logo.png', fit: BoxFit.contain),
        ),
      ),
      const SizedBox(height: 12),
      ShaderMask(
        shaderCallback: (r) => const LinearGradient(
          colors: [Color(0xFF1D4ED8), Color(0xFF7C3AED)],
        ).createShader(r),
        child: const Text('Safety Lens',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800,
            color: Colors.white, letterSpacing: -0.5)),
      ),
      const SizedBox(height: 3),
      const Text('SAIL · AI-Powered Safety · IS 14489',
        style: TextStyle(color: Color(0xFF64748B), fontSize: 10,
          letterSpacing: 1.5, fontWeight: FontWeight.w600)),
    ]);
  }

  Widget _glassCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.55),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.8), width: 1.5),
        boxShadow: [
          BoxShadow(color: const Color(0xFF3B82F6).withOpacity(0.08),
            blurRadius: 30, spreadRadius: 0, offset: const Offset(0, 8)),
          BoxShadow(color: Colors.black.withOpacity(0.06),
            blurRadius: 20, spreadRadius: 0),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Column(children: [
          _tabBar(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: _isLogin ? _loginForm() : _registerForm(),
          ),
        ]),
      ),
    );
  }

  Widget _tabBar() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFE2E8F0),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Row(children: [
        _tab('Sign In', Icons.login_rounded, true),
        _tab('Register', Icons.person_add_rounded, false),
      ]),
    );
  }

  Widget _tab(String label, IconData icon, bool isLogin) {
    final selected = _isLogin == isLogin;
    return Expanded(
      child: GestureDetector(
        onTap: () => _switchTab(isLogin),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            boxShadow: selected ? [
              BoxShadow(color: Colors.black.withOpacity(0.08),
                blurRadius: 8, offset: const Offset(0, 2)),
            ] : [],
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 13,
              color: selected ? const Color(0xFF3B82F6) : const Color(0xFF94A3B8)),
            const SizedBox(width: 5),
            Text(label, style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700,
              color: selected ? const Color(0xFF1E40AF) : const Color(0xFF94A3B8))),
          ]),
        ),
      ),
    );
  }

  Widget _loginForm() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _fieldLabel('Username'),
      _glassInput(_liUsername, hint: 'your.username',
        icon: Icons.person_outline_rounded),
      const SizedBox(height: 12),
      _fieldLabel('Password'),
      _glassInput(_liPassword, hint: '••••••••',
        icon: Icons.lock_outline_rounded, isPassword: true),
      const SizedBox(height: 20),
      const SizedBox(height: 16),
const LanguagePickerWidget(),
const SizedBox(height: 20),
// ... your existing login button
      _primaryBtn(
        label: 'Sign In',
        icon: Icons.login_rounded,
        onTap: _busy ? null : _doLogin,
        gradient: const LinearGradient(
          colors: [Color(0xFF2563EB), Color(0xFF7C3AED)]),
      ),
      const SizedBox(height: 12),
      Center(child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Text('New user? ', style: TextStyle(
          color: Color(0xFF64748B), fontSize: 11)),
        GestureDetector(
          onTap: () => _switchTab(false),
          child: const Text('Create account', style: TextStyle(
            color: Color(0xFF2563EB), fontSize: 11,
            fontWeight: FontWeight.w700))),
      ])),
    ]);
  }

  Widget _registerForm() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _fieldLabel('Full Name *'),
      _glassInput(_rgName, icon: Icons.badge_outlined),
      const SizedBox(height: 10),
      _fieldLabel('Designation *'),
      _glassInput(_rgDesig, hint: 'e.g. AGM, Manager', icon: Icons.work_outline),
      const SizedBox(height: 10),
      _fieldLabel('Plant / Unit'),
      _glassInput(_rgPlant, icon: Icons.factory_outlined),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _fieldLabel('P.No'),
            _glassInput(_rgPno, hint: 'Personnel No.', icon: Icons.tag),
          ])),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _fieldLabel('Mobile'),
            _glassInput(_rgMobile, hint: '10-digit',
              icon: Icons.phone_outlined,
              kbType: TextInputType.phone),
          ])),
      ]),
      const SizedBox(height: 10),
      _fieldLabel('Email'),
      _glassInput(_rgEmail, hint: 'name@sail.in',
        icon: Icons.email_outlined,
        kbType: TextInputType.emailAddress),
      const SizedBox(height: 10),
      _fieldLabel('Password *'),
      _glassInput(_rgPassword, hint: 'Min 4 characters',
        icon: Icons.lock_outline_rounded, isPassword: true),
      const SizedBox(height: 20),
      _primaryBtn(
        label: 'Create Account',
        icon: Icons.person_add_rounded,
        onTap: _busy ? null : _doRegister,
        gradient: const LinearGradient(
          colors: [Color(0xFF059669), Color(0xFF0891B2)]),
      ),
      const SizedBox(height: 12),
      Center(child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Text('Already registered? ', style: TextStyle(
          color: Color(0xFF64748B), fontSize: 11)),
        GestureDetector(
          onTap: () => _switchTab(true),
          child: const Text('Sign in', style: TextStyle(
            color: Color(0xFF2563EB), fontSize: 11,
            fontWeight: FontWeight.w700))),
      ])),
    ]);
  }

  Widget _fieldLabel(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: Text(t, style: const TextStyle(
      color: Color(0xFF475569), fontSize: 10.5,
      fontWeight: FontWeight.w700, letterSpacing: 0.3)));

  Widget _glassInput(TextEditingController c, {
    String? hint, bool isPassword = false,
    IconData? icon, TextInputType? kbType,
  }) {
    return TextField(
      controller: c,
      obscureText: isPassword && _obscurePass,
      keyboardType: kbType,
      style: const TextStyle(color: Color(0xFF1E293B), fontSize: 13),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 12),
        prefixIcon: icon != null
            ? Icon(icon, size: 17, color: const Color(0xFF94A3B8)) : null,
        suffixIcon: isPassword
            ? GestureDetector(
                onTap: () => setState(() => _obscurePass = !_obscurePass),
                child: Icon(
                  _obscurePass ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  size: 17, color: const Color(0xFF94A3B8)))
            : null,
        filled: true,
        fillColor: Colors.white.withOpacity(0.7),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.9), width: 1.5)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1.5)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 2)),
      ),
    );
  }

  Widget _primaryBtn({
    required String label,
    required IconData icon,
    required VoidCallback? onTap,
    required Gradient gradient,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          gradient: onTap == null ? null : gradient,
          color: onTap == null ? const Color(0xFFCBD5E1) : null,
          borderRadius: BorderRadius.circular(14),
          boxShadow: onTap == null ? [] : [
            BoxShadow(color: const Color(0xFF3B82F6).withOpacity(0.35),
              blurRadius: 16, offset: const Offset(0, 6)),
          ],
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (_busy)
            const SizedBox(width: 16, height: 16,
              child: CircularProgressIndicator(strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
          else
            Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(
            color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700,
            letterSpacing: 0.3)),
        ]),
      ),
    );
  }
}
