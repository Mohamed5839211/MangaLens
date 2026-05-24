import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../ocr/models/ocr_result.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/utils/image_utils.dart';
import '../../../core/utils/text_utils.dart';

/// عارض النصوص العربية على الصورة (RTL Text Renderer)
/// Dynamically renders Arabic text inside bounding boxes over the cleaned image
/// يدعم: توسيع الصناديق، تنسيق المؤثرات الصوتية، وتوحيد علامات الترقيم
class TextRenderer {

  /// توحيد علامات الترقيم الغربية إلى العربية لمنع انعكاس النص RTL
  static String _normalizeArabicPunctuation(String text) {
    return text
        .replaceAll('?', '\u061F')  // ؟
        .replaceAll(',', '\u060C')  // ،
        .replaceAll(';', '\u061B')  // ؛
        .replaceAll('!', '!')      // علامة التعجب تبقى كما هي (مدعومة في كلا الاتجاهين)
        ;
  }

  /// كشف وسوم المؤثرات الصوتية [SFX: ...] أو [صوت: ...]
  static final RegExp _sfxPattern = RegExp(r'^\[(?:SFX|صوت)\s*:\s*(.+)\]$', caseSensitive: false);

  /// التحقق من أن النص هو مؤثر صوتي
  static String? _extractSfxText(String text) {
    final match = _sfxPattern.firstMatch(text.trim());
    if (match != null) {
      return match.group(1)?.trim();
    }
    return null;
  }

  /// دمج الصورة المنظفة مع النصوص المترجمة
  Future<Uint8List> render(
    Uint8List cleanedImageBytes,
    List<String> translations,
    List<OcrResult> ocrResults,
  ) async {
    if (translations.isEmpty || ocrResults.isEmpty) return cleanedImageBytes;

    ui.Image? image;
    ui.Image? finalImage;
    ui.Picture? picture;

    try {
      // 1. تحويل الصورة إلى ui.Image لتتمكن من الرسم عليها
      image = await ImageUtils.bytesToImage(cleanedImageBytes);
      final imageSize = ImageUtils.getImageSize(image);

      // استخراج البكسلات لتحديد درجة سطوع لون الخلفية خلف الصناديق
      final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final Uint32List? pixels = byteData?.buffer.asUint32List();

      // 2. إنشاء لوحة رسم (Canvas) بنفس حجم الصورة
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, imageSize.width, imageSize.height));

      // 3. رسم الصورة الأصلية (المنظفة) كخلفية
      canvas.drawImage(image, Offset.zero, Paint());

      // 4. رسم النصوص المترجمة داخل الصناديق
      final count = ocrResults.length < translations.length
          ? ocrResults.length
          : translations.length;

      for (int i = 0; i < count; i++) {
        final originalBox = ocrResults[i].boundingBox;
        String text = translations[i];

        if (text.isEmpty) continue;

        // تنظيف النص من الرموز الزائدة (مع الحفاظ على السطور في شاشات النظام)
        if (!_isSystemStatus(text)) {
          text = text.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
        } else {
          text = text.trim();
        }

        // توسيع مستطيل الرسم ديناميكياً (نفس المنطق المستخدم في Inpainting)
        // لمنح النصوص العربية مساحة كافية للالتفاف ومنع صغر الخط
        final dynamicDilation = (originalBox.height * 0.15).clamp(6.0, 20.0);
        final expandedBox = ImageUtils.expandRect(
          originalBox,
          dynamicDilation,
          imageSize,
        );

        // كشف المؤثرات الصوتية
        final sfxText = _extractSfxText(text);
        final isSfx = sfxText != null;
        final displayText = isSfx ? sfxText : text;

        // توحيد علامات الترقيم العربية لمنع انعكاس الجمل
        final normalizedText = _normalizeArabicPunctuation(displayText);

        if (isSfx) {
          // ═══ رسم المؤثرات الصوتية بتنسيق مميز ═══
          _renderSfxText(canvas, normalizedText, expandedBox, imageSize);
        } else {
          // ═══ رسم النص العادي ═══
          _renderDialogueText(
            canvas,
            normalizedText,
            originalBox,
            pixels,
            image,
            ocrResults[i].detectedScript,
            imageSize,
          );
        }
      }

