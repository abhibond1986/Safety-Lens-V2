import 'package:flutter/material.dart';
import '../main.dart';
import '../services/local_db.dart';
import 'login_screen.dart';
import 'ai_scan_tab.dart';
import 'near_miss_tab.dart';
import 'chat_tab.dart';
import 'reports_tab.dart';
import 'dashboard_tab.dart';
import 'admin_screen.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback toggleTheme;
  const HomeScreen({super.key, required this.toggleTheme});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tabIndex = 0;
  Map<String, dynamic>? _currentUser;
  bool _isDark = true;

  @override
  void initState() { super.initState(); _loadUser(); }

  Future<void> _loadUser() async {
    final user = await LocalDB.getCurrentUser();
    if (mounted) setState(() => _currentUser = user);
  }

  void _toggleTheme() {
    setState(() => _isDark = !_isDark);
    widget.toggleTheme();
  }

  Future<void> _signOut() async {
    await LocalDB.signOut();
    if (mounted) Navigator.pushReplacement(context, PageRouteBuilder(
      pageBuilder: (_, a, __) => LoginScreen(toggleTheme: widget.toggleTheme),
      transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
      transitionDuration: const Duration(milliseconds: 400)));
  }

  bool get _isAdmin {
    final desig = (_currentUser?['designation']?.toString() ?? '').toLowerCase();
    return desig.contains('agm') || desig.contains('gm') ||
           desig.contains('manager') || desig.contains('admin');
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final tabs = [
      DashboardTab(user: _currentUser, toggleTheme: _toggleTheme, onSignOut: _signOut),
      const AIScanTab(),
      const NearMissTab(),
      const ChatTab(),
      const ReportsTab(),
    ];

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: IndexedStack(index: _tabIndex, children: tabs),
      floatingActionButton: _tabIndex == 3 ? null : FloatingActionButton(
        onPressed: () => setState(() => _tabIndex = 3),
        backgroundColor: AppColors.purple,
        elevation: 4,
        child: const Icon(Icons.chat_bubble_outline_rounded, color: Colors.white, size: 22)),
      bottomNavigationBar: _bottomNav(),
    );
  }

  Widget _bottomNav() {
    const items = [
      BottomNavigationBarItem(
        icon: Icon(Icons.home_outlined),
        activeIcon: Icon(Icons.home_rounded),
        label: 'Home'),
      BottomNavigationBarItem(
        icon: Icon(Icons.document_scanner_outlined),
        activeIcon: Icon(Icons.document_scanner_rounded),
        label: 'AI Scan'),
      BottomNavigationBarItem(
        icon: Icon(Icons.warning_amber_outlined),
        activeIcon: Icon(Icons.warning_amber_rounded),
        label: 'Near Miss'),
      BottomNavigationBarItem(
        icon: Icon(Icons.chat_outlined),
        activeIcon: Icon(Icons.chat_rounded),
        label: 'Ask AI'),
      BottomNavigationBarItem(
        icon: Icon(Icons.bar_chart_outlined),
        activeIcon: Icon(Icons.bar_chart_rounded),
        label: 'Reports'),
    ];

    return Container(
      decoration: BoxDecoration(
        color: AppColors.bg2,
        border: const Border(top: BorderSide(color: AppColors.border, width: 0.5)),
        boxShadow: [BoxShadow(
          color: Colors.black.withOpacity(0.3),
          blurRadius: 20, offset: const Offset(0, -5))],
      ),
      child: SafeArea(
        child: SizedBox(
          height: 62,
          child: Row(
            children: List.generate(items.length, (i) {
              final selected = _tabIndex == i;
              final item = items[i];
              return Expanded(child: GestureDetector(
                onTap: () => setState(() => _tabIndex = i),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 4),
                        decoration: BoxDecoration(
                          color: selected
                              ? AppColors.accent.withOpacity(0.15)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(20)),
                        child: IconTheme(
                          data: IconThemeData(
                            size: 20,
                            color: selected ? AppColors.accent : AppColors.text4),
                          child: selected ? item.activeIcon! : item.icon),
                      ),
                      const SizedBox(height: 2),
                      Text(item.label!, style: TextStyle(
                        fontSize: 10,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                        color: selected ? AppColors.accent : AppColors.text4)),
                    ],
                  ),
                ),
              ));
            }),
          ),
        ),
      ),
    );
  }
}
