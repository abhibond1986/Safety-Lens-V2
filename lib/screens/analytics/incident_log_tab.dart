import 'dart:ui';
import 'package:flutter/material.dart';
import '../../main.dart' show AppColors, SL;
import '../../services/local_db.dart';
import '../incident_detail_screen.dart';

class IncidentLogTab extends StatefulWidget {
  const IncidentLogTab({super.key});
  @override
  State<IncidentLogTab> createState() => _IncidentLogTabState();
}

class _IncidentLogTabState extends State<IncidentLogTab> {
  List<Map<String, dynamic>> _all = [];
  bool _loading = true;

  // Filters
  String _plantFilter = 'All';
  final Set<String> _sevFilter = {};
  final Set<String> _statusFilter = {};
  String _typeFilter = 'All';
  String _dateRange = '90 days';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final inc = await LocalDB.getIncidents();
    if (mounted) setState(() { _all = inc; _loading = false; });
  }

  List<Map<String, dynamic>> get _filtered {
    var list = List<Map<String, dynamic>>.from(_all);

    // Plant filter
    if (_plantFilter != 'All') {
      list = list.where((i) =>
          (i['plant']?.toString() ?? '').contains(_plantFilter)).toList();
    }

    // Severity filter
    if (_sevFilter.isNotEmpty) {
      list = list.where((i) =>
          _sevFilter.contains(i['severity']?.toString().toUpperCase() ?? 'MEDIUM')).toList();
    }

    // Status filter
    if (_statusFilter.isNotEmpty) {
      list = list.where((i) =>
          _statusFilter.contains(i['status']?.toString().toUpperCase() ?? 'OPEN')).toList();
    }

    // Type filter
    if (_typeFilter != 'All') {
      list = list.where((i) =>
          (i['type']?.toString().toUpperCase() ?? '') == _typeFilter).toList();
    }

    // Date range filter
    final now = DateTime.now();
    int days = 90;
    if (_dateRange == '7 days') days = 7;
    else if (_dateRange == '30 days') days = 30;
    else if (_dateRange == 'All') days = 99999;

    if (days < 99999) {
      final cutoff = now.subtract(Duration(days: days));
      list = list.where((i) {
        final d = DateTime.tryParse(i['date']?.toString() ?? '');
        return d != null && d.isAfter(cutoff);
      }).toList();
    }

    // Sort by date descending
    list.sort((a, b) =>
        (b['date']?.toString() ?? '').compareTo(a['date']?.toString() ?? ''));
    return list;
  }

  // Get unique plants from data
  List<String> get _plants {
    final s = <String>{};
    for (final i in _all) {
      final p = i['plant']?.toString() ?? '';
      if (p.isNotEmpty) s.add(p);
    }
    final list = s.toList()..sort();
    return ['All', ...list];
  }

  @override
  Widget build(BuildContext context) {
    final sl = SL.of(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    final filtered = _filtered;

    return Column(children: [
      // Filter section
      _filterSection(sl),
      // Summary
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Row(children: [
          Text('Showing ${filtered.length} of ${_all.length} incidents',
              style: TextStyle(color: sl.text3, fontSize: 11,
                  fontWeight: FontWeight.w600)),
          const Spacer(),
          if (_sevFilter.isNotEmpty || _statusFilter.isNotEmpty ||
              _plantFilter != 'All' || _typeFilter != 'All')
            GestureDetector(
              onTap: () => setState(() {
                _sevFilter.clear();
                _statusFilter.clear();
                _plantFilter = 'All';
                _typeFilter = 'All';
                _dateRange = '90 days';
              }),
              child: Text('Clear filters', style: TextStyle(
                  color: AppColors.accent, fontSize: 11,
                  fontWeight: FontWeight.w600)),
            ),
        ]),
      ),
      // Incident list
      Expanded(
        child: filtered.isEmpty
            ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.search_off_rounded, color: sl.text4, size: 40),
                const SizedBox(height: 8),
                Text('No incidents match filters',
                    style: TextStyle(color: sl.text3, fontSize: 13)),
              ]))
            : RefreshIndicator(
                onRefresh: _load,
                color: AppColors.accent,
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 80),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) => _incidentCard(sl, filtered[i]),
                ),
              ),
      ),
    ]);
  }

  // ═══════════════════════════════════════════════════════════════
  //  FILTER SECTION
  // ═══════════════════════════════════════════════════════════════
  Widget _filterSection(SL sl) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Row 1: Plant dropdown + Date range
        Row(children: [
          Expanded(child: _dropdownChip(sl, _plantFilter, _plants, (v) =>
              setState(() => _plantFilter = v))),
          const SizedBox(width: 8),
          _dropdownChip(sl, _dateRange,
              ['7 days', '30 days', '90 days', 'All'], (v) =>
              setState(() => _dateRange = v)),
        ]),
        const SizedBox(height: 8),
        // Row 2: Severity chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            _filterChip(sl, 'CRITICAL', _sevFilter, AppColors.crit),
            _filterChip(sl, 'HIGH', _sevFilter, AppColors.red),
            _filterChip(sl, 'MEDIUM', _sevFilter, AppColors.amber),
            _filterChip(sl, 'LOW', _sevFilter, AppColors.green),
            const SizedBox(width: 12),
            _typeChip(sl, 'All'),
            _typeChip(sl, 'AI_SCAN'),
            _typeChip(sl, 'NEAR_MISS'),
          ]),
        ),
        const SizedBox(height: 6),
        // Row 3: Status chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            _statusChip(sl, 'OPEN', AppColors.amber),
            _statusChip(sl, 'INVESTIGATING', AppColors.cyan),
            _statusChip(sl, 'ACTION TAKEN', const Color(0xFF8B5CF6)),
            _statusChip(sl, 'CLOSED', AppColors.green),
          ]),
        ),
      ]),
    );
  }

  Widget _dropdownChip(SL sl, String value, List<String> items,
      ValueChanged<String> onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
      decoration: BoxDecoration(
        color: sl.glassColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: sl.glassBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isDense: true,
          dropdownColor: sl.card,
          style: TextStyle(color: sl.text1, fontSize: 12),
          icon: Icon(Icons.keyboard_arrow_down, color: sl.text3, size: 16),
          items: items.map((v) => DropdownMenuItem(
              value: v, child: Text(v, style: TextStyle(
                  color: sl.text1, fontSize: 12),
                  overflow: TextOverflow.ellipsis))).toList(),
          onChanged: (v) { if (v != null) onChanged(v); },
        ),
      ),
    );
  }

  Widget _filterChip(SL sl, String label, Set<String> set, Color color) {
    final active = set.contains(label);
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: () => setState(() {
          if (active) set.remove(label); else set.add(label);
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: active ? color.withOpacity(0.15) : sl.glassColor,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
                color: active ? color : sl.glassBorder, width: active ? 1.5 : 1),
          ),
          child: Text(label, style: TextStyle(
              color: active ? color : sl.text3,
              fontSize: 10, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }

  Widget _statusChip(SL sl, String label, Color color) {
    final active = _statusFilter.contains(label);
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: () => setState(() {
          if (active) _statusFilter.remove(label);
          else _statusFilter.add(label);
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: active ? color.withOpacity(0.15) : sl.glassColor,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
                color: active ? color : sl.glassBorder, width: active ? 1.5 : 1),
          ),
          child: Text(label, style: TextStyle(
              color: active ? color : sl.text3,
              fontSize: 10, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }

  Widget _typeChip(SL sl, String label) {
    final active = _typeFilter == label;
    final displayLabel = label == 'AI_SCAN' ? 'AI Scan'
        : label == 'NEAR_MISS' ? 'Near Miss' : 'All Types';
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: () => setState(() => _typeFilter = label),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: active ? AppColors.accent.withOpacity(0.15) : sl.glassColor,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
                color: active ? AppColors.accent : sl.glassBorder,
                width: active ? 1.5 : 1),
          ),
          child: Text(displayLabel, style: TextStyle(
              color: active ? AppColors.accent : sl.text3,
              fontSize: 10, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  INCIDENT CARD
  // ═══════════════════════════════════════════════════════════════
  Widget _incidentCard(SL sl, Map<String, dynamic> inc) {
    final sev = inc['severity']?.toString().toUpperCase() ?? 'MEDIUM';
    final status = inc['status']?.toString().toUpperCase() ?? 'OPEN';
    final type = inc['type']?.toString().toUpperCase() ?? '';

    Color sevColor;
    switch (sev) {
      case 'CRITICAL': sevColor = AppColors.crit; break;
      case 'HIGH': sevColor = AppColors.red; break;
      case 'MEDIUM': sevColor = AppColors.amber; break;
      default: sevColor = AppColors.green;
    }

    Color statusColor;
    switch (status) {
      case 'CLOSED': statusColor = AppColors.green; break;
      case 'INVESTIGATING': statusColor = AppColors.cyan; break;
      case 'ACTION TAKEN': statusColor = const Color(0xFF8B5CF6); break;
      default: statusColor = AppColors.amber;
    }

    final date = inc['date']?.toString() ?? '';
    final dateStr = date.length >= 10 ? date.substring(0, 10) : date;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => IncidentDetailScreen(
              incident: inc, onStatusChanged: _load))),
        child: Container(
          decoration: BoxDecoration(
            color: sl.glassColor,
            borderRadius: BorderRadius.circular(12),
            border: Border(
              left: BorderSide(color: sevColor, width: 3),
              top: BorderSide(color: sl.glassBorder),
              right: BorderSide(color: sl.glassBorder),
              bottom: BorderSide(color: sl.glassBorder),
            ),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Title row
            Row(children: [
              Expanded(child: Text(
                inc['title']?.toString() ?? 'Untitled',
                style: TextStyle(color: sl.text1, fontSize: 13,
                    fontWeight: FontWeight.w700),
                maxLines: 1, overflow: TextOverflow.ellipsis,
              )),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: statusColor.withOpacity(0.3)),
                ),
                child: Text(status, style: TextStyle(
                    color: statusColor, fontSize: 8, fontWeight: FontWeight.w800)),
              ),
            ]),
            const SizedBox(height: 6),
            // Info row
            Row(children: [
              Icon(Icons.factory_outlined, color: sl.text4, size: 11),
              const SizedBox(width: 3),
              Flexible(child: Text(
                inc['plant']?.toString() ?? '—',
                style: TextStyle(color: sl.text3, fontSize: 10),
                overflow: TextOverflow.ellipsis,
              )),
              const SizedBox(width: 8),
              Icon(Icons.calendar_today_outlined, color: sl.text4, size: 10),
              const SizedBox(width: 3),
              Text(dateStr, style: TextStyle(color: sl.text3, fontSize: 10)),
              const Spacer(),
              // Severity badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: sevColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(4)),
                child: Text(sev, style: TextStyle(
                    color: sevColor, fontSize: 8, fontWeight: FontWeight.w800)),
              ),
            ]),
            const SizedBox(height: 4),
            // Bottom row: category + type + reported by
            Row(children: [
              if ((inc['wsaCategory']?.toString() ?? '').isNotEmpty) ...[
                Icon(Icons.label_outline, color: sl.text4, size: 10),
                const SizedBox(width: 3),
                Flexible(child: Text(inc['wsaCategory'].toString(),
                    style: TextStyle(color: sl.text4, fontSize: 9),
                    overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 8),
              ],
              if (type.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: (type == 'AI_SCAN' ? AppColors.accent : AppColors.amber)
                        .withOpacity(0.1),
                    borderRadius: BorderRadius.circular(3)),
                  child: Text(type == 'AI_SCAN' ? 'AI' : 'NM',
                      style: TextStyle(
                          color: type == 'AI_SCAN' ? AppColors.accent : AppColors.amber,
                          fontSize: 8, fontWeight: FontWeight.w700)),
                ),
              const Spacer(),
              if ((inc['reportedBy']?.toString() ?? '').isNotEmpty)
                Text(inc['reportedBy'].toString(),
                    style: TextStyle(color: sl.text4, fontSize: 9)),
            ]),
          ]),
        ),
      ),
    );
  }
}
