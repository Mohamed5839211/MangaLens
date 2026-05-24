import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:image/image.dart' as img;
import '../../ocr/models/ocr_result.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/image_utils.dart';

/// خدمة تنظيف الصور (Inpainting) باستخدام OpenCV والمعالجة الخلفية (Isolates)
/// OpenCV Image Inpainting Service (Torii Method) optimized with background Isolates
class InpaintingService {

  /// تحويل أي صيغة صورة (WebP, JPEG, etc.) إلى PNG خام لضمان توافق OpenCV
  /// يعمل في Isolate خلفي لمنع جرف الإطارات
  Future<Uint8List> _ensurePngFormat(Uint8List imageBytes) async {
    try {
      return await Isolate.run(() {
        final decoded = img.decodeImage(imageBytes);
        if (decoded == null) return imageBytes;
        return Uint8List.fromList(img.encodePng(decoded));
      });
    } catch (e) {
      debugPrint('⚠️ PNG conversion in Isolate failed, using original: $e');
      return imageBytes;
    }
  }

  static bool _isOpenCvInpaintSupported = true;

  /// تنظيف فقاعات النصوص من الصورة
  Future<Uint8List> cleanBubbles(
      Uint8List originalImage, List<OcrResult> ocrResults, [List<String>? translations]) async {
    
    if (ocrResults.isEmpty) return originalImage;

    if (!_isOpenCvInpaintSupported) {
      return _fallbackClean(originalImage, ocrResults, translations);
    }

    ui.Image? image;
    cv.Mat? srcMat;
    cv.Mat? mask;
    cv.Mat? resultMat;

    try {
      // 0. تحويل الصورة إلى PNG لضمان عمل OpenCV (حل مشكلة WebP) في Isolate خلفي
      final pngImage = await _ensurePngFormat(originalImage);

      // 1. تحويل الصورة إلى مصفوفة OpenCV
      srcMat = cv.imdecode(pngImage, cv.IMREAD_COLOR);

      // التحقق من نجاح فك التشفير
      if (srcMat.isEmpty || srcMat.rows == 0 || srcMat.cols == 0) {
        debugPrint('⚠️ OpenCV imdecode failed, falling back to Canvas');
        return _fallbackClean(originalImage, ocrResults, translations);
      }

      // 2. إنشاء القناع الدقيق
      image = await ImageUtils.bytesToImage(originalImage);
      final maskBytes = await _generatePreciseMask(
        image: image,
        ocrResults: ocrResults,
        translations: translations,
      );
      
      // 3. فك تشفير القناع في OpenCV
      mask = cv.imdecode(maskBytes, cv.IMREAD_GRAYSCALE);

      // 4. تطبيق Inpainting
      resultMat = cv.inpaint(
        srcMat,
        mask,
        AppConstants.inpaintRadius.toDouble(),
        cv.INPAINT_TELEA,
      );

      // 5. تحويل المصفوفة الناتجة إلى Uint8List
      final (success, encodedBytes) = cv.imencode('.png', resultMat);
      
      if (success) {
        return encodedBytes;
      } else {
        throw Exception("Failed to encode inpainted image");
      }
    } catch (e) {
      final errorStr = e.toString();
      if (errorStr.contains('cv_inpaint') ||
          errorStr.contains('Failed to lookup symbol') ||
          errorStr.contains('undefined symbol')) {
        _isOpenCvInpaintSupported = false;
        debugPrint('ℹ️ OpenCV Inpainting is not supported on this platform. Permanently switched to Smart Canvas Fallback.');
      } else {
        debugPrint('Inpainting Error: $e');
      }
      return _fallbackClean(originalImage, ocrResults, translations);
    } finally {
      // تحرير الذاكرة لمنع تسربها
      image?.dispose();
      srcMat?.dispose();
      mask?.dispose();
      resultMat?.dispose();
    }
  }

