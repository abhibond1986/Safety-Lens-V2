// lib/screens/login_screen.dart
//
// Changes from original:
// 1. Plant field replaced with dropdown (14 SAIL plants + "Others")
// 2. When "Others" selected, a free-text field appears for custom plant name
// 3. All other logic unchanged

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

class _LoginScreenState extends State<LoginScreen> {
  bool _isLogin = true;
  bool _loading = false;
  String _err = '';

  // Login controllers
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  // Register controllers
  final _regNameCtrl   = TextEditingController();
  final _regUserCtrl   = TextEditingController();
  final _regPassCtrl   = TextEditingController();
  final _regDesigCtrl  = TextEditingController();
  final _regPnoCtrl    = TextEditingController();
  final _regOtherPlantCtrl = TextEditingController();

  // Plant dropdown
  String? _selectedPlant;
  bool _isOtherPlant = false;

  static const List<String> _sailPlants = [
    'BSL - Bokaro Steel Plant',
    'RSP - Rourkela Steel Plant',
    'DSP - Durgapur Steel Plant',
    'BSP - Bhilai Steel Plant',
    'ISP - IISCO Steel Plant, Burnpur',
    'VISL - Visvesvaraya Iron & Steel Plant',
    'SSP - Salem Steel Plant',
    'ASP - Alloy Steels Plant, Durgapur',
    'CFP - Chandrapur Ferro Alloy Plant',
    'SAIL Corporate Office, New Delhi',
    'R&D Centre for Iron & Steel (RDCIS)',
    'Centre for Engineering & Technology (CET)',
    'Management Training Institute (MTI)',
    'SAIL Safety Organisation (SSO)',
    'Others',
  ];

  String get _effectivePlant {
    if (_isOtherPlant) return _regOtherPlantCtrl.text.trim();
    return _selectedPlant ?? '';
  }

