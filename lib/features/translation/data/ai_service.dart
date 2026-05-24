import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../../ocr/models/ocr_result.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/supported_languages.dart';
import '../../../core/storage/secure_storage_service.dart';

/// خدمة الترجمة الذكية — موديل مفضل + إعادة محاولة ذكية + Fallback
/// Smart AI Service with Preferred Model, Exponential Backoff Retry & Fallback
class AiService {
  final Dio _dio;

  AiService() : _dio = Dio() {
    _dio.options.connectTimeout = AppConstants.apiTimeout;
    _dio.options.receiveTimeout = AppConstants.apiTimeout;
    _dio.options.headers = { 'Content-Type': 'application/json' };
  }

  /// بناء سلسلة التنفيذ بناءً على الموديل المفضل:
  /// 1. الموديل المفضل (يحاول أولاً مع إعادة محاولة)
  /// 2. بقية الموديلات كـ Fallback
  List<String> _buildExecutionChain(String preferredModel) {
    final chain = <String>[preferredModel];

    // بقية الموديلات كـ fallback
    for (final model in AppConstants.rotationModels) {
      if (!chain.contains(model)) {
        chain.add(model);
      }
    }

    debugPrint('🔄 Execution chain: $chain (preferred: $preferredModel)');
    return chain;
  }

  /// التحقق من صحة الترجمة (أنها لا تحتوي على أحرف من لغة أصلية غير مترجمة)
  bool _isValidTranslation(String translatedText, String originalText, String targetLangCode) {
    final trimmedTranslated = translatedText.trim();
    final trimmedOriginal = originalText.trim();
    if (trimmedTranslated.isEmpty) return true;

    // السماح بوسوم SFX مثل [SFX: ...]
    if (trimmedTranslated.startsWith('[SFX:') || trimmedTranslated.startsWith('[sfx:')) return true;

    // إذا كان النص الأصلي لا يحتوي على أي حرف أبجدي (مثل علامات الترقيم فقط أو أرقام فقط: "... " أو "12")
    // فلا داعي لطلب وجود أحرف لغة الهدف في الترجمة.
    final letterRegex = RegExp(r'[a-zA-Z\u3040-\u309F\u30A0-\u30FF\u4E00-\u9FFF\uAC00-\uD7AF]');
    if (!letterRegex.hasMatch(trimmedOriginal)) {
      return true;
    }

    final targetLower = targetLangCode.toLowerCase();

    // تنظيف النص من وسوم SFX مؤقتاً لتجنب إعطاء نتائج إيجابية خاطئة عند التحقق من اللغة
    final cleanText = trimmedTranslated
        .replaceAll(RegExp(r'\[(?:SFX|sfx|صوت)\s*:\s*[^\]]*\]', caseSensitive: false), '')
        .trim();

    if (cleanText.isEmpty) return true;

    // إذا كان الهدف عربي: نمنع تسرب الحروف الإنجليزية والآسيوية تماماً لضمان تعريب الأسماء والمصطلحات
    if (targetLower == 'ar') {
      final latinLetters = RegExp(r'[a-zA-Z]').allMatches(cleanText).length;
      final arabicLetters = RegExp(r'[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF]').allMatches(cleanText).length;
      
      // نتحقق من تسرب الإنجليزية فقط إذا كانت الحروف الإنجليزية سائدة وتتجاوز 40% من إجمالي الحروف وتشكل كلمة حقيقية (أكثر من 5 حروف)
      // لتفادي رفض الاختصارات الرياضية والـ RPG مثل HP, Lv. 9, Exp, MP
      if (latinLetters > 0) {
        final totalLetters = latinLetters + arabicLetters;
        if (totalLetters > 0 && (latinLetters / totalLetters) > 0.4 && latinLetters > 5) {
          debugPrint('⚠️ Validation: English letters leaked in Arabic translation: $trimmedTranslated');
          return false;
        }
      }

      final hasCjkLetters = RegExp(r'[\u3040-\u309F\u30A0-\u30FF\u4E00-\u9FFF\uAC00-\uD7AF]').hasMatch(cleanText);
      if (hasCjkLetters) {
        debugPrint('⚠️ Validation: CJK letters leaked in Arabic translation: $trimmedTranslated');
        return false;
      }

      final arabicRegex = RegExp(r'[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF]');
      final hasArabic = arabicRegex.hasMatch(cleanText);
      if (!hasArabic && cleanText.length > 15) {
        debugPrint('⚠️ Validation: No Arabic found in dialogue: $trimmedTranslated');
        return false;
      }
    }

    // إذا كان الهدف إنجليزي: نمنع تسرب الحروف الآسيوية
    if (targetLower == 'en') {
      final hasCjkLetters = RegExp(r'[\u3040-\u309F\u30A0-\u30FF\u4E00-\u9FFF\uAC00-\uD7AF]').hasMatch(cleanText);
      if (hasCjkLetters) {
        debugPrint('⚠️ Validation: CJK letters leaked in English translation: $trimmedTranslated');
        return false;
      }
    }

    // بشكل عام، إذا كانت اللغة المستهدفة ليست آسيوية، نمنع تسرب الحروف الآسيوية (أكثر من 30% أو بشكل كامل)
    if (targetLower != 'zh' && targetLower != 'ja' && targetLower != 'ko' && targetLower != 'ar' && targetLower != 'en') {
      final cjkRegex = RegExp(r'[\u3040-\u309F\u30A0-\u30FF\u4E00-\u9FFF\uAC00-\uD7AF]');
      final cjkMatches = cjkRegex.allMatches(cleanText).length;
      final totalChars = cleanText.replaceAll(RegExp(r'\s'), '').length;

      if (totalChars > 0 && cjkMatches / totalChars > 0.3) {
        debugPrint('⚠️ Validation: CJK ratio ${(cjkMatches / totalChars * 100).toInt()}% in: $trimmedTranslated');
        return false;
      }
    }

    return true;
  }