  /// إنشاء قناع دقيق للغاية عند مستوى البكسل للنصوص فقط لتفادي تدمير حدود الفقاعات
  /// تم تحسينها لتعمل المعالجة الحسابية المكثفة داخل Isolate مستقل
  Future<Uint8List> _generatePreciseMask({
    required ui.Image image,
    required List<OcrResult> ocrResults,
    List<String>? translations,
  }) async {
    final width = image.width;
    final height = image.height;

    // 1. استخراج البكسلات الخام من الصورة الأصلية على خيط الواجهة
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) throw Exception("Failed to get image byte data");
    final Uint32List pixels = byteData.buffer.asUint32List();

    // 2. تمرير العمليات الحسابية الكثيفة لـ Isolate مستقل لمنع تجميد الشاشة
    final maskPixelsRaw = await Isolate.run(() {
      final maskPixels = Uint32List(width * height);

      for (int i = 0; i < ocrResults.length; i++) {
        final result = ocrResults[i];

        // تخطي المؤثرات الصوتية (SFX)
        if (translations != null && i < translations.length) {
          if (_isSfx(translations[i])) {
            continue;
          }
        }

        // تحديد الحيز المناسب للمسح (على مستوى السطر)
        final List<Rect> scanBoxes = result.lineBoxes.isNotEmpty ? result.lineBoxes : [result.boundingBox];
        final Rect sampleRect = result.boundingBox;

        // تحديد لون الخلفية للفقاعة ومستوى التجانس
        final Color bgColor = ImageUtils.sampleBubbleColor(pixels, width, height, sampleRect);
        final bgR = (bgColor.r * 255.0).round().clamp(0, 255);
        final bgG = (bgColor.g * 255.0).round().clamp(0, 255);
        final bgB = (bgColor.b * 255.0).round().clamp(0, 255);

        for (final scanBox in scanBoxes) {
          final left = scanBox.left.toInt().clamp(0, width - 1);
          final top = scanBox.top.toInt().clamp(0, height - 1);
          final right = scanBox.right.toInt().clamp(0, width - 1);
          final bottom = scanBox.bottom.toInt().clamp(0, height - 1);

          final dilation = (scanBox.height * 0.06).round().clamp(1, 2);

          // ─── احتساب عتبة التباين الديناميكية للفقاعات البيضاء المتجانسة ───
          int maxDiff = 0;
          for (int y = top; y <= bottom; y += 2) {
            for (int x = left; x <= right; x += 2) {
              final pixel = pixels[y * width + x];
              final r = pixel & 0xFF;
              final g = (pixel >> 8) & 0xFF;
              final b = (pixel >> 16) & 0xFF;
              final diff = (r - bgR).abs() + (g - bgG).abs() + (b - bgB).abs();
              if (diff > maxDiff) maxDiff = diff;
            }
          }

          final dynamicThreshold = maxDiff < 75 ? (maxDiff * 0.5).clamp(20.0, 75.0) : 75.0;

          // التكرار على بكسلات الصندوق للعزل الدقيق
          for (int y = top; y <= bottom; y++) {
            for (int x = left; x <= right; x++) {
              final pixel = pixels[y * width + x];

              final r = pixel & 0xFF;
              final g = (pixel >> 8) & 0xFF;
              final b = (pixel >> 16) & 0xFF;

              final diff = (r - bgR).abs() + (g - bgG).abs() + (b - bgB).abs();

              bool isTextPixel = false;
              if (diff > dynamicThreshold) {
                isTextPixel = true;
              }

              if (isTextPixel) {
                // تمديد بالقطر الديناميكي لابتلاع الحواف والظلال والوهج تماماً دون تدمير حواف الفقاعة
                for (int dy = -dilation; dy <= dilation; dy++) {
                  for (int dx = -dilation; dx <= dilation; dx++) {
                    final nx = (x + dx).clamp(0, width - 1);
                    final ny = (y + dy).clamp(0, height - 1);
                    maskPixels[ny * width + nx] = 0xFFFFFFFF;
                  }
                }
              }
            }
          }
        }
      }

      return maskPixels.buffer.asUint8List();
    });

