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
  // Login fields
  final _liUsername = TextEditingController(text: 'abhishek.kumar');
  final _liPassword = TextEditingController(text: 'demo');
  // Register fields
  final _rgName = TextEditingController(text: 'Abhishek Kumar');
  final _rgDesig = TextEditingController(text: 'AGM');
  final _rgPlant = TextEditingController(text: 'SAIL Safety Organisation');
  final _rgPno = TextEditingController();
  final _rgMobile = TextEditingController();
  final _rgEmail = TextEditingController();
  final _rgPassword = TextEditingController();

  bool _busy = false;

  Future<void> _doLogin() async {
    setState(() => _busy = true);
    final user = await LocalDB.signIn(_liUsername.text.trim(), _liPassword.text);
    setState(() => _busy = false);
    if (user != null && mounted) {
      Navigator.pushReplacement(context, MaterialPageRoute(
        builder: (_) => HomeScreen(toggleTheme: widget.toggleTheme),
      ));
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid username or password'), backgroundColor: AppColors.red),
      );
    }
  }

  Future<void> _doRegister() async {
    if (_rgName.text.trim().isEmpty || _rgDesig.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill name and designation'), backgroundColor: AppColors.red),
      );
      return;
    }
    if (_rgPassword.text.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password must be at least 6 characters'), backgroundColor: AppColors.red),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Account created for ${user['name']}'), backgroundColor: AppColors.green),
      );
      Navigator.pushReplacement(context, MaterialPageRoute(
        builder: (_) => HomeScreen(toggleTheme: widget.toggleTheme),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              Center(
                child: Column(
                  children: [
                    const SailLogoTile(size: 90),
                    const SizedBox(height: 14),
                    const BrandTitle(size: 28),
                    const SizedBox(height: 6),
                    Text('SAIL · IS 14489',
                      style: TextStyle(color: AppColors.text4, fontSize: 10, letterSpacing: 1.8, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _toggleRow(),
              const SizedBox(height: 14),
              _isLogin ? _loginForm() : _registerForm(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toggleRow() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: [
          Expanded(child: _toggleBtn('Sign In', Icons.login, true)),
          Expanded(child: _toggleBtn('Register', Icons.person_add, false)),
        ],
      ),
    );
  }

  Widget _toggleBtn(String label, IconData icon, bool isLogin) {
    final selected = _isLogin == isLogin;
    return GestureDetector(
      onTap: () => setState(() => _isLogin = isLogin),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: selected ? Colors.white : AppColors.text3),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(
              color: selected ? Colors.white : AppColors.text3,
              fontSize: 11, fontWeight: FontWeight.w600,
            )),
          ],
        ),
      ),
    );
  }

  Widget _loginForm() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _label('Username or email'),
          _input(_liUsername),
          const SizedBox(height: 10),
          _label('Password'),
          _input(_liPassword, isPassword: true),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: _busy ? null : _doLogin,
            icon: const Icon(Icons.login, size: 14, color: Colors.white),
            label: const Text('Sign In', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: AppColors.accentDark, width: 2)),
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: Wrap(
              children: [
                Text('New user? ', style: TextStyle(color: AppColors.text3, fontSize: 11)),
                GestureDetector(
                  onTap: () => setState(() => _isLogin = false),
                  child: const Text('Create account',
                    style: TextStyle(color: AppColors.accent, fontSize: 11, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _registerForm() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Create account', style: TextStyle(color: AppColors.text1, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          _label('Full name'), _input(_rgName),
          const SizedBox(height: 10),
          _label('Designation'), _input(_rgDesig),
          const SizedBox(height: 10),
          _label('Plant / Unit'), _input(_rgPlant),
          const SizedBox(height: 10),
          _label('P.No'), _input(_rgPno, hint: 'e.g. SAIL-2024-1234'),
          const SizedBox(height: 10),
          _label('Mobile'), _input(_rgMobile, hint: '10-digit', kbType: TextInputType.phone),
          const SizedBox(height: 10),
          _label('Email'), _input(_rgEmail, hint: 'name@sail.in', kbType: TextInputType.emailAddress),
          const SizedBox(height: 10),
          _label('Password'), _input(_rgPassword, hint: 'Min 6 chars', isPassword: true),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: _busy ? null : _doRegister,
            icon: const Icon(Icons.person_add, size: 14, color: Colors.white),
            label: const Text('Create Account', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.green,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: Color(0xFF047857), width: 2)),
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: Wrap(
              children: [
                Text('Already registered? ', style: TextStyle(color: AppColors.text3, fontSize: 11)),
                GestureDetector(
                  onTap: () => setState(() => _isLogin = true),
                  child: const Text('Sign in',
                    style: TextStyle(color: AppColors.accent, fontSize: 11, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: Text(text, style: const TextStyle(color: AppColors.text3, fontSize: 10, fontWeight: FontWeight.w600)),
  );

  Widget _input(TextEditingController c, {String? hint, bool isPassword = false, TextInputType? kbType}) {
    return TextField(
      controller: c,
      obscureText: isPassword,
      keyboardType: kbType,
      style: const TextStyle(color: AppColors.text1, fontSize: 12),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: AppColors.text4, fontSize: 11),
        filled: true,
        fillColor: AppColors.bg2,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.border, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.border, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
        ),
      ),
    );
  }
}