  /// التحقق مما إذا كان النص يمثل علامة مائية أو رابطاً لموقع (Watermark / URL)
  bool _isWatermarkOrUrl(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;

    // 1. روابط الويب التي تبدأ بـ http أو https
    if (trimmed.toLowerCase().startsWith('http://') || trimmed.toLowerCase().startsWith('https://')) {
      return true;
    }

    // 2. أسماء النطاقات البسيطة (مثل: EN-THUNDERSCANS.COM أو site.org) دون مسافات
    final domainRegex = RegExp(
      r'^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,6}(/[a-zA-Z0-9_.-]*)*$',
      caseSensitive: false,
    );
    if (domainRegex.hasMatch(trimmed) && !trimmed.contains(' ')) {
      return true;
    }

    // 3. روابط أو دعوات ديسكورد
    if (trimmed.toLowerCase().startsWith('discord.gg/') || trimmed.toLowerCase().startsWith('discord.com/invite/')) {
      return true;
    }

    // 4. السطور التي تدل على موقع أو حقوق ترجمة
    final creditRegex = RegExp(
      r'\b(scans|scanlation|translator|translations|group|team)\b.*\b(com|net|org|co|gg|xyz)\b',
      caseSensitive: false,
    );
    if (creditRegex.hasMatch(trimmed)) {
      return true;
    }

    return false;
  }