      // 5. الانتهاء من الرسم وتحويل النتيجة إلى Uint8List (PNG)
      picture = recorder.endRecording();
      finalImage = await picture.toImage(imageSize.width.toInt(), imageSize.height.toInt());
      return await ImageUtils.imageToBytes(finalImage);

    } catch (e) {
      debugPrint('Text Rendering Error: $e');
      return cleanedImageBytes;
    } finally {
      // تنظيف الموارد لمنع تسرب الذاكرة
      image?.dispose();
      finalImage?.dispose();
      picture?.dispose();
    }
  }

  /// رسم نص حوار عادي داخل الفقاعة
  void _renderDialogueText(
    Canvas canvas,
    String text,
    Rect box,
    Uint32List? pixels,
    ui.Image image,
    String sourceScript,
    Size imageSize,
  ) {
    final isArabicText = TextUtils.isArabic(text);
    final textDir = isArabicText ? TextDirection.rtl : TextDirection.ltr;
    final align = isArabicText ? TextAlign.center : TextAlign.center;

    // ─── 1. الكشف والفرز الذكي لنوع الصندوق النصي ───
    final isRpg = _isSystemStatus(text);
    final isMartial = _isMartialArts(text);
    final isTimeGate = _isTimeTravelOrGate(text);

    if (isRpg) {
      _renderRpgStatusWindow(canvas, text, box, isArabicText, imageSize);
      return;
    } else if (isTimeGate) {
      _renderTimeTravelOrGateWindow(canvas, text, box, isArabicText, imageSize);
      return;
    }

    // ─── 2. توسيع فقاعات المانجا اليابانية الرأسية والضيقة لمنح النصوص الأفقية مساحة مريحة ───
    Rect finalBox = box;
    if (sourceScript == 'ja') {
      final double widthExpansion = (box.width * 0.25).clamp(10.0, 50.0);
      finalBox = Rect.fromLTRB(
        (box.left - widthExpansion).clamp(0.0, imageSize.width),
        box.top,
        (box.right + widthExpansion).clamp(0.0, imageSize.width),
        box.bottom,
      );
    }

    // ─── 3. اختيار الخط المخصص بناءً على نوع القصة ولغة الهدف ───
    TextStyle textStyle;
    if (isMartial) {
      textStyle = isArabicText 
          ? GoogleFonts.amiri(fontWeight: FontWeight.bold, height: 1.3)
          : GoogleFonts.cinzel(fontWeight: FontWeight.bold, height: 1.3);
    } else {
      textStyle = isArabicText 
          ? GoogleFonts.cairo(fontWeight: FontWeight.bold, height: 1.2)
          : GoogleFonts.comicNeue(fontWeight: FontWeight.bold, height: 1.2);
    }

    // حساب حجم الخط المناسب للمربع
    final fontSize = TextUtils.calculateFontSize(
      text: text,
      boxSize: Size(finalBox.width * 0.9, finalBox.height * 0.9),
      style: textStyle,
      minSize: 9.5,
      maxSize: isMartial ? 20.0 : 18.0,
    );

    // تحديد ما إذا كانت خلفية الصندوق مظلمة
    bool isDarkBg = false;
    if (pixels != null) {
      isDarkBg = ImageUtils.isBubbleDark(pixels, image.width, image.height, finalBox);
    }

    // لون النص والحدود
    Color textColor;
    Color? strokeColor;
    if (isMartial) {
      textColor = isDarkBg ? const Color(0xFFFFD700) : const Color(0xFF1E1E1E); // ذهبي في الظلام، أسود عتيق في الضياء
      strokeColor = isDarkBg ? Colors.black : null;
    } else {
      textColor = isDarkBg ? Colors.white : const Color(0xFF111111);
      strokeColor = isDarkBg ? Colors.black : null;
    }

    if (strokeColor != null) {
      // نص بحدود سوداء سميكة لمنع تلاشيه في الخلفية
      final strokeStyle = textStyle.copyWith(
        fontSize: fontSize,
        foreground: Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = (fontSize * 0.15).clamp(1.5, 4.5)
          ..color = strokeColor,
      );

      final strokePainter = TextPainter(
        text: TextSpan(text: text, style: strokeStyle),
        textDirection: textDir,
        textAlign: align,
        maxLines: null,
      );
      strokePainter.layout(maxWidth: finalBox.width * 0.9);

      final xOffset = finalBox.left + (finalBox.width - strokePainter.width) / 2;
      final yOffset = finalBox.top + (finalBox.height - strokePainter.height) / 2;

      strokePainter.paint(canvas, Offset(xOffset, yOffset));

      final fillStyle = textStyle.copyWith(
        fontSize: fontSize,
        color: textColor,
      );

      final fillPainter = TextPainter(
        text: TextSpan(text: text, style: fillStyle),
        textDirection: textDir,
        textAlign: align,
        maxLines: null,
      );
      fillPainter.layout(maxWidth: finalBox.width * 0.9);
      fillPainter.paint(canvas, Offset(xOffset, yOffset));
    } else {
      // نص مصمت بدون حدود
      final fillStyle = textStyle.copyWith(
        fontSize: fontSize,
        color: textColor,
      );

      final fillPainter = TextPainter(
        text: TextSpan(text: text, style: fillStyle),
        textDirection: textDir,
        textAlign: align,
        maxLines: null,
      );
      fillPainter.layout(maxWidth: finalBox.width * 0.9);

      final xOffset = finalBox.left + (finalBox.width - fillPainter.width) / 2;
      final yOffset = finalBox.top + (finalBox.height - fillPainter.height) / 2;

      fillPainter.paint(canvas, Offset(xOffset, yOffset));
    }
  }

  /// رسم مؤثرات صوتية (SFX) بتنسيق مميز ومائل وبارز
  void _renderSfxText(
    Canvas canvas,
    String text,
    Rect box,
    Size imageSize,
  ) {
    final isArabicText = TextUtils.isArabic(text);
    final textDir = isArabicText ? TextDirection.rtl : TextDirection.ltr;

    // حجم الخط للمؤثرات: أكبر قليلاً وأكثر بروزاً
    final fontSize = TextUtils.calculateFontSize(
      text: text,
      boxSize: box.size,
      style: AppTextStyles.bubbleText,
      minSize: 10.0,
      maxSize: 32.0,
    );

    // لون المؤثر الصوتي: برتقالي مشع مميز
    const sfxColor = Color(0xFFFF6B35);
    const sfxStrokeColor = Color(0xFF1A1A2E);

    // حدود سميكة خارجية (Stroke) لإظهار المؤثر بشكل بارز
    final strokeStyle = AppTextStyles.bubbleText.copyWith(
      fontSize: fontSize,
      fontWeight: FontWeight.w900,
      fontStyle: FontStyle.italic,
      foreground: Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = (fontSize * 0.25).clamp(2.0, 6.0)
        ..color = sfxStrokeColor,
    );

    final strokePainter = TextPainter(
      text: TextSpan(text: text, style: strokeStyle),
      textDirection: textDir,
      textAlign: TextAlign.center,
      maxLines: null,
    );
    strokePainter.layout(maxWidth: box.width);

    final xOffset = box.left + (box.width - strokePainter.width) / 2;
    final yOffset = box.top + (box.height - strokePainter.height) / 2;

    strokePainter.paint(canvas, Offset(xOffset, yOffset));

    // النص الداخلي الملون
    final fillStyle = AppTextStyles.bubbleText.copyWith(
      fontSize: fontSize,
      fontWeight: FontWeight.w900,
      fontStyle: FontStyle.italic,
      color: sfxColor,
    );

    final fillPainter = TextPainter(
      text: TextSpan(text: text, style: fillStyle),
      textDirection: textDir,
      textAlign: TextAlign.center,
      maxLines: null,
    );
    fillPainter.layout(maxWidth: box.width);
    fillPainter.paint(canvas, Offset(xOffset, yOffset));
  }

  // ─── 4. معالجة وتصنيف صناديق النظام وتدرجات الألوان ───

  /// هل النص يمثل قائمة أو نافذة إحصائيات النظام (RPG Status)?
  bool _isSystemStatus(String text) {
    final lower = text.toLowerCase();
    final sWindowKeywords = [
      'level', 'status', 'hp', 'mp', 'str', 'agi', 'dex', 'int', 'vit', 'stats', 'speed', 'potential',
      'المستوى', 'الحالة', 'النقاط', 'القوة', 'الرشاقة', 'الذكاء', 'الخصائص', 'المهارة', 'القدرة', 'التحمل'
    ];
    return sWindowKeywords.any((k) => lower.contains(k));
  }

  /// هل النص يعود لقصة فنون قتالية أو تصنيف عشائر تاريخية؟
  bool _isMartialArts(String text) {
    final lower = text.toLowerCase();
    final martialKeywords = [
      'sect', 'clan', 'cultivation', 'elixir', 'qi', 'dantian', 'martial', 'grandmaster',
      'طائفة', 'عشيرة', 'زراعة', 'إكسير', 'تشي', 'دانتين', 'سيد عظيم', 'الكونغ فو'
    ];
    return martialKeywords.any((k) => lower.contains(k));
  }

  /// هل النص يعود لبوابة سحرية، أو إشعار عودة بالزمن وتناسخ؟
  bool _isTimeTravelOrGate(String text) {
    final lower = text.toLowerCase();
    final timeGateKeywords = [
      'gate', 'reincarnation', 'regression', 'time travel', 'awakening', 'quest',
      'بوابة', 'تناسخ', 'العودة بالزمن', 'المهمة', 'إشعار النظام', 'يقظة'
    ];
    return timeGateKeywords.any((k) => lower.contains(k));
  }

  /// رسم شاشة النظام (RPG Status Window) بأسلوب رقمي مشع ومقروء
  void _renderRpgStatusWindow(
    Canvas canvas,
    String text,
    Rect box,
    bool isArabic,
    Size imageSize,
  ) {
    // 1. حساب مستطيل بحواف دائرية أنيقة (RRect)
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTRB(
        (box.left - 6).clamp(0.0, imageSize.width),
        (box.top - 6).clamp(0.0, imageSize.height),
        (box.right + 6).clamp(0.0, imageSize.width),
        (box.bottom + 6).clamp(0.0, imageSize.height),
      ),
      const Radius.circular(10),
    );

    // 2. رسم خلفية تقنية زرقاء داكنة شفافة بنسبة 90%
    final bgPaint = Paint()
      ..color = const Color(0xDC0B1528) // زرقاء داكنة جداً عميقة
      ..style = PaintingStyle.fill;
    
    // رسم ظل خفيف خلف الصندوق لمزيد من الواقعية والعمق
    canvas.drawRRect(rrect, bgPaint);

    // 3. رسم حدود مضيئة بتقنية النيون الزرقاء المشعة (Cyan Border)
    final borderPaint = Paint()
      ..color = const Color(0xFF38BDF8) // أزرق نيون ساطع
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    canvas.drawRRect(rrect, borderPaint);

    // 4. اختيار الخط الرقمي المناسب
    final textStyle = isArabic 
        ? GoogleFonts.cairo(color: const Color(0xFFF0F9FF), fontWeight: FontWeight.bold, height: 1.3)
        : GoogleFonts.shareTechMono(color: const Color(0xFF38BDF8), fontWeight: FontWeight.bold, height: 1.3);

    final textDir = isArabic ? TextDirection.rtl : TextDirection.ltr;
    final align = isArabic ? TextAlign.right : TextAlign.left; // محاذاة مرتبة حسب اتجاه اللغة

    final fontSize = TextUtils.calculateFontSize(
      text: text,
      boxSize: Size(box.width * 0.9, box.height * 0.9),
      style: textStyle,
      minSize: 8.5,
      maxSize: 14.0,
    );

    final painter = TextPainter(
      text: TextSpan(text: text, style: textStyle.copyWith(fontSize: fontSize)),
      textDirection: textDir,
      textAlign: align,
      maxLines: null,
    );
    painter.layout(maxWidth: box.width * 0.9);

    // رسم النص محاذاة في المنتصف
    final xOffset = box.left + (box.width - painter.width) / 2;
    final yOffset = box.top + (box.height - painter.height) / 2;
    painter.paint(canvas, Offset(xOffset, yOffset));
  }

  /// رسم نافذة سحرية وإشعار عودة بالزمن/بوابات بتدرج داكن وحدود ذهبية/أرجوانية مشعة
  void _renderTimeTravelOrGateWindow(
    Canvas canvas,
    String text,
    Rect box,
    bool isArabic,
    Size imageSize,
  ) {
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTRB(
        (box.left - 6).clamp(0.0, imageSize.width),
        (box.top - 6).clamp(0.0, imageSize.height),
        (box.right + 6).clamp(0.0, imageSize.width),
        (box.bottom + 6).clamp(0.0, imageSize.height),
      ),
      const Radius.circular(12),
    );

    // خلفية أرجوانية ملكية داكنة غامضة
    final bgPaint = Paint()
      ..color = const Color(0xEC1A0B2E)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(rrect, bgPaint);

    // حدود ذهبية سحرية مضيئة ومميزة
    final borderPaint = Paint()
      ..color = const Color(0xFFFBBF24) // ذهبي مشع
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    canvas.drawRRect(rrect, borderPaint);

    final textStyle = isArabic
        ? GoogleFonts.cairo(color: const Color(0xFFFEF3C7), fontWeight: FontWeight.bold, height: 1.3)
        : GoogleFonts.cinzel(color: const Color(0xFFFBBF24), fontWeight: FontWeight.bold, height: 1.3);

    final textDir = isArabic ? TextDirection.rtl : TextDirection.ltr;
    final align = isArabic ? TextAlign.center : TextAlign.center;

    final fontSize = TextUtils.calculateFontSize(
      text: text,
      boxSize: Size(box.width * 0.9, box.height * 0.9),
      style: textStyle,
      minSize: 9.0,
      maxSize: 14.5,
    );

    final painter = TextPainter(
      text: TextSpan(text: text, style: textStyle.copyWith(fontSize: fontSize)),
      textDirection: textDir,
      textAlign: align,
      maxLines: null,
    );
    painter.layout(maxWidth: box.width * 0.9);

    final xOffset = box.left + (box.width - painter.width) / 2;
    final yOffset = box.top + (box.height - painter.height) / 2;
    painter.paint(canvas, Offset(xOffset, yOffset));
  }
}
