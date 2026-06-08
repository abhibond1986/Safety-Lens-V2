// lib/widgets/universal_app_bar.dart
// Shared header used at the top of Home / AI Scan / Near Miss / Reports.
// Provides:
//   • SAIL logo + screen title
//   • User avatar (tap → profile menu: name, designation, plant, sign out)
//   • Theme toggle (sun/moon)
//   • Language toggle (EN ⇄ हिन्दी)
//   • Export to Google Sheets button
//
// Usage:
//   UniversalAppBar(
//     title: I18n.t('home.dashboard'),
//     user: currentUser,
//     toggleTheme: () => setState(() => isDark = !isDark),
//     onSignOut: _signOut,
//   )

import 'package:flutter/material.dart';
import '../main.dart' show AppColors, SL;
import '../services/i18n.dart';
import '../services/sync_service.dart';
import '../services/local_db.dart';
import '../utils/sail_logo.dart';

class UniversalAppBar extends StatefulWidget implements PreferredSizeWidget {
  final String title;
  final String? subtitle;
  final Map<String, dynamic>? user;
  final VoidCallback? toggleTheme;
  final VoidCallback? onSignOut;
  final bool isDark;

  /// Optional override — defaults to "export all incidents to Sheets"
  final Future<void> Function()? onExport;

  /// Show export button (default true). Hide on tabs where it doesn't make sense.
  final bool showExport;

  const UniversalAppBar({
    super.key,
    required this.title,
    this.subtitle,
    this.user,
    this.toggleTheme,
    this.onSignOut,
    this.isDark = true,
    this.onExport,
    this.showExport = true,
  });

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  State<UniversalAppBar> createState() => _UniversalAppBarState();
}

