// lib/services/i18n.dart
// Lightweight i18n for SAIL Safety Lens
// Usage:
//   String x = I18n.t('home.welcome');
//   I18n.setLocale(Locale('hi'));
//   listen to I18n.instance to rebuild on language change
//
// Wrap any text: Text(I18n.t('key'))

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class I18n extends ChangeNotifier {
  static final I18n instance = I18n._();
  I18n._();

  static const _kLocaleKey = 'app_locale_lang';

  Locale _locale = const Locale('en');
  Locale get locale => _locale;

  static String get currentLang => instance._locale.languageCode;

  /// Read saved preference + initialise locale. Call once in main().
  static Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    final saved = p.getString(_kLocaleKey);
    if (saved == 'hi' || saved == 'en') {
      instance._locale = Locale(saved!);
    }
  }

  /// Switch language and persist
  static Future<void> setLocale(String code) async {
    if (code != 'hi' && code != 'en') return;
    if (instance._locale.languageCode == code) return;
    instance._locale = Locale(code);
    final p = await SharedPreferences.getInstance();
    await p.setString(_kLocaleKey, code);
    instance.notifyListeners();
  }

  /// Toggle between hi and en
  static Future<void> toggle() async {
    await setLocale(currentLang == 'en' ? 'hi' : 'en');
  }

  /// Lookup translation by dot-notation key; falls back to key itself if missing.
  static String t(String key, {Map<String, String>? args}) {
    final table = currentLang == 'hi' ? _hi : _en;
    var value = table[key] ?? _en[key] ?? key;
    if (args != null) {
      args.forEach((k, v) => value = value.replaceAll('{$k}', v));
    }
    return value;
  }

  // ──────────────────────────────────────────────────────────────
  //  ENGLISH STRINGS
  // ──────────────────────────────────────────────────────────────
  static const Map<String, String> _en = {
    // App
    'app.name'             : 'SAIL Safety Lens',
    'app.tagline'          : 'AI Safety Platform',

    // Common
    'common.save'          : 'Save',
    'common.cancel'        : 'Cancel',
    'common.close'         : 'Close',
    'common.delete'        : 'Delete',
    'common.edit'          : 'Edit',
    'common.add'           : 'Add',
    'common.submit'        : 'Submit',
    'common.export'        : 'Export',
    'common.search'        : 'Search',
    'common.filter'        : 'Filter',
    'common.refresh'       : 'Refresh',
    'common.sync'          : 'Sync',
    'common.loading'       : 'Loading…',
    'common.success'       : 'Success',
    'common.failed'        : 'Failed',
    'common.yes'           : 'Yes',
    'common.no'            : 'No',
    'common.ok'            : 'OK',
    'common.back'          : 'Back',
    'common.next'          : 'Next',
    'common.continue'      : 'Continue',
    'common.retry'         : 'Retry',

    // Bottom tabs
    'tab.home'             : 'Home',
    'tab.aiScan'           : 'AI Scan',
    'tab.nearMiss'         : 'Near Miss',
    'tab.askAi'            : 'Ask AI',
    'tab.reports'          : 'Reports',

    // Home screen
    'home.welcome'         : 'Welcome',
    'home.dashboard'       : 'Safety Dashboard',
    'home.totalCases'      : 'Total Cases',
    'home.openCases'       : 'Open',
    'home.closedCases'     : 'Closed',
    'home.criticalCases'   : 'Critical',
    'home.thisMonth'       : 'This Month',
    'home.thisWeek'        : 'This Week',
    'home.today'           : 'Today',
    'home.quickActions'    : 'Quick Actions',
    'home.recentActivity'  : 'Recent Activity',
    'home.safetyStats'     : 'Safety Statistics',
    'home.byPlant'         : 'By Plant',
    'home.bySeverity'      : 'By Severity',
    'home.daysSinceLti'    : 'Days since LTI',
    'home.safetyScore'     : 'Safety Score',
    'home.viewAll'         : 'View All',
    'home.noData'          : 'No incidents yet',
    'home.startScan'       : 'Start AI Scan',
    'home.reportNearMiss'  : 'Report Near Miss',
    'home.viewReports'     : 'View Reports',
    'home.askExpert'       : 'Ask Expert',
    'home.greeting.morning': 'Good morning',
    'home.greeting.afternoon': 'Good afternoon',
    'home.greeting.evening': 'Good evening',
    'home.weeklyTrend'     : 'Weekly Trend',
    'home.topHazards'      : 'Top Hazards',

    // AI Scan
    'aiScan.title'         : 'AI Hazard Scan',
    'aiScan.subtitle'      : 'Gemini Vision · IS 14489 · WSA 13 · Factories Act',
    'aiScan.capture'       : 'Capture',
    'aiScan.aiScan'        : 'AI Scan',
    'aiScan.review'        : 'Review',
    'aiScan.save'          : 'Save',
    'aiScan.mitigate'      : 'Mitigate',
    'aiScan.takePhoto'     : 'Capture workplace photo',
    'aiScan.aiDetects'     : 'AI detects hazards & marks them on photo',
    'aiScan.camera'        : 'Camera',
    'aiScan.gallery'       : 'Gallery',
    'aiScan.analyzing'     : 'Analyzing photo…',
    'aiScan.summary'       : 'Summary',
    'aiScan.hazardAnalysis': 'Hazard Analysis',
    'aiScan.overallRisk'   : 'Overall Risk',
    'aiScan.confidence'    : 'confidence',
    'aiScan.savedToSheets' : 'Saved to Google Sheets',
    'aiScan.newScan'       : 'New',
    'aiScan.pdf'           : 'PDF',
    'aiScan.howItWorks'    : 'How AI Hazard Scan works',

    // Near Miss
    'nearMiss.title'       : 'Near Miss / Unsafe Condition',
    'nearMiss.brief'       : 'Brief description',
    'nearMiss.briefHint'   : 'What happened? (Voice or text)',
    'nearMiss.plant'       : 'Plant',
    'nearMiss.dept'        : 'Department',
    'nearMiss.location'    : 'Location',
    'nearMiss.severity'    : 'Severity',
    'nearMiss.people'      : 'No. of people involved',
    'nearMiss.description' : 'Detailed description',
    'nearMiss.action'      : 'Immediate action taken',
    'nearMiss.uploadImage' : 'Upload Image',
    'nearMiss.submit'      : 'Submit Report',
    'nearMiss.submitExport': 'Submit + Export PDF',
    'nearMiss.recording'   : 'Listening…',
    'nearMiss.tapToTalk'   : 'Tap mic to dictate',

    // Reports
    'reports.title'        : 'Reports',
    'reports.all'          : 'All',
    'reports.open'         : 'Open',
    'reports.closed'       : 'Closed',
    'reports.critical'     : 'Critical',
    'reports.high'         : 'High',
    'reports.medium'       : 'Medium',
    'reports.low'          : 'Low',
    'reports.plant'        : 'Plant / Unit',
    'reports.byPlant'      : 'Filter by Plant',
    'reports.allPlants'    : 'All Plants',
    'reports.export'       : 'Export PDF',
    'reports.exportSheets' : 'Open in Sheets',
    'reports.noReports'    : 'No reports found',
    'reports.sortBy'       : 'Sort by',
    'reports.date'         : 'Date',
    'reports.severity'     : 'Severity',
    'reports.score'        : 'Risk Score',
    'reports.status'       : 'Status',

    // Settings / user menu
    'settings.title'       : 'Settings',
    'settings.profile'     : 'Profile',
    'settings.language'    : 'Language',
    'settings.theme'       : 'Theme',
    'settings.darkMode'    : 'Dark Mode',
    'settings.lightMode'   : 'Light Mode',
    'settings.signOut'     : 'Sign Out',
    'settings.exportData'  : 'Export to Sheets',
    'settings.account'     : 'Account',
    'settings.designation' : 'Designation',
    'settings.pno'         : 'P. No.',
    'settings.changePass'  : 'Change Password',

    // Status / severity
    'status.open'          : 'OPEN',
    'status.investigating' : 'INVESTIGATING',
    'status.actionTaken'   : 'ACTION TAKEN',
    'status.closed'        : 'CLOSED',
    'severity.critical'    : 'CRITICAL',
    'severity.high'        : 'HIGH',
    'severity.medium'      : 'MEDIUM',
    'severity.low'         : 'LOW',

    // Messages
    'msg.savedLocal'       : 'Saved locally',
    'msg.savedSheets'      : '✓ Synced to Google Sheets',
    'msg.willSync'         : 'Will sync when online',
    'msg.exportSuccess'    : 'Exported successfully',
    'msg.networkError'     : 'Network error — try again',
    'msg.permissionDenied' : 'Permission denied',
  };

  // ──────────────────────────────────────────────────────────────
  //  HINDI STRINGS (देवनागरी)
  // ──────────────────────────────────────────────────────────────
  static const Map<String, String> _hi = {
    'app.name'             : 'सेल सेफ्टी लेंस',
    'app.tagline'          : 'AI सुरक्षा प्लेटफ़ॉर्म',

    'common.save'          : 'सहेजें',
    'common.cancel'        : 'रद्द करें',
    'common.close'         : 'बंद करें',
    'common.delete'        : 'हटाएँ',
    'common.edit'          : 'संपादित करें',
    'common.add'           : 'जोड़ें',
    'common.submit'        : 'जमा करें',
    'common.export'        : 'निर्यात',
    'common.search'        : 'खोजें',
    'common.filter'        : 'फ़िल्टर',
    'common.refresh'       : 'रिफ्रेश',
    'common.sync'          : 'सिंक',
    'common.loading'       : 'लोड हो रहा है…',
    'common.success'       : 'सफल',
    'common.failed'        : 'विफल',
    'common.yes'           : 'हाँ',
    'common.no'            : 'नहीं',
    'common.ok'            : 'ठीक है',
    'common.back'          : 'वापस',
    'common.next'          : 'अगला',
    'common.continue'      : 'जारी रखें',
    'common.retry'         : 'पुनः प्रयास',

    'tab.home'             : 'होम',
    'tab.aiScan'           : 'AI स्कैन',
    'tab.nearMiss'         : 'नियर मिस',
    'tab.askAi'            : 'AI से पूछें',
    'tab.reports'          : 'रिपोर्ट',

    'home.welcome'         : 'स्वागत है',
    'home.dashboard'       : 'सुरक्षा डैशबोर्ड',
    'home.totalCases'      : 'कुल मामले',
    'home.openCases'       : 'खुले',
    'home.closedCases'     : 'बंद',
    'home.criticalCases'   : 'गंभीर',
    'home.thisMonth'       : 'इस माह',
    'home.thisWeek'        : 'इस सप्ताह',
    'home.today'           : 'आज',
    'home.quickActions'    : 'त्वरित कार्य',
    'home.recentActivity'  : 'हालिया गतिविधि',
    'home.safetyStats'     : 'सुरक्षा आँकड़े',
    'home.byPlant'         : 'संयंत्रवार',
    'home.bySeverity'      : 'गंभीरता के अनुसार',
    'home.daysSinceLti'    : 'LTI के बाद दिन',
    'home.safetyScore'     : 'सुरक्षा स्कोर',
    'home.viewAll'         : 'सभी देखें',
    'home.noData'          : 'अभी तक कोई घटना नहीं',
    'home.startScan'       : 'AI स्कैन शुरू करें',
    'home.reportNearMiss'  : 'नियर मिस रिपोर्ट',
    'home.viewReports'     : 'रिपोर्ट देखें',
    'home.askExpert'       : 'विशेषज्ञ से पूछें',
    'home.greeting.morning': 'सुप्रभात',
    'home.greeting.afternoon': 'नमस्कार',
    'home.greeting.evening': 'शुभ संध्या',
    'home.weeklyTrend'     : 'साप्ताहिक प्रवृत्ति',
    'home.topHazards'      : 'मुख्य खतरे',

    'aiScan.title'         : 'AI ख़तरा स्कैन',
    'aiScan.subtitle'      : 'जेमिनी विज़न · IS 14489 · WSA 13',
    'aiScan.capture'       : 'फोटो',
    'aiScan.aiScan'        : 'AI स्कैन',
    'aiScan.review'        : 'समीक्षा',
    'aiScan.save'          : 'सहेजें',
    'aiScan.mitigate'      : 'निवारण',
    'aiScan.takePhoto'     : 'कार्यस्थल की फोटो लें',
    'aiScan.aiDetects'     : 'AI ख़तरों का पता लगाता है और फोटो पर अंकित करता है',
    'aiScan.camera'        : 'कैमरा',
    'aiScan.gallery'       : 'गैलरी',
    'aiScan.analyzing'     : 'फोटो का विश्लेषण…',
    'aiScan.summary'       : 'सारांश',
    'aiScan.hazardAnalysis': 'ख़तरा विश्लेषण',
    'aiScan.overallRisk'   : 'समग्र जोखिम',
    'aiScan.confidence'    : 'विश्वास',
    'aiScan.savedToSheets' : 'गूगल शीट में सहेजा गया',
    'aiScan.newScan'       : 'नया',
    'aiScan.pdf'           : 'PDF',
    'aiScan.howItWorks'    : 'AI स्कैन कैसे काम करता है',

    'nearMiss.title'       : 'नियर मिस / असुरक्षित स्थिति',
    'nearMiss.brief'       : 'संक्षिप्त विवरण',
    'nearMiss.briefHint'   : 'क्या हुआ? (आवाज़ या लिख कर)',
    'nearMiss.plant'       : 'संयंत्र',
    'nearMiss.dept'        : 'विभाग',
    'nearMiss.location'    : 'स्थान',
    'nearMiss.severity'    : 'गंभीरता',
    'nearMiss.people'      : 'शामिल व्यक्ति',
    'nearMiss.description' : 'विस्तृत विवरण',
    'nearMiss.action'      : 'तुरंत की गई कार्यवाही',
    'nearMiss.uploadImage' : 'फोटो अपलोड',
    'nearMiss.submit'      : 'रिपोर्ट जमा करें',
    'nearMiss.submitExport': 'जमा + PDF',
    'nearMiss.recording'   : 'सुन रहा है…',
    'nearMiss.tapToTalk'   : 'बोलने के लिए माइक दबाएँ',

    'reports.title'        : 'रिपोर्ट्स',
    'reports.all'          : 'सभी',
    'reports.open'         : 'खुले',
    'reports.closed'       : 'बंद',
    'reports.critical'     : 'गंभीर',
    'reports.high'         : 'उच्च',
    'reports.medium'       : 'मध्यम',
    'reports.low'          : 'निम्न',
    'reports.plant'        : 'संयंत्र / इकाई',
    'reports.byPlant'      : 'संयंत्र अनुसार फ़िल्टर',
    'reports.allPlants'    : 'सभी संयंत्र',
    'reports.export'       : 'PDF निर्यात',
    'reports.exportSheets' : 'शीट में खोलें',
    'reports.noReports'    : 'कोई रिपोर्ट नहीं',
    'reports.sortBy'       : 'क्रमबद्ध करें',
    'reports.date'         : 'दिनांक',
    'reports.severity'     : 'गंभीरता',
    'reports.score'        : 'जोखिम स्कोर',
    'reports.status'       : 'स्थिति',

    'settings.title'       : 'सेटिंग्स',
    'settings.profile'     : 'प्रोफ़ाइल',
    'settings.language'    : 'भाषा',
    'settings.theme'       : 'थीम',
    'settings.darkMode'    : 'डार्क मोड',
    'settings.lightMode'   : 'लाइट मोड',
    'settings.signOut'     : 'साइन आउट',
    'settings.exportData'  : 'शीट में निर्यात',
    'settings.account'     : 'खाता',
    'settings.designation' : 'पदनाम',
    'settings.pno'         : 'पी. नं.',
    'settings.changePass'  : 'पासवर्ड बदलें',

    'status.open'          : 'खुला',
    'status.investigating' : 'जाँच',
    'status.actionTaken'   : 'कार्यवाही',
    'status.closed'        : 'बंद',
    'severity.critical'    : 'गंभीर',
    'severity.high'        : 'उच्च',
    'severity.medium'      : 'मध्यम',
    'severity.low'         : 'निम्न',

    'msg.savedLocal'       : 'स्थानीय रूप से सहेजा गया',
    'msg.savedSheets'      : '✓ गूगल शीट में सिंक',
    'msg.willSync'         : 'ऑनलाइन होने पर सिंक होगा',
    'msg.exportSuccess'    : 'निर्यात सफल',
    'msg.networkError'     : 'नेटवर्क त्रुटि — पुनः प्रयास',
    'msg.permissionDenied' : 'अनुमति अस्वीकृत',
  };
}
