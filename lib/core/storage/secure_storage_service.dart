import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../constants/app_constants.dart';

/// خدمة التخزين الآمن — تغليف flutter_secure_storage
/// Secure storage service wrapper
class SecureStorageService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );


  // ─── مفتاح API ──────────────────────────────────────

  /// حفظ مفتاح API
  static Future<void> saveApiKey(String apiKey) async {
    await _storage.write(key: AppConstants.storageKeyApiKey, value: apiKey);
  }

  /// قراءة مفتاح API
  static Future<String> getApiKey() async {
    final key = await _storage.read(key: AppConstants.storageKeyApiKey);
    return key ?? '';
  }

  /// التحقق من وجود مفتاح API
  static Future<bool> hasApiKey() async {
    final key = await _storage.read(key: AppConstants.storageKeyApiKey);
    return key != null && key.isNotEmpty;
  }

  // ─── اللغة ──────────────────────────────────────────

  /// حفظ رمز اللغة ('ar' أو 'en')
  static Future<void> saveLanguage(String langCode) async {
    await _storage.write(key: AppConstants.storageKeyLanguage, value: langCode);
  }

  /// قراءة رمز اللغة (الافتراضي: 'ar')
  static Future<String> getLanguage() async {
    final lang = await _storage.read(key: AppConstants.storageKeyLanguage);
    return lang ?? 'ar';
  }

  // ─── منع الإعلانات ──────────────────────────────────
  static const String _adBlockKey = 'pref_ad_block';

  static Future<void> saveAdBlockEnabled(bool enabled) async {
    await _storage.write(key: _adBlockKey, value: enabled.toString());
  }

  static Future<bool> getAdBlockEnabled() async {
    final val = await _storage.read(key: _adBlockKey);
    return val != 'false'; // Default true
  }

  // ─── آخر رابط تمت زيارته ──────────────────────────────
  static const String _lastUrlKey = 'last_visited_url';

  static Future<void> saveLastUrl(String url) async {
    // لا نحفظ about:blank
    if (url.isNotEmpty && url != 'about:blank' && !url.contains('google.com/search')) {
      await _storage.write(key: _lastUrlKey, value: url);
    }
  }

  static Future<String?> getLastUrl() async {
    return await _storage.read(key: _lastUrlKey);
  }

  // ─── موديل الترجمة المفضل ──────────────────────────
  static Future<void> saveTranslationModel(String model) async {
    await _storage.write(key: AppConstants.storageKeyTranslationModel, value: model);
  }

  static Future<String> getTranslationModel() async {
    final model = await _storage.read(key: AppConstants.storageKeyTranslationModel);
    if (model == null || !AppConstants.rotationModels.contains(model)) {
      return AppConstants.primaryModel;
    }
    return model;
  }

  // ─── حفظ التبويبات المتعددة ──────────────────────────
  static const String _browserTabsKey = 'browser_open_tabs';
  static const String _activeTabIndexKey = 'browser_active_tab_index';

  static Future<void> saveBrowserTabs(String tabsJson, int activeIndex) async {
    await _storage.write(key: _browserTabsKey, value: tabsJson);
    await _storage.write(key: _activeTabIndexKey, value: activeIndex.toString());
  }

  static Future<String?> getBrowserTabs() async {
    return await _storage.read(key: _browserTabsKey);
  }

  static Future<int> getActiveTabIndex() async {
    final idxStr = await _storage.read(key: _activeTabIndexKey);
    return idxStr != null ? (int.tryParse(idxStr) ?? 0) : 0;
  }

  // ─── إعادة التعيين ──────────────────────────────────

  /// مسح جميع البيانات المخزنة
  static Future<void> clearAll() async {
    await _storage.deleteAll();
  }
}