  /// ترجمة قائمة من نصوص OCR
  /// [targetLangCode] كود اللغة المستهدفة (مثل 'ar', 'en')
  Future<List<String>> translateBlocks(List<OcrResult> blocks, {String targetLangCode = 'ar'}) async {
    if (blocks.isEmpty) return [];

    final List<String> translations = List.filled(blocks.length, "");
    final List<int> blocksToTranslateIndices = [];

    // تصفية العلامات المائية وروابط المواقع وتعيين قيمتها كفراغ لمنع إرسالها أو فشل التحقق
    for (int i = 0; i < blocks.length; i++) {
      final text = blocks[i].text.trim();
      if (_isWatermarkOrUrl(text)) {
        debugPrint('🧹 Watermark/URL detected & filtered out: $text');
        translations[i] = ""; // سيتم مسحها بالكامل (Inpainted) دون كتابة شيء
      } else {
        blocksToTranslateIndices.add(i);
      }
    }

    // إذا كانت كل النصوص المكتشفة هي علامات مائية فقط
    if (blocksToTranslateIndices.isEmpty) {
      debugPrint('✨ All detected blocks were watermarks/URLs. Returning cleared results.');
      return translations;
    }

    // ─── جلب المفتاح ────────
    String apiKey = await SecureStorageService.getApiKey();
    if (apiKey.isEmpty) {
      apiKey = dotenv.env['DEFAULT_GROQ_API_KEY'] ?? '';
    }
    if (apiKey.isEmpty) {
      throw Exception('مفتاح API مفقود. يرجى إضافة مفتاحك في الإعدادات.');
    }

    // ─── جلب الموديل المفضل ────────
    final preferredModel = await SecureStorageService.getTranslationModel();

    // ─── Smart Routing ────────
    String baseUrl;
    List<String> executionChain;

    if (apiKey.startsWith('sk-')) {
      // OpenAI مباشر
      baseUrl = AppConstants.openAIBaseUrl;
      executionChain = [AppConstants.openAIDefaultModel];
    } else {
      // Groq — نظام الموديل المفضل + Fallback
      baseUrl = AppConstants.groqBaseUrl;
      executionChain = _buildExecutionChain(preferredModel);
    }

    _dio.options.baseUrl = baseUrl;

    // ─── تجهيز النص الفعلي المراد ترجمته فقط ────────
    final StringBuffer promptBuffer = StringBuffer();
    for (int i = 0; i < blocksToTranslateIndices.length; i++) {
      final origIdx = blocksToTranslateIndices[i];
      promptBuffer.writeln('[${i + 1}] ${blocks[origIdx].text}');
    }

    // ─── تنفيذ السلسلة: جرّب كل موديل ────────
    Exception? lastError;

    for (int modelIdx = 0; modelIdx < executionChain.length; modelIdx++) {
      final model = executionChain[modelIdx];

      try {
        debugPrint('🤖 Trying: $model');
        final result = await _callModel(
          apiKey,
          model,
          promptBuffer.toString(),
          blocksToTranslateIndices.length,
          targetLangCode,
        );

        // التحقق من صحة الترجمة
        bool allValid = true;
        for (int i = 0; i < result.length; i++) {
          final origIdx = blocksToTranslateIndices[i];
          if (!_isValidTranslation(result[i], blocks[origIdx].text, targetLangCode)) {
            allValid = false;
            break;
          }
        }

        if (!allValid) {
          debugPrint('⚠️ Model $model returned untranslated foreign script characters. Trying next...');
          lastError = Exception('$model: Returned untranslated script characters');
          continue; // جرب الموديل التالي مباشرة
        }

        debugPrint('✅ Success: $model');

        // دمج النتائج مع العلامات المائية المصفاة مسبقاً
        for (int i = 0; i < result.length; i++) {
          final origIdx = blocksToTranslateIndices[i];
          translations[origIdx] = result[i];
        }

        return translations;
      } on DioException catch (e) {
        final code = e.response?.statusCode;
        debugPrint('⚠️ $model failed [$code]: ${e.response?.data}');

        // 401 = مفتاح خاطئ — لا فائدة من المحاولة مع موديل آخر
        if (code == 401) {
          throw Exception('مفتاح API غير صالح. تحقق من الإعدادات.');
        }

        // 429 = Rate Limit — الانتقال فوراً للموديل التالي لتفادي التأخير وسجل الخطأ
        if (code == 429) {
          debugPrint('⏳ Rate limited on $model. Falling back immediately to next model in chain...');
          lastError = Exception('$model: Rate limit exceeded (429)');
          continue; // جرب الموديل التالي فوراً
        }

        lastError = Exception('$model: ${e.message}');
        continue; // جرب الموديل التالي
      } catch (e) {
        debugPrint('⚠️ $model error: $e');
        lastError = Exception('$model: $e');
        continue; // جرب الموديل التالي
      }
    }

    throw lastError ?? Exception('فشلت جميع الموديلات (${executionChain.length}) في الترجمة');
  }

