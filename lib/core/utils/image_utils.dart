import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// أدوات معالجة الصور
/// Image processing utilities
class ImageUtils {
  ImageUtils._();

  /// تحويل Uint8List إلى ui.Image
  static Future<ui.Image> bytesToImage(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    codec.dispose(); // التخلص من كوديك الصورة لمنع تسرب الذاكرة
    return image;
  }

  /// تحويل ui.Image إلى Uint8List (PNG)
  static Future<Uint8List> imageToBytes(ui.Image image) async {
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  /// حساب حجم الصورة
  static Size getImageSize(ui.Image image) {
    return Size(image.width.toDouble(), image.height.toDouble());
  }

  /// تغيير حجم المستطيل بنسبة
  static Rect scaleRect(Rect rect, double scaleX, double scaleY) {
    return Rect.fromLTWH(
      rect.left * scaleX,
      rect.top * scaleY,
      rect.width * scaleX,
      rect.height * scaleY,
    );
  }

  /// توسيع المستطيل بعدد من البكسلات مع حماية الحدود
  static Rect expandRect(Rect rect, double pixels, Size imageSize) {
    final double left = (rect.left - pixels).clamp(0.0, imageSize.width);
    final double top = (rect.top - pixels).clamp(0.0, imageSize.height);
    final double right = (rect.right + pixels).clamp(0.0, imageSize.width);
    final double bottom = (rect.bottom + pixels).clamp(0.0, imageSize.height);
    return Rect.fromLTRB(left, top, right, bottom);
  }

  /// أخذ عينات ذكية من حلقة خارجية حول المستطيل لتحديد لون الخلفية الحقيقي
  /// بدلاً من أخذ العينات من داخل المستطيل (حيث يوجد نص أسود يشوّش النتيجة)
  /// نأخذ العينات من 12 نقطة على بعد [outerMargin] بكسل خارج حدود المستطيل
  static Color sampleBubbleColor(Uint32List pixels, int imgWidth, int imgHeight, Rect rect) {
    int getPixelColor(int x, int y) {
      x = x.clamp(0, imgWidth - 1);
      y = y.clamp(0, imgHeight - 1);
      return pixels[y * imgWidth + x];
    }

    // هامش خارجي لأخذ العينات بعيداً عن النص
    const double outerMargin = 8.0;

    final double left = rect.left;
    final double top = rect.top;
    final double right = rect.right;
    final double bottom = rect.bottom;
    final double midX = left + rect.width / 2;
    final double midY = top + rect.height / 2;

    // 12 نقطة موزعة على حلقة خارجية حول المستطيل
    final sampleCoords = [
      // الأركان الخارجية (خارج حدود المستطيل بـ outerMargin بكسل)
      Offset(left - outerMargin, top - outerMargin),
      Offset(right + outerMargin, top - outerMargin),
      Offset(left - outerMargin, bottom + outerMargin),
      Offset(right + outerMargin, bottom + outerMargin),
      // منتصف الأضلاع الخارجية
      Offset(midX, top - outerMargin),
      Offset(midX, bottom + outerMargin),
      Offset(left - outerMargin, midY),
      Offset(right + outerMargin, midY),
      // نقاط إضافية عند الربع والثلاثة أرباع على الحواف الخارجية
      Offset(left + rect.width * 0.25, top - outerMargin),
      Offset(left + rect.width * 0.75, top - outerMargin),
      Offset(left + rect.width * 0.25, bottom + outerMargin),
      Offset(left + rect.width * 0.75, bottom + outerMargin),
    ];

    final colors = sampleCoords.map((coord) {
      return getPixelColor(coord.dx.toInt(), coord.dy.toInt());
    }).toList();

    // فرز العينات حسب السطوع (Luminance)
    colors.sort((a, b) {
      final rA = a & 0xFF;
      final gA = (a >> 8) & 0xFF;
      final bA = (a >> 16) & 0xFF;
      final brightA = rA * 0.299 + gA * 0.587 + bA * 0.114;

      final rB = b & 0xFF;
      final gB = (b >> 8) & 0xFF;
      final bB = (b >> 16) & 0xFF;
      final brightB = rB * 0.299 + gB * 0.587 + bB * 0.114;

      return brightA.compareTo(brightB);
    });

    // استخدام قيم وسيطة (نستبعد الربع الأعلى والربع الأدنى للسطوع) لمنع النقاط الشاذة تماماً
    // نأخذ متوسط القيم الست الوسطى (من الفهرس 3 إلى 8)
    int totalR = 0, totalG = 0, totalB = 0;
    const startIndex = 3;
    const count = 6;
    for (int j = startIndex; j < startIndex + count; j++) {
      final pixel = colors[j];
      totalR += pixel & 0xFF;
      totalG += (pixel >> 8) & 0xFF;
      totalB += (pixel >> 16) & 0xFF;
    }

    final r = totalR ~/ count;
    final g = totalG ~/ count;
    final b = totalB ~/ count;

    final avgBright = r * 0.299 + g * 0.587 + b * 0.114;

    // تطبيع الألوان الفاتحة جداً والداكنة جداً للوضوح
    if (avgBright > 225) {
      return Colors.white;
    } else if (avgBright < 35) {
      return Colors.black;
    } else {
      return Color.fromARGB(255, r, g, b);
    }
  }

  /// التحقق مما إذا كانت خلفية الفقاعة مظلمة
  static bool isBubbleDark(Uint32List pixels, int imgWidth, int imgHeight, Rect rect) {
    final color = sampleBubbleColor(pixels, imgWidth, imgHeight, rect);
    final brightness = (color.r * 255.0) * 0.299 + (color.g * 255.0) * 0.587 + (color.b * 255.0) * 0.114;
    return brightness <= 150;
  }
}
