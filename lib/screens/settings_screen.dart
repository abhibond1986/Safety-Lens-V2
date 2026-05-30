import 'package:flutter/material.dart';
import '../main.dart';
import '../services/sync_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _urlCtrl = TextEditingController();
  bool _busy = false;
  String _status = '';
  DateTime? _lastSync;
  int _pendingCount = 0;
  bool _backendOk = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final url = await SyncService.getBackendUrl();
    final lastSync = await SyncService.getLastSyncTime();
    final pending = await SyncService.pendingQueueSize();
    final configured = await SyncService.isConfigured;
    if (!mounted) return;
    setState(() {
      _urlCtrl.text = (url == 'YOUR_APPS_SCRIPT_URL_HERE') ? '' : url;
      _lastSync = lastSync;
      _pendingCount = pending;
      _backendOk = configured;
    });
  }

  Future<void> _saveUrl() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) {
      _showSnack('Please paste the Apps Script Web App URL', AppColors.red);
      return;
    }
    if (!url.startsWith('https://script.google.com/')) {
      _showSnack('URL should start with https://script.google.com/', AppColors.red);
      return;
    }
    await SyncService.setBackendUrl(url);
    await _load();
    _showSnack('Backend URL saved', AppColors.green);
  }

  Future<void> _testConnection() async {
    setState(() { _busy = true; _status = 'Testing connection...'; });
    final result = await SyncService.ping();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result['ok'] == true) {
        _status = 'Connected! Backend responded at ${result['time']}';
      } else {
        _status = 'Failed: ${result['error'] ?? 'Unknown error'}';
      }
    });
  }

  Future<void> _syncNow() async {
    setState(() { _busy = true; _status = 'Syncing...'; });
    final result = await SyncService.fullSync();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result['ok'] == true) {
        _status = 'Sync complete · Pushed: ${result['pushed']} · Pulled: ${result['pulled']}';
      } else {
        _status = '${result['error']}';
      }
    });
    await _load();
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg2,
        title: const Text('Settings · Sync',
          style: TextStyle(color: AppColors.text1, fontSize: 15, fontWeight: FontWeight.w600)),
        iconTheme: const IconThemeData(color: AppColors.text1),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _backendOk ? AppColors.green.withOpacity(0.1) : AppColors.amber.withOpacity(0.1),
                border: Border.all(color: _backendOk ? AppColors.green : AppColors.amber),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(_backendOk ? Icons.cloud_done : Icons.cloud_off,
                      color: _backendOk ? AppColors.green : AppColors.amber, size: 22),
                    const SizedBox(width: 8),
                    Text(_backendOk ? 'Backend Configured' : 'Backend Not Configured',
                      style: TextStyle(color: _backendOk ? AppColors.green : AppColors.amber,
                        fontSize: 13, fontWeight: FontWeight.w700)),
                  ]),
                  const SizedBox(height: 6),
                  Text(
                    _backendOk
                      ? 'Reports will sync to Google Sheets'
                      : 'Reports save locally only. Add Apps Script URL to enable sync.',
                    style: const TextStyle(color: AppColors.text2, fontSize: 11, height: 1.4),
                  ),
                  if (_lastSync != null) ...[
                    const SizedBox(height: 4),
                    Text('Last sync: ${_lastSync!.toLocal()}',
                      style: const TextStyle(color: AppColors.text4, fontSize: 9)),
                  ],
                  if (_pendingCount > 0) ...[
                    const SizedBox(height: 4),
                    Text('$_pendingCount items waiting to sync',
                      style: const TextStyle(color: AppColors.amber, fontSize: 10, fontWeight: FontWeight.w600)),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text('GOOGLE APPS SCRIPT URL',
              style: TextStyle(color: AppColors.text4, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
            const SizedBox(height: 6),
            const Text(
              'Paste the Web App URL from your Apps Script deployment.',
              style: TextStyle(color: AppColors.text3, fontSize: 10, height: 1.4),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _urlCtrl,
              style: const TextStyle(color: AppColors.text1, fontSize: 11),
              maxLines: 2,
              decoration: InputDecoration(
                filled: true,
                fillColor: AppColors.card2,
                hintText: 'https://script.google.com/macros/s/.../exec',
                hintStyle: const TextStyle(color: AppColors.text4, fontSize: 10),
                contentPadding: const EdgeInsets.all(10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: ElevatedButton(
                onPressed: _busy ? null : _saveUrl,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('Save URL', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              )),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton(
                onPressed: _busy ? null : _testConnection,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.accent, width: 2),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('Test Connection', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w600)),
              )),
            ]),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: _busy || !_backendOk ? null : _syncNow,
              icon: const Icon(Icons.sync, color: Colors.white),
              label: const Text('Sync Now (Push + Pull)',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.green,
                padding: const EdgeInsets.symmetric(vertical: 14),
                minimumSize: const Size(double.infinity, 0),
              ),
            ),
            if (_status.isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.card2,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(_status,
                  style: const TextStyle(color: AppColors.text1, fontSize: 11, height: 1.4)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
