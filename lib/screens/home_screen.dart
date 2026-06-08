// lib/screens/home_screen.dart
//
// ✅ Uses the new glass-UI HomeTab (replaces DashboardTab on tab 0)
// ✅ Passes user/toggleTheme/onSignOut/isDark to all 4 tabs that need them
// ✅ Keeps existing LanguageFab + bottom nav + sign-out flow
// ✅ Theme state lifted here so all tabs share the same isDark value

import 'package:flutter/material.dart';
import '../main.dart';
import '../services/local_db.dart';
import '../widgets/language_fab.dart';
import 'login_screen.dart';
import 'home_tab.dart';        // ← new glass-UI home
import 'ai_scan_tab.dart';
import 'near_miss_tab.dart';
import 'chat_tab.dart';
import 'reports_tab.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback toggleTheme;
  const HomeScreen({super.key, required this.toggleTheme});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  int _tabIndex = 0;
  Map<String, dynamic>? _user;
  late AnimationController _tabAnim;

  @override
  void initState() {
    super.initState();
    _tabAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
    _loadUser();
  }

  @override
  void dispose() {
    _tabAnim.dispose();
    super.dispose();
  }

  Future<void> _loadUser() async {
    final u = await LocalDB.getCurrentUser();
    if (mounted) setState(() => _user = u);
  }

  Future<void> _signOut() async {
    await LocalDB.signOut();
    if (!mounted) return;
    Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (_, a, __) =>
              LoginScreen(toggleTheme: widget.toggleTheme),
          transitionsBuilder: (_, a, __, child) =>
              FadeTransition(opacity: a, child: child),
          transitionDuration: const Duration(milliseconds: 400),
        ));
  }

  // Helper — change tab from inside any child (used by HomeTab's quick actions)
  void _changeTab(int i) {
    if (i >= 0 && i < 5 && i != _tabIndex) {
      setState(() => _tabIndex = i);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sl     = SL.of(context);
    final isDark = sl.isDark;

    final tabs = <Widget>[
      // 0 — Glass-UI Home (replaces DashboardTab)
      HomeTab(
        user: _user,
        toggleTheme: widget.toggleTheme,
        onSignOut: _signOut,
        isDark: isDark,
        onTabChange: _changeTab,
      ),
      // 1 — AI Scan
      AIScanTab(
        user: _user,
        toggleTheme: widget.toggleTheme,
        onSignOut: _signOut,
        isDark: isDark,
      ),
      // 2 — Near Miss
      NearMissTab(
        user: _user,
        toggleTheme: widget.toggleTheme,
        onSignOut: _signOut,
        isDark: isDark,
      ),
      // 3 — Ask AI (no props needed)
      const ChatTab(),
      // 4 — Reports
      ReportsTab(
        user: _user,
        toggleTheme: widget.toggleTheme,
        onSignOut: _signOut,
        isDark: isDark,
      ),
    ];

    return Scaffold(
      backgroundColor: sl.bg,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: KeyedSubtree(
          key: ValueKey(_tabIndex),
          child: tabs[_tabIndex],
        ),
      ),
      bottomNavigationBar: _bottomNav(sl),
      // Language FAB — visible on all tabs, sits above bottom nav
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 68),
        child: const LanguageFab(),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  Widget _bottomNav(SL sl) {
    final items = [
      _NavItem(Icons.home_outlined,             Icons.home_rounded,             'Home'),
      _NavItem(Icons.document_scanner_outlined, Icons.document_scanner_rounded, 'AI Scan'),
      _NavItem(Icons.warning_amber_outlined,    Icons.warning_amber_rounded,    'Near Miss'),
      _NavItem(Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded,    'Ask AI'),
      _NavItem(Icons.bar_chart_outlined,        Icons.bar_chart_rounded,        'Reports'),
    ];

    return Container(
      decoration: BoxDecoration(
        color: sl.bg2,
        border: Border(
          top: BorderSide(
              color: sl.border.withOpacity(0.5), width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(sl.isDark ? 0.3 : 0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: SizedBox(
          height: 60,
          child: Row(
            children: List.generate(items.length, (i) {
              final sel  = _tabIndex == i;
              final item = items[i];
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _tabIndex = i),
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 4),
                        decoration: BoxDecoration(
                          color: sel
                              ? AppColors.accent.withOpacity(0.15)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Icon(
                          sel ? item.activeIcon : item.icon,
                          size: 22,
                          color: sel ? AppColors.accent : sl.text4,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: sel
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: sel ? AppColors.accent : sl.text4,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon, activeIcon;
  final String label;
  const _NavItem(this.icon, this.activeIcon, this.label);
}
