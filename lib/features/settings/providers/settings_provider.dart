import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/storage/secure_storage_service.dart';

/// حالة الإعدادات
/// Settings state model
class SettingsState {
  final String apiKey;
  final String language;
  final bool adBlockEnabled;
  final String translationModel;
  final bool isLoaded;

  const SettingsState({
    this.apiKey = '',
    this.language = 'ar',
    this.adBlockEnabled = true,
    this.translationModel = 'llama-3.3-70b-versatile',
    this.isLoaded = false,
  });

  SettingsState copyWith({
    String? apiKey,
    String? language,
    bool? adBlockEnabled,
    String? translationModel,
    bool? isLoaded,
  }) {
    return SettingsState(
      apiKey: apiKey ?? this.apiKey,
      language: language ?? this.language,
      adBlockEnabled: adBlockEnabled ?? this.adBlockEnabled,
      translationModel: translationModel ?? this.translationModel,
      isLoaded: isLoaded ?? this.isLoaded,
    );
  }
}

/// مزود الإعدادات
/// Settings state provider
class SettingsNotifier extends Notifier<SettingsState> {
  @override
  SettingsState build() {
    _loadSettings();
    return const SettingsState();
  }

  /// تحميل جميع الإعدادات من التخزين الآمن
  Future<void> _loadSettings() async {
    final apiKey = await SecureStorageService.getApiKey();
    final language = await SecureStorageService.getLanguage();
    final adBlockEnabled = await SecureStorageService.getAdBlockEnabled();
    final translationModel = await SecureStorageService.getTranslationModel();

    state = state.copyWith(
      apiKey: apiKey,
      language: language,
      adBlockEnabled: adBlockEnabled,
      translationModel: translationModel,
      isLoaded: true,
    );
  }

  /// تحديث وحفظ مفتاح API
  Future<void> updateApiKey(String apiKey) async {
    await SecureStorageService.saveApiKey(apiKey);
    state = state.copyWith(apiKey: apiKey);
  }

  /// تحديث وحفظ اللغة
  Future<void> updateLanguage(String languageCode) async {
    await SecureStorageService.saveLanguage(languageCode);
    state = state.copyWith(language: languageCode);
  }

  /// تحديث إعدادات منع الإعلانات
  Future<void> updateAdBlock(bool enabled) async {
    await SecureStorageService.saveAdBlockEnabled(enabled);
    state = state.copyWith(adBlockEnabled: enabled);
  }

  /// تحديث موديل الترجمة المفضل
  Future<void> updateTranslationModel(String model) async {
    await SecureStorageService.saveTranslationModel(model);
    state = state.copyWith(translationModel: model);
  }

  /// هل مفتاح API متوفر؟
  bool get hasValidApiKey => state.apiKey.isNotEmpty;
}

/// مزود الإعدادات الرئيسي
final settingsProvider =
    NotifierProvider<SettingsNotifier, SettingsState>(() {
  return SettingsNotifier();
});
