// lib/services/locale_service.dart
// Now delegates to I18n singleton for consistency.
// Kept for backward compatibility with existing imports.

import 'package:flutter/material.dart';
import 'i18n.dart';

class LocaleService extends ChangeNotifier {
  static final LocaleService _instance = LocaleService._internal();
  factory LocaleService() => _instance;
  LocaleService._internal() {
    // Mirror I18n changes
    I18n.instance.addListener(_onI18nChanged);
  }

  void _onI18nChanged() => notifyListeners();

  Locale get locale => I18n.instance.locale;

  Future<void> load() async {
    await I18n.init();
    notifyListeners();
  }

  Future<void> setLocale(Locale locale) async {
    await I18n.setLocale(locale.languageCode);
    // I18n.setLocale already notifies, which triggers _onI18nChanged
  }

  static const List<Locale> supportedLocales = [
    Locale('en'),
    Locale('hi'),
  ];

  static const List<Map<String, String>> languages = [
    {'code': 'en', 'name': 'English', 'native': 'English', 'flag': '🇬🇧'},
    {'code': 'hi', 'name': 'Hindi',   'native': 'हिंदी',    'flag': '🇮🇳'},
  ];
}
