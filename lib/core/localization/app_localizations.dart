import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// مفوض الترجمة المحلية
/// Localization delegate for loading JSON-based translations
class AppLocalizations {
  final Locale locale;
  late Map<String, String> _localizedStrings;

  AppLocalizations(this.locale);

  /// الوصول السريع من السياق
  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// اللغات المدعومة
  static const List<Locale> supportedLocales = [
    Locale('ar'), // العربية — الافتراضية
    Locale('en'), // English
  ];

  /// تحميل ملف الترجمة JSON
  Future<bool> load() async {
    final jsonString = await rootBundle.loadString(
      'assets/localization/${locale.languageCode}.json',
    );
    final Map<String, dynamic> jsonMap = json.decode(jsonString);

    _localizedStrings = jsonMap.map((key, value) {
      return MapEntry(key, value.toString());
    });

    return true;
  }

  /// الحصول على النص المترجم بالمفتاح
  String translate(String key) {
    return _localizedStrings[key] ?? key;
  }

  /// اختصار للترجمة
  String tr(String key) => translate(key);
}

/// مفوض التحميل
class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return ['ar', 'en'].contains(locale.languageCode);
  }

  @override
  Future<AppLocalizations> load(Locale locale) async {
    final localizations = AppLocalizations(locale);
    await localizations.load();
    return localizations;
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

/// امتداد للوصول السريع
extension LocalizationExtension on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
  String tr(String key) => AppLocalizations.of(this).translate(key);
}
