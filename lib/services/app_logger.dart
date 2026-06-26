// lib/services/app_logger.dart
// ★ v25: Structured error logging service.
// Replaces silent catch(_) blocks with traceable, diagnosable error records.
// Stores last 200 log entries in SharedPreferences for admin inspection.

import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

enum LogLevel { debug, info, warn, error, critical }

class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String source;   // e.g. 'SyncService', 'GeminiVision'
  final String message;
  final String? details; // stack trace or extra context
  final String? action;  // what was being attempted

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.source,
    required this.message,
    this.details,
    this.action,
  });

  Map<String, dynamic> toJson() => {
    'ts': timestamp.toIso8601String(),
    'lvl': level.name,
    'src': source,
    'msg': message,
    if (details != null) 'det': details,
    if (action != null) 'act': action,
  };

  factory LogEntry.fromJson(Map<String, dynamic> j) => LogEntry(
    timestamp: DateTime.tryParse(j['ts'] ?? '') ?? DateTime.now(),
    level: LogLevel.values.firstWhere(
      (l) => l.name == j['lvl'], orElse: () => LogLevel.info),
    source: j['src'] ?? '',
    message: j['msg'] ?? '',
    details: j['det'],
    action: j['act'],
  );

  @override
  String toString() => '[${level.name.toUpperCase()}] $source: $message';
}

class AppLogger {
  static const String _kLogs = 'app_error_logs';
  static const int _maxEntries = 200;
  static final List<LogEntry> _memoryLog = [];

  /// Log a debug message (only in debug mode)
  static void debug(String source, String message, {String? action}) {
    _log(LogLevel.debug, source, message, action: action);
  }

  /// Log an informational message
  static void info(String source, String message, {String? action}) {
    _log(LogLevel.info, source, message, action: action);
  }

  /// Log a warning (something unexpected but non-fatal)
  static void warn(String source, String message, {String? details, String? action}) {
    _log(LogLevel.warn, source, message, details: details, action: action);
  }

  /// Log an error (operation failed)
  static void error(String source, String message, {Object? error, StackTrace? stack, String? action}) {
    final det = [
      if (error != null) error.toString(),
      if (stack != null) stack.toString().split('\n').take(5).join('\n'),
    ].join('\n');
    _log(LogLevel.error, source, message, details: det.isEmpty ? null : det, action: action);
  }

  /// Log a critical error (data loss, security, crash)
  static void critical(String source, String message, {Object? error, StackTrace? stack, String? action}) {
    final det = [
      if (error != null) error.toString(),
      if (stack != null) stack.toString().split('\n').take(10).join('\n'),
    ].join('\n');
    _log(LogLevel.critical, source, message, details: det.isEmpty ? null : det, action: action);
  }

  static void _log(LogLevel level, String source, String message,
      {String? details, String? action}) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      source: source,
      message: message,
      details: details,
      action: action,
    );

    _memoryLog.add(entry);
    if (_memoryLog.length > _maxEntries) {
      _memoryLog.removeRange(0, _memoryLog.length - _maxEntries);
    }

    // Also print for debug console
    debugPrint(entry.toString());

    // Persist errors and above
    if (level.index >= LogLevel.error.index) {
      _persistAsync(entry);
    }
  }

  static Future<void> _persistAsync(LogEntry entry) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kLogs);
      List<Map<String, dynamic>> logs = [];
      if (raw != null) {
        try {
          logs = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
        } catch (_) {}
      }
      logs.add(entry.toJson());
      if (logs.length > _maxEntries) {
        logs = logs.sublist(logs.length - _maxEntries);
      }
      await prefs.setString(_kLogs, jsonEncode(logs));
    } catch (_) {
      // Can't log a logging failure — just ignore
    }
  }

  /// Get all persisted error logs (for admin panel)
  static Future<List<LogEntry>> getPersistedLogs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kLogs);
      if (raw == null) return [];
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      return list.map((j) => LogEntry.fromJson(j)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Get recent in-memory logs (all levels, current session only)
  static List<LogEntry> getRecentLogs({LogLevel? minLevel}) {
    if (minLevel == null) return List.unmodifiable(_memoryLog);
    return _memoryLog.where((e) => e.level.index >= minLevel.index).toList();
  }

  /// Clear all persisted logs
  static Future<void> clearLogs() async {
    _memoryLog.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kLogs);
  }

  /// Get error count since last clear (for badge/indicator)
  static int get errorCount =>
      _memoryLog.where((e) => e.level.index >= LogLevel.error.index).length;

  /// Summary for diagnostics
  static Map<String, dynamic> getSummary() {
    final now = DateTime.now();
    final last24h = _memoryLog.where(
      (e) => now.difference(e.timestamp).inHours < 24);
    return {
      'totalInMemory': _memoryLog.length,
      'errorsLast24h': last24h.where((e) => e.level.index >= LogLevel.error.index).length,
      'warningsLast24h': last24h.where((e) => e.level == LogLevel.warn).length,
      'oldestEntry': _memoryLog.isNotEmpty ? _memoryLog.first.timestamp.toIso8601String() : null,
      'newestEntry': _memoryLog.isNotEmpty ? _memoryLog.last.timestamp.toIso8601String() : null,
    };
  }
}
