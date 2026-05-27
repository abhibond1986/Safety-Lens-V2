import 'package:flutter/material.dart';
import '../main.dart';
import '../services/local_db.dart';
import 'login_screen.dart';
import 'ai_scan_tab.dart';
import 'near_miss_tab.dart';
import 'chat_tab.dart';
import 'reports_tab.dart';
import 'dashboard_tab.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback toggleTheme;
  const HomeScreen({super.key, required this.toggleTheme});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tabIndex = 0;
  Map<String, dynamic>? _currentUser;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final user = await LocalDB.getCurrentUser();
    if (mounted) setState(() => _currentUser = user);
  }

  Future<void> _signOut() async {
    await LocalDB.signOut();
    if (mounted) {
      Navigator.pushReplacement(context, MaterialPageRoute(
        builder: (_) => LoginScreen(toggleTheme: widget.toggleTheme),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [
      DashboardTab(user: _currentUser, toggleTheme: widget.toggleTheme, onSignOut: _signOut),
      const AIScanTab(),
      const NearMissTab(),
      const ChatTab(),
      const ReportsTab(),
    ];

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: tabs[_tabIndex],
      floatingActionButton: _tabIndex == 3 ? null : FloatingActionButton(
        onPressed: () => setState(() => _tabIndex = 3),
        backgroundColor: AppColors.purple,
        child: const Icon(Icons.chat_bubble_outline, color: Colors.white),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tabIndex,
        onTap: (i) => setState(() => _tabIndex = i),
        type: BottomNavigationBarType.fixed,
        backgroundColor: AppColors.bg2,
        selectedItemColor: AppColors.accent,
        unselectedItemColor: AppColors.text4,
        selectedFontSize: 10,
        unselectedFontSize: 10,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined, size: 18), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.camera_alt_outlined, size: 18), label: 'AI Scan'),
          BottomNavigationBarItem(icon: Icon(Icons.warning_amber_outlined, size: 18), label: 'Near Miss'),
          BottomNavigationBarItem(icon: Icon(Icons.chat_outlined, size: 18), label: 'Ask AI'),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart, size: 18), label: 'Reports'),
        ],
      ),
    );
  }
}