  @override
  void dispose() {
    _userCtrl.dispose(); _passCtrl.dispose();
    _regNameCtrl.dispose(); _regUserCtrl.dispose(); _regPassCtrl.dispose();
    _regDesigCtrl.dispose(); _regPnoCtrl.dispose(); _regOtherPlantCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_userCtrl.text.trim().isEmpty || _passCtrl.text.isEmpty) {
      setState(() => _err = 'Please fill all fields');
      return;
    }
    setState(() { _loading = true; _err = ''; });
    try {
      final user = await LocalDB.signIn(
        _userCtrl.text.trim(), _passCtrl.text);
      if (!mounted) return;
      if (user != null) {
        Navigator.pushReplacement(context, PageRouteBuilder(
          pageBuilder: (_, a, __) =>
              HomeScreen(toggleTheme: widget.toggleTheme),
          transitionsBuilder: (_, a, __, child) =>
              FadeTransition(opacity: a, child: child),
          transitionDuration: const Duration(milliseconds: 400)));
      } else {
        setState(() => _err = 'Invalid credentials');
      }
    } catch (e) {
      setState(() => _err = 'Login failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _register() async {
    final name  = _regNameCtrl.text.trim();
    final user  = _regUserCtrl.text.trim();
    final pass  = _regPassCtrl.text;
    final desig = _regDesigCtrl.text.trim();
    final plant = _effectivePlant;

    if ([name, user, pass, desig, plant].any((s) => s.isEmpty)) {
      setState(() => _err = 'Please fill all fields including plant');
      return;
    }
    setState(() { _loading = true; _err = ''; });
    try {
      final ok = await LocalDB.register({
        'name': name, 'username': user, 'password': pass,
        'designation': desig, 'plant': plant,
        'pno': _regPnoCtrl.text.trim()});
      if (!mounted) return;
      if (ok != null) {
        setState(() { _isLogin = true; _err = ''; });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Account created! Please login.'),
          backgroundColor: Colors.green));
      } else {
        setState(() => _err = 'Username already taken');
      }
    } catch (e) {
      setState(() => _err = 'Registration failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sl = SL.of(context);
    return Scaffold(
      backgroundColor: sl.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: 28, vertical: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ── Logo ─────────────────────────────────────────────
                Container(
                  width: 76, height: 76,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1E1E3F), Color(0xFF2A2A50)]),
                    border: Border.all(
                      color: AppColors.accent.withOpacity(0.4),
                      width: 1.5),
                    boxShadow: [BoxShadow(
                      color: AppColors.accent.withOpacity(0.2),
                      blurRadius: 20)]),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Image.asset(
                      'assets/images/sail_logo.png',
                      fit: BoxFit.contain))),
                const SizedBox(height: 18),
                const BrandTitle(size: 24),
                const SizedBox(height: 6),
                Text('AI Safety Platform',
                  style: TextStyle(
                    color: sl.text4, fontSize: 12,
                    letterSpacing: 1.2)),
                const SizedBox(height: 32),

                // ── Tab switcher ─────────────────────────────────────
                Container(
                  decoration: BoxDecoration(
                    color: sl.card2,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: sl.border)),
                  padding: const EdgeInsets.all(4),
                  child: Row(children: [
                    _tab('Login', _isLogin, () =>
                        setState(() { _isLogin = true; _err = ''; })),
                    _tab('Register', !_isLogin, () =>
                        setState(() { _isLogin = false; _err = ''; })),
                  ])),
                const SizedBox(height: 24),

                // ── Form ─────────────────────────────────────────────
                if (_isLogin) ..._loginFields(sl)
                else ..._registerFields(sl),

                if (_err.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.crit.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.crit.withOpacity(0.4))),
                    child: Row(children: [
                      const Icon(Icons.error_outline,
                        color: AppColors.crit, size: 16),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_err,
                        style: const TextStyle(
                          color: AppColors.crit, fontSize: 12))),
                    ])),
                ],

                const SizedBox(height: 20),

                // ── Submit button ─────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: _loading
                        ? [sl.card2, sl.card2]
                        : [AppColors.accent, AppColors.cyan]),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: _loading ? [] : [BoxShadow(
                        color: AppColors.accent.withOpacity(0.3),
                        blurRadius: 12, offset: const Offset(0, 4))]),
                    child: ElevatedButton(
                      onPressed: _loading
                        ? null
                        : (_isLogin ? _login : _register),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12))),
                      child: _loading
                        ? const SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white))
                        : Text(
                            _isLogin ? 'Login' : 'Create Account',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700))))),

                const SizedBox(height: 16),

                // ── Theme toggle ──────────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(sl.isDark
                      ? Icons.light_mode_outlined
                      : Icons.dark_mode_outlined,
                      color: sl.text4, size: 16),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: widget.toggleTheme,
                      child: Text(
                        sl.isDark ? 'Switch to Light Mode'
                                  : 'Switch to Dark Mode',
                        style: TextStyle(
                          color: sl.text4, fontSize: 11,
                          decoration: TextDecoration.underline))),
                  ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _loginFields(SL sl) => [
    _field('Username', _userCtrl, sl),
    const SizedBox(height: 12),
    _field('Password', _passCtrl, sl, obscure: true),
  ];

  List<Widget> _registerFields(SL sl) => [
    _field('Full Name', _regNameCtrl, sl,
      hint: 'e.g. Rajesh Kumar'),
    const SizedBox(height: 12),
    _field('Username', _regUserCtrl, sl,
      hint: 'Choose a username'),
    const SizedBox(height: 12),
    _field('Password', _regPassCtrl, sl, obscure: true),
    const SizedBox(height: 12),
    _field('Designation', _regDesigCtrl, sl,
      hint: 'e.g. AGM Safety, Safety Officer'),
    const SizedBox(height: 12),
    _field('Employee No. (P.No.)', _regPnoCtrl, sl,
      hint: 'Optional'),
    const SizedBox(height: 12),

    // ── Plant dropdown ────────────────────────────────────────────
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('PLANT / UNIT',
          style: TextStyle(
            color: sl.text4, fontSize: 9,
            fontWeight: FontWeight.w700, letterSpacing: 0.8)),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: sl.card2,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: sl.border)),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedPlant,
              isExpanded: true,
              dropdownColor: sl.card,
              style: TextStyle(color: sl.text1, fontSize: 13),
              hint: Text('Select your plant / unit',
                style: TextStyle(color: sl.text4, fontSize: 12)),
              icon: Icon(Icons.keyboard_arrow_down_rounded,
                color: sl.text3),
              items: _sailPlants.map((p) => DropdownMenuItem(
                value: p,
                child: Text(p,
                  style: TextStyle(color: sl.text1, fontSize: 12),
                  overflow: TextOverflow.ellipsis))).toList(),
              onChanged: (val) => setState(() {
                _selectedPlant = val;
                _isOtherPlant = val == 'Others';
                if (!_isOtherPlant) _regOtherPlantCtrl.clear();
              }),
            ),
          )),

        // Free-text field when "Others" is selected
        if (_isOtherPlant) ...[
          const SizedBox(height: 8),
          _field('Specify your plant / unit',
            _regOtherPlantCtrl, sl,
            hint: 'Enter plant or unit name'),
        ],
      ]),
  ];

  Widget _tab(String label, bool active, VoidCallback onTap) {
    final sl = SL.of(context);
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: active ? AppColors.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(9)),
          child: Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: active ? Colors.white : sl.text3,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              fontSize: 13)))));
  }

  Widget _field(String label, TextEditingController ctrl, SL sl,
      {bool obscure = false, String? hint}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(),
          style: TextStyle(
            color: sl.text4, fontSize: 9,
            fontWeight: FontWeight.w700, letterSpacing: 0.8)),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          obscureText: obscure,
          style: TextStyle(color: sl.text1, fontSize: 13),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: sl.text4, fontSize: 11),
            filled: true,
            fillColor: sl.card2,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: sl.border)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: sl.border)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(
                color: AppColors.accent, width: 1.5)))),
      ]);
  }
}
