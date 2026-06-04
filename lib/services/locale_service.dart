// lib/services/locale_service.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocaleService extends ChangeNotifier {
  static const String _key = 'selected_locale';

  Locale _locale = const Locale('en');
  Locale get locale => _locale;

  static final LocaleService _instance = LocaleService._internal();
  factory LocaleService() => _instance;
  LocaleService._internal();

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_key) ?? 'en';
    _locale = Locale(code);
    notifyListeners();
  }

  Future<void> setLocale(Locale locale) async {
    if (_locale == locale) return;
    _locale = locale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, locale.languageCode);
    notifyListeners();
  }

  static const List<Locale> supportedLocales = [
    Locale('en'),
    Locale('hi'),
    Locale('bn'),
    Locale('or'),
  ];

  static const List<Map<String, String>> languages = [
    {'code': 'en', 'name': 'English', 'native': 'English', 'flag': '🇬🇧'},
    {'code': 'hi', 'name': 'Hindi',   'native': 'हिंदी',    'flag': '🇮🇳'},
    {'code': 'bn', 'name': 'Bengali', 'native': 'বাংলা',    'flag': '🇮🇳'},
    {'code': 'or', 'name': 'Odia',    'native': 'ଓଡ଼ିଆ',   'flag': '🇮🇳'},
  ];
}
