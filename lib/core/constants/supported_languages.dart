/// اللغات المدعومة للترجمة
/// Supported languages for translation source/target
class SupportedLanguages {
  SupportedLanguages._();

  /// خريطة اللغات: كود → اسم
  static const Map<String, String> all = {
    'auto': 'تعرف تلقائي 🔍',
    'ar': 'العربية',
    'en': 'English',
    'ja': '日本語',
    'ko': '한국어',
    'zh': '中文',
    'fr': 'Français',
    'es': 'Español',
    'de': 'Deutsch',
    'tr': 'Türkçe',
    'id': 'Indonesia',
    'pt': 'Português',
    'ru': 'Русский',
    'th': 'ไทย',
    'vi': 'Tiếng Việt',
  };

  /// اللغات المتاحة كهدف (بدون auto)
  static Map<String, String> get targets {
    return Map.from(all)..remove('auto');
  }

  /// اللغات المتاحة كمصدر (مع auto)
  static Map<String, String> get sources => all;

  /// الحصول على اسم لغة من الكود
  static String getName(String code) => all[code] ?? code;

  /// الحصول على الاسم الكامل بالإنجليزية للـ AI Prompt
  static const Map<String, String> fullNames = {
    'ar': 'Arabic',
    'en': 'English',
    'ja': 'Japanese',
    'ko': 'Korean',
    'zh': 'Chinese',
    'fr': 'French',
    'es': 'Spanish',
    'de': 'German',
    'tr': 'Turkish',
    'id': 'Indonesian',
    'pt': 'Portuguese',
    'ru': 'Russian',
    'th': 'Thai',
    'vi': 'Vietnamese',
  };

  static String getFullName(String code) => fullNames[code] ?? code;
}
