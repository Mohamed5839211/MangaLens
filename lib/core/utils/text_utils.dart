import 'package:flutter/material.dart';

/// أدوات معالجة النصوص العربية و RTL
/// RTL and Arabic text processing utilities
class TextUtils {
  TextUtils._();

  /// التحقق مما إذا كان النص عربياً
  static bool isArabic(String text) {
    final arabicRegex = RegExp(r'[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF]');
    return arabicRegex.hasMatch(text);
  }

  /// التحقق مما إذا كان النص يابانياً
  static bool isJapanese(String text) {
    final japaneseRegex = RegExp(r'[\u3040-\u309F\u30A0-\u30FF\u4E00-\u9FAF]');
    return japaneseRegex.hasMatch(text);
  }

  /// التحقق مما إذا كان النص كورياً
  static bool isKorean(String text) {
    final koreanRegex = RegExp(r'[\uAC00-\uD7AF\u1100-\u11FF]');
    return koreanRegex.hasMatch(text);
  }

  /// التحقق مما إذا كان النص صينياً
  static bool isChinese(String text) {
    final chineseRegex = RegExp(r'[\u4E00-\u9FFF\u3400-\u4DBF]');
    return chineseRegex.hasMatch(text);
  }

  /// تحديد اتجاه النص تلقائياً
  static TextDirection getTextDirection(String text) {
    if (isArabic(text)) return TextDirection.rtl;
    return TextDirection.ltr;
  }

  /// حساب حجم الخط المناسب للمستطيل المحدد
  static double calculateFontSize({
    required String text,
    required Size boxSize,
    required TextStyle style,
    double minSize = 8.0,
    double maxSize = 32.0,
  }) {
    double fontSize = maxSize;

    while (fontSize >= minSize) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: text,
          style: style.copyWith(fontSize: fontSize),
        ),
        textDirection: TextDirection.rtl,
        maxLines: null,
      );

      textPainter.layout(maxWidth: boxSize.width - 4);

      if (textPainter.height <= boxSize.height - 4) {
        return fontSize;
      }

      fontSize -= 0.5;
    }

    return minSize;
  }

  /// تقسيم النص مع مراعاة الكلمات العربية
  static List<String> wrapText(String text, int maxCharsPerLine) {
    final words = text.split(' ');
    final lines = <String>[];
    var currentLine = '';

    for (final word in words) {
      if (currentLine.isEmpty) {
        currentLine = word;
      } else if ('$currentLine $word'.length <= maxCharsPerLine) {
        currentLine = '$currentLine $word';
      } else {
        lines.add(currentLine);
        currentLine = word;
      }
    }

    if (currentLine.isNotEmpty) {
      lines.add(currentLine);
    }

    return lines;
  }
}