    // 3. تحويل مصفوفة البكسلات للقناع إلى Uint8List بصيغة PNG على خيط الواجهة
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      maskPixelsRaw,
      width,
      height,
      ui.PixelFormat.rgba8888,
      (ui.Image img) => completer.complete(img),
    );
    final maskImage = await completer.future;
    final maskBytes = await ImageUtils.imageToBytes(maskImage);
    maskImage.dispose();

    return maskBytes;
  }

  /// حل الطوارئ الذكي: استبدال بكسلات النصوص بدمج وتدرج محلي متلائم (Bilinear Local Interpolation)
  /// تم تحسينها لتعمل داخل Isolate لضمان سلاسة التطبيق الكاملة
  Future<Uint8List> _fallbackClean(
      Uint8List originalImage, List<OcrResult> ocrResults, [List<String>? translations]) async {
    ui.Image? image;
    ui.Image? finalImage;

    try {
      debugPrint('🔧 Using smart Bilinear Pixel-level Canvas fallback optimized with Isolate...');
      
      image = await ImageUtils.bytesToImage(originalImage);
      final width = image.width;
      final height = image.height;

      // 1. استخراج البكسلات الخام على خيط الواجهة
      final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null) return originalImage;
      final Uint32List pixels = byteData.buffer.asUint32List();

      // 2. تشغيل العمليات الحسابية وتعديل البكسلات في Isolate مستقل
      final modifiedPixelsRaw = await Isolate.run(() {
        final modifiedPixels = Uint32List.fromList(pixels);

        for (int i = 0; i < ocrResults.length; i++) {
          final result = ocrResults[i];

          // تخطي المؤثرات الصوتية
          if (translations != null && i < translations.length) {
            if (_isSfx(translations[i])) {
              continue;
            }
          }

          final List<Rect> scanBoxes = result.lineBoxes.isNotEmpty ? result.lineBoxes : [result.boundingBox];
          final Rect sampleRect = result.boundingBox;

          // تحديد لون الخلفية للفقاعة ومستوى التجانس
          final Color bgColor = ImageUtils.sampleBubbleColor(pixels, width, height, sampleRect);
          final int bgR = (bgColor.r * 255.0).round().clamp(0, 255);
          final int bgG = (bgColor.g * 255.0).round().clamp(0, 255);
          final int bgB = (bgColor.b * 255.0).round().clamp(0, 255);

          for (final scanBox in scanBoxes) {
            final left = scanBox.left.toInt().clamp(0, width - 1);
            final top = scanBox.top.toInt().clamp(0, height - 1);
            final right = scanBox.right.toInt().clamp(0, width - 1);
            final bottom = scanBox.bottom.toInt().clamp(0, height - 1);

            final dilation = (scanBox.height * 0.06).round().clamp(1, 2);

            // Define bounds for sampling
            final sampleLeft = (left - 4).clamp(0, width - 1);
            final sampleRight = (right + 4).clamp(0, width - 1);
            final sampleTop = (top - 4).clamp(0, height - 1);
            final sampleBottom = (bottom + 4).clamp(0, height - 1);

            int getInterpolatedColor(int px, int py) {
              final pTL = pixels[sampleTop * width + sampleLeft];
              final pTR = pixels[sampleTop * width + sampleRight];
              final pBL = pixels[sampleBottom * width + sampleLeft];
              final pBR = pixels[sampleBottom * width + sampleRight];

              final double tx = (right > left) ? (px - left) / (right - left) : 0.5;
              final double ty = (bottom > top) ? (py - top) / (bottom - top) : 0.5;
              final clampedTx = tx.clamp(0.0, 1.0);
              final clampedTy = ty.clamp(0.0, 1.0);

              final rTL = pTL & 0xFF;
              final gTL = (pTL >> 8) & 0xFF;
              final bTL = (pTL >> 16) & 0xFF;

              final rTR = pTR & 0xFF;
              final gTR = (pTR >> 8) & 0xFF;
              final bTR = (pTR >> 16) & 0xFF;

              final rBL = pBL & 0xFF;
              final gBL = (pBL >> 8) & 0xFF;
              final bBL = (pBL >> 16) & 0xFF;

              final rBR = pBR & 0xFF;
              final gBR = (pBR >> 8) & 0xFF;
              final bBR = (pBR >> 16) & 0xFF;

              final rT = rTL + (rTR - rTL) * clampedTx;
              final gT = gTL + (gTR - gTL) * clampedTx;
              final bT = bTL + (bTR - bTL) * clampedTx;

              final rB = rBL + (rBR - rBL) * clampedTx;
              final gB = gBL + (gBR - gBL) * clampedTx;
              final bB = bBL + (bBR - bBL) * clampedTx;

              final r = (rT + (rB - rT) * clampedTy).round().clamp(0, 255);
              final g = (gT + (gB - gT) * clampedTy).round().clamp(0, 255);
              final b = (bT + (bB - bT) * clampedTy).round().clamp(0, 255);

              return (0xFF << 24) | (b << 16) | (g << 8) | r;
            }

            // ─── احتساب عتبة التباين الديناميكية للفقاعات البيضاء ───
            int maxDiff = 0;
            for (int y = top; y <= bottom; y += 2) {
              for (int x = left; x <= right; x += 2) {
                final pixel = pixels[y * width + x];
                final r = pixel & 0xFF;
                final g = (pixel >> 8) & 0xFF;
                final b = (pixel >> 16) & 0xFF;
                final diff = (r - bgR).abs() + (g - bgG).abs() + (b - bgB).abs();
                if (diff > maxDiff) maxDiff = diff;
              }
            }

            final dynamicThreshold = maxDiff < 75 ? (maxDiff * 0.5).clamp(20.0, 75.0) : 75.0;

            // التكرار على بكسلات الصندوق فقط للتنظيف الدقيق
            for (int y = top; y <= bottom; y++) {
              for (int x = left; x <= right; x++) {
                final pixel = pixels[y * width + x];

                final r = pixel & 0xFF;
                final g = (pixel >> 8) & 0xFF;
                final b = (pixel >> 16) & 0xFF;

                final diff = (r - bgR).abs() + (g - bgG).abs() + (b - bgB).abs();

                bool isTextPixel = false;
                if (diff > dynamicThreshold) {
                  isTextPixel = true;
                }

                if (isTextPixel) {
                  // استبدال البكسل بدمج ثنائي البعد مع تمدد ديناميكي للحواف والظلال
                  for (int dy = -dilation; dy <= dilation; dy++) {
                    for (int dx = -dilation; dx <= dilation; dx++) {
                      final nx = (x + dx).clamp(0, width - 1);
                      final ny = (y + dy).clamp(0, height - 1);
                      modifiedPixels[ny * width + nx] = getInterpolatedColor(nx, ny);
                    }
                  }
                }
              }
            }
          }
        }
        return modifiedPixels.buffer.asUint8List();
      });

      // 3. إعادة بناء الصورة من البكسلات المعدلة على خيط الواجهة
      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        modifiedPixelsRaw,
        width,
        height,
        ui.PixelFormat.rgba8888,
        (ui.Image img) => completer.complete(img),
      );
      finalImage = await completer.future;
      return await ImageUtils.imageToBytes(finalImage);

    } catch (e) {
      debugPrint('❌ Smart fallback clean failed: $e');
      return originalImage;
    } finally {
      image?.dispose();
      finalImage?.dispose();
    }
  }

  /// التحقق مما إذا كان النص مؤثر صوتي بناءً على الهيكل
  static bool _isSfx(String text) {
    final trimmed = text.trim();
    return trimmed.startsWith('[') &&
        (trimmed.toLowerCase().contains('sfx:') || trimmed.contains('صوت:'));
  }

}
