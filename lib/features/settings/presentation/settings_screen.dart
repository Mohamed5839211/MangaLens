import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/localization/app_localizations.dart';
import '../providers/settings_provider.dart';
import '../../../core/services/update_service.dart';

/// شاشة الإعدادات مع التعرف الذكي على مزود المفتاح
/// Settings screen with Smart API Key Provider Detection
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _apiKeyController = TextEditingController();

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  /// التعرف الذكي على مزود المفتاح
  _ApiProviderInfo _detectProvider(String key) {
    if (key.isEmpty) {
      final hasDefault = (dotenv.env['DEFAULT_GROQ_API_KEY'] ?? '').isNotEmpty &&
                         dotenv.env['DEFAULT_GROQ_API_KEY'] != 'gsk_default_key_here';
      if (hasDefault) {
        return _ApiProviderInfo(
          name: 'Groq (Default)',
          icon: Icons.memory_rounded,
          color: Colors.orangeAccent,
          model: AppConstants.primaryModel,
          isDefault: true,
        );
      }
      return _ApiProviderInfo(
        name: 'لا يوجد مفتاح',
        icon: Icons.warning_amber_rounded,
        color: Colors.redAccent,
        model: '—',
        isDefault: false,
      );
    }

    if (key.startsWith('gsk_')) {
      return _ApiProviderInfo(
        name: 'Groq',
        icon: Icons.memory_rounded,
        color: Colors.orangeAccent,
        model: AppConstants.primaryModel,
        isDefault: false,
      );
    } else if (key.startsWith('sk-')) {
      return _ApiProviderInfo(
        name: 'OpenAI',
        icon: Icons.auto_awesome_rounded,
        color: Colors.greenAccent,
        model: AppConstants.openAIDefaultModel,
        isDefault: false,
      );
    } else {
      return _ApiProviderInfo(
        name: 'مزود غير معروف',
        icon: Icons.help_outline_rounded,
        color: Colors.amber,
        model: 'سيتم محاولة Groq',
        isDefault: false,
      );
    }
  }

  Future<void> _manualCheckForUpdates() async {
    // إظهار مؤشر تحميل بسيط
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('جاري التحقق من وجود تحديثات...', style: GoogleFonts.cairo()),
        backgroundColor: AppColors.primary,
        duration: const Duration(seconds: 1),
      ),
    );

    final updateInfo = await UpdateService.checkForUpdates();
    if (!mounted) return;

    if (updateInfo != null) {
      UpdateService.showUpdateDialog(context, ref, updateInfo);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تطبيقك محدث! أنت تستخدم أحدث إصدار بالفعل (${AppConstants.appVersion})', style: GoogleFonts.cairo()),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsState = ref.watch(settingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);

    if (_apiKeyController.text.isEmpty && settingsState.apiKey.isNotEmpty) {
      _apiKeyController.text = settingsState.apiKey;
    }

    if (!settingsState.isLoaded) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final providerInfo = _detectProvider(settingsState.apiKey);

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text(context.tr('settingsTitle'), style: GoogleFonts.cairo(fontWeight: FontWeight.w800, color: Colors.white)),
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ─── إعدادات اللغة ─────────────────────────────
          _buildSectionHeader(context, context.tr('language'), Icons.language),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border, width: 1.5),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 15, offset: const Offset(0, 8)),
              ],
            ),
            child: Column(
              children: [
                _buildRadioTile(
                  context: context,
                  title: context.tr('arabic'),
                  value: 'ar',
                  groupValue: settingsState.language,
                  onChanged: (val) => settingsNotifier.updateLanguage(val!),
                ),
                const Divider(height: 1, color: AppColors.border, indent: 20, endIndent: 20),
                _buildRadioTile(
                  context: context,
                  title: context.tr('english'),
                  value: 'en',
                  groupValue: settingsState.language,
                  onChanged: (val) => settingsNotifier.updateLanguage(val!),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          // ─── منع الإعلانات ─────────────────────────────
          _buildSectionHeader(context, 'منع الإعلانات (AdBlock)', Icons.shield_rounded),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border, width: 1.5),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 15, offset: const Offset(0, 8)),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'تفعيل مانع الإعلانات',
                        style: GoogleFonts.cairo(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'حجب الإعلانات المزعجة داخل مواقع المانغا',
                        style: GoogleFonts.cairo(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: settingsState.adBlockEnabled,
                  activeColor: AppColors.primary,
                  onChanged: (value) {
                    settingsNotifier.updateAdBlock(value);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          // ─── إعدادات مفتاح الذكاء الاصطناعي ──────────
          _buildSectionHeader(context, context.tr('apiKey'), Icons.vpn_key_rounded),
          const SizedBox(height: 12),

          // بطاقة المزود المكتشف
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: providerInfo.color.withOpacity(0.05),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: providerInfo.color.withOpacity(0.4), width: 1.5),
              boxShadow: [
                BoxShadow(color: providerInfo.color.withOpacity(0.1), blurRadius: 20),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: providerInfo.color.withOpacity(0.15),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: providerInfo.color.withOpacity(0.3), blurRadius: 10),
                    ],
                  ),
                  child: Icon(providerInfo.icon, color: providerInfo.color, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${context.tr('detected_provider')}: ${providerInfo.name}',
                        style: TextStyle(
                          color: providerInfo.color,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Model: ${providerInfo.model}',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                if (providerInfo.isDefault)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.primary.withOpacity(0.5)),
                    ),
                    child: Text(
                      context.tr('using_default_key'),
                      style: const TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                  ),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          Text(
            context.tr('apiKeyHint'),
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border, width: 1.5),
            ),
            child: TextField(
              controller: _apiKeyController,
              style: const TextStyle(color: Colors.white, fontSize: 15, letterSpacing: 2),
              obscureText: true,
              decoration: InputDecoration(
                hintText: 'gsk_... أو sk-...',
                hintStyle: GoogleFonts.cairo(color: AppColors.textSecondary.withOpacity(0.5), letterSpacing: 0),
                prefixIcon: const Icon(Icons.lock_outline_rounded, color: AppColors.textSecondary),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    final key = _apiKeyController.text.trim();
                    settingsNotifier.updateApiKey(key);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(context.tr('apiKeySaved'), style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
                        backgroundColor: AppColors.success,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    );
                    FocusScope.of(context).unfocus();
                    setState(() {});
                  },
                  icon: const Icon(Icons.check_circle_outline_rounded, color: Colors.white),
                  label: Text('تأكيد الاستخدام', style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: () {
                  _apiKeyController.clear();
                  settingsNotifier.updateApiKey('');
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('تم العودة للمفتاح الافتراضي', style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
                      backgroundColor: AppColors.secondary,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  );
                  FocusScope.of(context).unfocus();
                  setState(() {});
                },
                icon: const Icon(Icons.restore_rounded, color: Colors.white),
                label: Text('الافتراضي', style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.surfaceBright,
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),

          const SizedBox(height: 32),

          // ─── موديل الترجمة المفضل ─────────────────────
          _buildSectionHeader(context, 'موديل الترجمة', Icons.psychology_rounded),
          const SizedBox(height: 8),
          Text(
            'اختر الموديل المفضل للترجمة. الموديل القوي أبطأ قليلاً لكن أدق وأكثر اتساقاً.',
            style: GoogleFonts.cairo(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border, width: 1.5),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 15, offset: const Offset(0, 8)),
              ],
            ),
            child: Column(
              children: [
                _buildModelRadioTile(
                  title: 'Llama 3.3 70B (موصى به)',
                  subtitle: 'الأقوى — ترجمة دقيقة ومتسقة النبرة',
                  value: 'llama-3.3-70b-versatile',
                  groupValue: settingsState.translationModel,
                  color: Colors.orangeAccent,
                  onChanged: (val) => settingsNotifier.updateTranslationModel(val!),
                ),
                const Divider(height: 1, color: AppColors.border, indent: 20, endIndent: 20),
                _buildModelRadioTile(
                  title: 'علّام ALLAM-2 7B',
                  subtitle: 'علّام (SDAIA) — متفوق لغوياً ومصمم للغة العربية',
                  value: 'allam-2-7b',
                  groupValue: settingsState.translationModel,
                  color: Colors.pinkAccent,
                  onChanged: (val) => settingsNotifier.updateTranslationModel(val!),
                ),
                const Divider(height: 1, color: AppColors.border, indent: 20, endIndent: 20),
                _buildModelRadioTile(
                  title: 'Qwen 3 32B',
                  subtitle: 'الأفضل لترجمة المانغا واللغات الآسيوية (CJK)',
                  value: 'qwen/qwen3-32b',
                  groupValue: settingsState.translationModel,
                  color: Colors.lightBlueAccent,
                  onChanged: (val) => settingsNotifier.updateTranslationModel(val!),
                ),
                const Divider(height: 1, color: AppColors.border, indent: 20, endIndent: 20),
                _buildModelRadioTile(
                  title: 'GPT-OSS 120B',
                  subtitle: 'نموذج ضخم يقدم أداء متسق وفهم عميق للقصص',
                  value: 'openai/gpt-oss-120b',
                  groupValue: settingsState.translationModel,
                  color: Colors.amberAccent,
                  onChanged: (val) => settingsNotifier.updateTranslationModel(val!),
                ),
                const Divider(height: 1, color: AppColors.border, indent: 20, endIndent: 20),
                _buildModelRadioTile(
                  title: 'Llama 3.1 8B Instant',
                  subtitle: 'سريع جداً — جودة متوسطة',
                  value: 'llama-3.1-8b-instant',
                  groupValue: settingsState.translationModel,
                  color: Colors.cyanAccent,
                  onChanged: (val) => settingsNotifier.updateTranslationModel(val!),
                ),
                const Divider(height: 1, color: AppColors.border, indent: 20, endIndent: 20),
                _buildModelRadioTile(
                  title: 'Mixtral 8x7B',
                  subtitle: 'ذكي ومتعدد الخبراء — جيد للتعبيرات والمصطلحات',
                  value: 'mixtral-8x7b-32768',
                  groupValue: settingsState.translationModel,
                  color: Colors.purpleAccent,
                  onChanged: (val) => settingsNotifier.updateTranslationModel(val!),
                ),
                const Divider(height: 1, color: AppColors.border, indent: 20, endIndent: 20),
                _buildModelRadioTile(
                  title: 'Gemma 2 9B',
                  subtitle: 'خفيف وفعال — سريع جداً للاستخدام الفوري',
                  value: 'gemma2-9b-it',
                  groupValue: settingsState.translationModel,
                  color: Colors.greenAccent,
                  onChanged: (val) => settingsNotifier.updateTranslationModel(val!),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // ─── تحديث التطبيق ─────────────────────────────
          _buildSectionHeader(context, 'تحديث التطبيق', Icons.system_update_rounded),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border, width: 1.5),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 15, offset: const Offset(0, 8)),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _manualCheckForUpdates,
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'التحقق من وجود تحديثات',
                              style: GoogleFonts.cairo(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'التحقق يدوياً من وجود إصدار أحدث للتطبيق على GitHub',
                              style: GoogleFonts.cairo(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios_rounded, color: AppColors.textSecondary, size: 16),
                    ],
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 48),
          // ─── معلومات التطبيق ─────────────────────────
          Center(
            child: Column(
              children: [
                Text(
                  AppConstants.appName,
                  style: AppTextStyles.headlineMedium.copyWith(
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${context.tr('version')} ${AppConstants.appVersion}',
                  style: AppTextStyles.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Text(
            title,
            style: GoogleFonts.cairo(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Widget _buildRadioTile({
    required BuildContext context,
    required String title,
    required String value,
    required String groupValue,
    required ValueChanged<String?> onChanged,
  }) {
    final isSelected = value == groupValue;
    return InkWell(
      onTap: () => onChanged(value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: isSelected ? Colors.white : AppColors.textSecondary,
                  fontSize: 16,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? AppColors.primary : AppColors.textSecondary.withOpacity(0.5),
                  width: 2,
                ),
              ),
              child: isSelected
                  ? Center(
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModelRadioTile({
    required String title,
    required String subtitle,
    required String value,
    required String groupValue,
    required Color color,
    required ValueChanged<String?> onChanged,
  }) {
    final isSelected = value == groupValue;
    return InkWell(
      onTap: () => onChanged(value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: color.withOpacity(0.5), blurRadius: 6),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isSelected ? Colors.white : AppColors.textSecondary,
                      fontSize: 15,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.cairo(
                      color: AppColors.textSecondary.withOpacity(0.7),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? color : AppColors.textSecondary.withOpacity(0.5),
                  width: 2,
                ),
              ),
              child: isSelected
                  ? Center(
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// معلومات المزود المكتشف
class _ApiProviderInfo {
  final String name;
  final IconData icon;
  final Color color;
  final String model;
  final bool isDefault;

  _ApiProviderInfo({
    required this.name,
    required this.icon,
    required this.color,
    required this.model,
    required this.isDefault,
  });
}