  Future<List<String>> _callModel(
    String apiKey,
    String model,
    String prompt,
    int expectedCount,
    String targetLangCode,
  ) async {
    final targetFullName = SupportedLanguages.getFullName(targetLangCode);
    final systemPrompt = AppConstants.getTranslationPrompt(targetFullName);
    final response = await _dio.post(
      '/chat/completions',
      options: Options(
        headers: { 'Authorization': 'Bearer $apiKey' },
      ),
      data: {
        'model': model,
        'messages': [
          { 'role': 'system', 'content': systemPrompt },
          { 'role': 'user',   'content': prompt },
        ],
        'temperature': 0.3,
        'max_tokens': 2048,
        'response_format': { 'type': 'json_object' },
      },
    );

    if (response.statusCode == 200) {
      final content = response.data['choices'][0]['message']['content'] as String;
      return _parseTranslations(content, expectedCount);
    } else {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        message: 'Status ${response.statusCode}',
      );
    }
  }

  /// تحليل مخرجات النموذج
  List<String> _parseTranslations(String responseText, int expectedCount) {
    final List<String> translations = List.filled(expectedCount, "");
    try {
      String cleanJson = responseText.trim();

      // تنظيف علامات كود ماركداون إذا كانت موجودة
      if (cleanJson.contains('```')) {
        final firstBrace = cleanJson.indexOf('{');
        final lastBrace = cleanJson.lastIndexOf('}');
        if (firstBrace != -1 && lastBrace != -1 && lastBrace > firstBrace) {
          cleanJson = cleanJson.substring(firstBrace, lastBrace + 1);
        }
      }

      final Map<String, dynamic> data = json.decode(cleanJson);
      final List<dynamic>? list = data['translations'];
      if (list != null) {
        for (final item in list) {
          if (item is Map) {
            final int? index = item['index'] as int?;
            final String? text = item['text'] as String?;
            if (index != null && text != null) {
              final adjustedIndex = index - 1; // تحويل الفهرس من 1 إلى 0
              if (adjustedIndex >= 0 && adjustedIndex < expectedCount) {
                translations[adjustedIndex] = text.trim();
              }
            }
          }
        }
        return translations;
      }

      throw Exception('JSON parsed but format is invalid');
    } catch (e) {
      debugPrint('⚠️ JSON parsing failed, falling back to line-by-line parsing: $e');
      return _parseLineByLineTranslations(responseText, expectedCount);
    }
  }

  /// تحليل سطر بسطر ذكي لحل الطوارئ مع الحفاظ على الفهارس لمنع الإزاحة
  List<String> _parseLineByLineTranslations(String responseText, int expectedCount) {
    final lines = responseText.split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final List<String> translations = List.filled(expectedCount, "");

    // 1. محاولة استخلاص النصوص من JSON غير صحيح التركيب باستخدام التعبيرات المنتظمة أولاً
    if (responseText.contains('"translations"') || responseText.contains('"text"')) {
      final textRegex = RegExp(r'"text"\s*:\s*"([^"]+)"');
      final matches = textRegex.allMatches(responseText).toList();
      if (matches.isNotEmpty) {
        debugPrint('✨ Extracted translations using regex from failed JSON: ${matches.length} matches');
        for (int i = 0; i < matches.length && i < expectedCount; i++) {
          translations[i] = matches[i].group(1) ?? "";
        }
        return translations;
      }
    }

    int trIndex = 0;
    for (int i = 0; i < lines.length && trIndex < expectedCount; i++) {
      String line = lines[i];

      // تخطي الأسطر الهيكلية للـ JSON لمنع تسرب الرموز والأقواس كترجمات
      if (line == '{' || line == '}' || line == '[' || line == ']' || line == '},' || line == '],' ||
          line.startsWith('"translations"') || line.startsWith('"index"') || line.startsWith('{') || line.endsWith('}')) {
        continue;
      }

      // 2. محاولة مطابقة الفهرس مباشرة لتجنب ترحيل السطور (مثال: "[1] الترجمة" أو "1. الترجمة")
      final match = RegExp(r'^\[?(\d+)\]?\.?\s*').firstMatch(line);
      if (match != null) {
        final parsedIndex = int.tryParse(match.group(1) ?? '');
        if (parsedIndex != null) {
          final adjustedIndex = parsedIndex - 1;
          final content = line.replaceFirst(RegExp(r'^\[?\d+\]?\.?\s*'), '').trim();
          if (adjustedIndex >= 0 && adjustedIndex < expectedCount) {
            translations[adjustedIndex] = content;
            continue;
          }
        }
      }

      // 3. حل أخير: الدمج التتابعي التقليدي مع حماية الخانات المملوءة سابقاً من الاستبدال
      line = line.replaceFirst(RegExp(r'^\[?\d+\]?\.?\s*'), '').trim();
      if (line.isNotEmpty) {
        while (trIndex < expectedCount && translations[trIndex].isNotEmpty) {
          trIndex++;
        }
        if (trIndex < expectedCount) {
          translations[trIndex] = line;
          trIndex++;
        }
      }
    }

    return translations;
  }
}