class _UniversalAppBarState extends State<UniversalAppBar> {
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    I18n.instance.addListener(_rebuild);
  }

  @override
  void dispose() {
    I18n.instance.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() { if (mounted) setState(() {}); }

  // ── EXPORT TO SHEETS ─────────────────────────────────────────
  Future<void> _doExport() async {
    if (widget.onExport != null) {
      setState(() => _exporting = true);
      try { await widget.onExport!(); }
      finally { if (mounted) setState(() => _exporting = false); }
      return;
    }

    // Default: push all local incidents to Sheets
    setState(() => _exporting = true);
    try {
      final all = await LocalDB.getIncidents();
      if (all.isEmpty) {
        if (mounted) _snack(I18n.t('home.noData'), AppColors.amber);
        return;
      }
      int success = 0;
      for (final inc in all) {
        final ok = await SyncService.pushIncident(inc).catchError((_) => false);
        if (ok == true) success++;
      }
      if (mounted) {
        _snack('$success / ${all.length} ${I18n.t('msg.savedSheets')}',
            success > 0 ? AppColors.green : AppColors.red);
      }
    } catch (e) {
      if (mounted) _snack('${I18n.t('msg.networkError')}: $e', AppColors.red);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(12),
      duration: const Duration(seconds: 3),
    ));
  }

  // ── PROFILE MENU ─────────────────────────────────────────────
  void _showProfileMenu() {
    final sl = SL.of(context);
    final u  = widget.user ?? {};
    showModalBottomSheet(
      context: context,
      backgroundColor: sl.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Drag handle
            Container(width: 40, height: 4,
              decoration: BoxDecoration(
                color: sl.border, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 18),

            // Avatar + name
            Row(children: [
              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [AppColors.accent, Color(0xFF6F45D9)])),
                child: Center(child: Text(
                  (u['name']?.toString().isNotEmpty == true
                      ? u['name'].toString()[0] : '?').toUpperCase(),
                  style: const TextStyle(color: Colors.white,
                      fontSize: 22, fontWeight: FontWeight.w800))),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(u['name']?.toString() ?? 'User',
                    style: TextStyle(color: sl.text1, fontSize: 16,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(u['designation']?.toString() ?? '—',
                    style: TextStyle(color: sl.text3, fontSize: 12)),
                if ((u['pno']?.toString() ?? '').isNotEmpty)
                  Text('${I18n.t('settings.pno')}: ${u['pno']}',
                      style: TextStyle(color: sl.text4, fontSize: 11)),
              ])),
            ]),
            const SizedBox(height: 8),
            if ((u['plant']?.toString() ?? '').isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.accent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.factory_outlined, color: AppColors.accent, size: 12),
                  const SizedBox(width: 5),
                  Text(u['plant'].toString(),
                      style: const TextStyle(color: AppColors.accent,
                          fontSize: 11, fontWeight: FontWeight.w600)),
                ])),

            const Divider(height: 28),

            // Theme + language toggles
            _menuRow(
              icon: widget.isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
              label: widget.isDark ? I18n.t('settings.darkMode') : I18n.t('settings.lightMode'),
              trailing: Switch(
                value: widget.isDark,
                activeColor: AppColors.accent,
                onChanged: (_) {
                  if (widget.toggleTheme != null) widget.toggleTheme!();
                  Navigator.pop(ctx);
                },
              ),
              sl: sl,
            ),
            _menuRow(
              icon: Icons.language_rounded,
              label: I18n.t('settings.language'),
              trailing: GestureDetector(
                onTap: () async {
                  await I18n.toggle();
                  if (mounted) setState(() {});
                  if (Navigator.canPop(ctx)) Navigator.pop(ctx);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.amber.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.amber.withOpacity(0.4))),
                  child: Text(
                    I18n.currentLang == 'en' ? 'EN  →  हिं' : 'हिं  →  EN',
                    style: const TextStyle(color: AppColors.amber,
                        fontSize: 12, fontWeight: FontWeight.w700)),
                ),
              ),
              sl: sl,
            ),
            _menuRow(
              icon: Icons.cloud_upload_rounded,
              label: I18n.t('settings.exportData'),
              trailing: const Icon(Icons.chevron_right_rounded,
                  color: AppColors.text3),
              onTap: () { Navigator.pop(ctx); _doExport(); },
              sl: sl,
            ),

            const Divider(height: 24),

            // Sign out
            if (widget.onSignOut != null)
              GestureDetector(
                onTap: () { Navigator.pop(ctx); widget.onSignOut!(); },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.red.withOpacity(0.3))),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.logout_rounded, color: AppColors.red, size: 18),
                    const SizedBox(width: 8),
                    Text(I18n.t('settings.signOut'),
                        style: const TextStyle(color: AppColors.red,
                            fontSize: 13, fontWeight: FontWeight.w700)),
                  ]))),
          ]),
        ),
      ),
    );
  }

  Widget _menuRow({
    required IconData icon, required String label,
    Widget? trailing, VoidCallback? onTap, required SL sl,
  }) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      child: Row(children: [
        Icon(icon, color: sl.text2, size: 18),
        const SizedBox(width: 12),
        Expanded(child: Text(label,
            style: TextStyle(color: sl.text1, fontSize: 13,
                fontWeight: FontWeight.w600))),
        if (trailing != null) trailing,
      ]),
    ));

  // ── BUILD ────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final sl = SL.of(context);
    final initial = (widget.user?['name']?.toString().isNotEmpty == true
        ? widget.user!['name'].toString()[0] : '?').toUpperCase();

    return Container(
      decoration: BoxDecoration(
        color: sl.bg2,
        border: Border(bottom: BorderSide(color: sl.border, width: 0.5))),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 8, 8),
          child: Row(children: [
            // SAIL logo
            SailLogo.widget(size: 36),
            const SizedBox(width: 10),

            // Title + subtitle
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.title,
                    style: TextStyle(color: sl.text1, fontSize: 15,
                        fontWeight: FontWeight.w700, height: 1.1),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                if (widget.subtitle != null)
                  Text(widget.subtitle!,
                      style: TextStyle(color: sl.text4, fontSize: 9.5),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
              ])),

            // Language quick toggle
            _IconBtn(
              icon: Icons.translate_rounded,
              label: I18n.currentLang.toUpperCase(),
              color: AppColors.amber,
              onTap: () async { await I18n.toggle(); if (mounted) setState(() {}); },
            ),
            const SizedBox(width: 4),

            // Theme quick toggle
            if (widget.toggleTheme != null)
              IconButton(
                tooltip: widget.isDark
                    ? I18n.t('settings.lightMode')
                    : I18n.t('settings.darkMode'),
                icon: Icon(widget.isDark
                    ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                    color: sl.text2, size: 20),
                onPressed: widget.toggleTheme,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),

            // Export to Sheets
            if (widget.showExport)
              IconButton(
                tooltip: I18n.t('settings.exportData'),
                icon: _exporting
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.green))
                    : const Icon(Icons.cloud_upload_outlined,
                        color: AppColors.green, size: 20),
                onPressed: _exporting ? null : _doExport,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),

            // User avatar
            GestureDetector(
              onTap: _showProfileMenu,
              child: Container(
                margin: const EdgeInsets.only(left: 4),
                width: 34, height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [AppColors.accent, Color(0xFF6F45D9)])),
                child: Center(child: Text(initial,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13, fontWeight: FontWeight.w800))),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _IconBtn({required this.icon, required this.label,
    required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 30, padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 12),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(color: color, fontSize: 10,
                  fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }
}
