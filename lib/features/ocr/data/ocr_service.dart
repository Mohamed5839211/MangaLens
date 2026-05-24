import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';
import '../models/ocr_result.dart';
import '../../../core/utils/image_utils.dart';

/// خدمة التعرف على النصوص باستخدام Google ML Kit
/// On-Device OCR Service using Google ML Kit (Supports Multi-script)
class OcrService {
  // إنشاء متعرفات النصوص للغات المختلفة
  late final TextRecognizer _japaneseRecognizer;
  late final TextRecognizer _koreanRecognizer;
  late final TextRecognizer _chineseRecognizer;
  late final TextRecognizer _latinRecognizer;

  OcrService() {
    _japaneseRecognizer = TextRecognizer(script: TextRecognitionScript.japanese);
    _koreanRecognizer = TextRecognizer(script: TextRecognitionScript.korean);
    _chineseRecognizer = TextRecognizer(script: TextRecognitionScript.chinese);
    _latinRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
  }

  /// إغلاق المتعرفات عند الانتهاء
  void dispose() {
    _japaneseRecognizer.close();
    _koreanRecognizer.close();
    _chineseRecognizer.close();
    _latinRecognizer.close();
  }

  /// التعرف على النص من صورة (Uint8List)
  /// [sourceLangCode] إذا كان 'auto'، يشغل كل المتعرفات. وإلا يشغل المتعرف المحدد فقط.
  Future<List<OcrResult>> recognizeText(Uint8List imageBytes, {String sourceLangCode = 'auto'}) async {
    try {
      // تحويل البايتات إلى ui.Image لمعرفة الأبعاد الحقيقية والتمكن من التقطيع
      final image = await ImageUtils.bytesToImage(imageBytes);
      final double width = image.width.toDouble();
      final double height = image.height.toDouble();

      List<OcrResult> allBlocks = [];

      // إذا كانت الصورة طويلة جداً (مثل صفحات الويب تون)، نقطعها لمنع تشوه النصوص عند تصغيرها في ML Kit
      if (height > 1500.0) {
        debugPrint('✂️ Very tall image detected (${width.toInt()}x${height.toInt()}). Slicing into chunks for accurate OCR...');
        final double sliceHeight = 1200.0;
        final double overlap = 150.0;
        double yOffset = 0.0;

        while (yOffset < height) {
          double currentSliceHeight = sliceHeight;
          if (yOffset + currentSliceHeight > height) {
            currentSliceHeight = height - yOffset;
          }

          final srcRect = Rect.fromLTWH(0, yOffset, width, currentSliceHeight);
          
          // رسم القطعة الحالية على Canvas جديد
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width, currentSliceHeight));
          
          canvas.drawImageRect(
            image,
            srcRect,
            Rect.fromLTWH(0, 0, width, currentSliceHeight),
            Paint(),
          );
          
          final picture = recorder.endRecording();
          final sliceImage = await picture.toImage(width.toInt(), currentSliceHeight.toInt());
          final sliceBytes = await ImageUtils.imageToBytes(sliceImage);
          sliceImage.dispose();

          // تشغيل OCR على القطعة
          final sliceResults = await _recognizeTextSingleFrame(sliceBytes, sourceLangCode: sourceLangCode);
          
          // تعديل الإحداثيات بإضافة الإزاحة العمودية
          for (final result in sliceResults) {
            final box = result.boundingBox;
            final shiftedBox = Rect.fromLTRB(
              box.left,
              box.top + yOffset,
              box.right,
              box.bottom + yOffset,
            );
            final shiftedLineBoxes = result.lineBoxes.map((lBox) {
              return Rect.fromLTRB(
                lBox.left,
                lBox.top + yOffset,
                lBox.right,
                lBox.bottom + yOffset,
              );
            }).toList();

            allBlocks.add(OcrResult(
              text: result.text,
              boundingBox: shiftedBox,
              lineBoxes: shiftedLineBoxes,
              detectedScript: result.detectedScript,
            ));
          }

          yOffset += (sliceHeight - overlap);
          if (yOffset + overlap >= height) {
            break;
          }
        }
      } else {
        // صورة عادية، تشغيل OCR مباشرة
        allBlocks = await _recognizeTextSingleFrame(imageBytes, sourceLangCode: sourceLangCode);
      }

      image.dispose();

      // إزالة التكرارات المتقاطعة (نفس الفقاعة تم التعرف عليها بلغتين أو في قطعتين متداخلتين)
      final filteredBlocks = _filterOverlappingBlocks(allBlocks);

      // ترتيب النتائج من الأعلى إلى الأسفل، ومن اليمين إلى اليسار
      filteredBlocks.sort((a, b) {
        int yCompare = a.boundingBox.top.compareTo(b.boundingBox.top);
        if (a.boundingBox.top > b.boundingBox.top - 20 &&
            a.boundingBox.top < b.boundingBox.top + 20) {
          return b.boundingBox.right.compareTo(a.boundingBox.right);
        }
        return yCompare;
      });

      return filteredBlocks;
    } catch (e) {
      debugPrint('OCR Error: $e');
      return [];
    }
  }

  /// تشغيل التعرف على صورة مفردة غير مجزأة
  Future<List<OcrResult>> _recognizeTextSingleFrame(Uint8List imageBytes, {required String sourceLangCode}) async {
    final tempDir = await getTemporaryDirectory();
    final uniqueId = DateTime.now().microsecondsSinceEpoch;
    final tempFile = File('${tempDir.path}/temp_ocr_$uniqueId.png');
    await tempFile.writeAsBytes(imageBytes);

    try {
      final inputImage = InputImage.fromFilePath(tempFile.path);
      List<OcrResult> allBlocks = [];

      if (sourceLangCode == 'ja') {
        final results = await Future.wait([
          _recognizeWithScript(inputImage, _japaneseRecognizer, 'ja'),
          _recognizeWithScript(inputImage, _latinRecognizer, 'en'),
        ]);
        allBlocks = results.expand((x) => x).toList();
      } else if (sourceLangCode == 'ko') {
        final results = await Future.wait([
          _recognizeWithScript(inputImage, _koreanRecognizer, 'ko'),
          _recognizeWithScript(inputImage, _latinRecognizer, 'en'),
        ]);
        allBlocks = results.expand((x) => x).toList();
      } else if (sourceLangCode == 'zh') {
        final results = await Future.wait([
          _recognizeWithScript(inputImage, _chineseRecognizer, 'zh'),
          _recognizeWithScript(inputImage, _latinRecognizer, 'en'),
        ]);
        allBlocks = results.expand((x) => x).toList();
      } else if (sourceLangCode != 'auto') {
        allBlocks = await _recognizeWithScript(inputImage, _latinRecognizer, 'en');
      } else {
        final results = await Future.wait([
          _recognizeWithScript(inputImage, _japaneseRecognizer, 'ja'),
          _recognizeWithScript(inputImage, _koreanRecognizer, 'ko'),
          _recognizeWithScript(inputImage, _chineseRecognizer, 'zh'),
          _recognizeWithScript(inputImage, _latinRecognizer, 'en'),
        ]);
        allBlocks = results.expand((x) => x).toList();
      }

      return allBlocks;
    } finally {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    }
  }

  /// تنفيذ التعرف بلغة محددة
  Future<List<OcrResult>> _recognizeWithScript(
      InputImage inputImage, TextRecognizer recognizer, String script) async {
    final recognizedText = await recognizer.processImage(inputImage);
    final List<OcrResult> results = [];

    for (TextBlock block in recognizedText.blocks) {
      if (block.text.trim().isNotEmpty) {
        final List<Rect> lineBoxes = block.lines.map((l) => l.boundingBox).toList();
        results.add(
          OcrResult(
            text: block.text.trim(),
            boundingBox: block.boundingBox,
            lineBoxes: lineBoxes,
            detectedScript: script,
          ),
        );
      }
    }
    return results;
  }

  /// تقييم جودة النص لاختيار الأفضل في حال تداخل اللغات
  int _scoreTextQuality(String text) {
    if (text.isEmpty) return 0;
    
    int score = 0;
    final letters = RegExp(r'[a-zA-Z\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Han}\p{Script=Hangul}]', unicode: true);
    final garbage = RegExp(r'[|\\/_\-\[\]{}<>=+~`^*]');
    
    for (int i = 0; i < text.length; i++) {
      final char = text[i];
      if (letters.hasMatch(char)) {
        score += 2; // الحروف الحقيقية تأخذ نقاط أعلى
      } else if (garbage.hasMatch(char)) {
        score -= 1; // الرموز العشوائية تخصم نقاط
      }
    }
    return score;
  }

  /// تصفية الكتل المتقاطعة باختيار النص ذو الكثافة اللغوية الأعلى (للتخلص من الهلوسة)
  List<OcrResult> _filterOverlappingBlocks(List<OcrResult> blocks) {
    if (blocks.isEmpty) return [];

    final List<OcrResult> filtered = [];
    final Set<int> toRemove = {};

    for (int i = 0; i < blocks.length; i++) {
      if (toRemove.contains(i)) continue;

      OcrResult current = blocks[i];
      int currentScore = _scoreTextQuality(current.text);

      for (int j = i + 1; j < blocks.length; j++) {
        if (toRemove.contains(j)) continue;

        final target = blocks[j];
        
        final intersection = current.boundingBox.intersect(target.boundingBox);
        if (intersection.width > 0 && intersection.height > 0) {
          final intersectArea = intersection.width * intersection.height;
          final currentArea = current.boundingBox.width * current.boundingBox.height;
          final targetArea = target.boundingBox.width * target.boundingBox.height;
          
          final minArea = currentArea < targetArea ? currentArea : targetArea;
          
          // إذا كان التقاطع أكثر من 40%، فهما نفس الفقاعة
          if (intersectArea > minArea * 0.4) {
            int targetScore = _scoreTextQuality(target.text);
            
            // نختار النص الذي يمتلك نقاط أكثر (حروف حقيقية أكثر)
            if (currentScore < targetScore) {
              current = target;
              currentScore = targetScore;
              toRemove.add(i); 
            } else {
              toRemove.add(j);
            }
          }
        }
      }
      
      if (!toRemove.contains(i) || current != blocks[i]) {
          if (!filtered.any((e) => e.boundingBox == current.boundingBox && e.text == current.text)) {
              filtered.add(current);
          }
      }
    }

    return filtered;
  }

  /// الكشف السريع عن لغة الفصل من عدة صور (بشكل لغوي ذكي لمنع الهلوسة)
  Future<String> detectChapterLanguage(List<Uint8List> imagesBytes) async {
    if (imagesBytes.isEmpty) return 'en';

    int totalEn = 0;
    int totalKo = 0;
    int totalJa = 0;
    int totalZh = 0;

    for (final imageBytes in imagesBytes) {
      try {
        final tempDir = await getTemporaryDirectory();
        final tempFile = File('${tempDir.path}/temp_detect_image.png');
        await tempFile.writeAsBytes(imageBytes);
        final inputImage = InputImage.fromFilePath(tempFile.path);

        // تشغيل الجميع بالتوازي لمعرفة الفائز لهذه الصفحة
        final results = await Future.wait([
          _recognizeWithScript(inputImage, _japaneseRecognizer, 'ja'),
          _recognizeWithScript(inputImage, _koreanRecognizer, 'ko'),
          _recognizeWithScript(inputImage, _chineseRecognizer, 'zh'),
          _recognizeWithScript(inputImage, _latinRecognizer, 'en'),
        ]);

        if (await tempFile.exists()) await tempFile.delete();

        final jaText = results[0].map((e) => e.text).join(' ');
        final koText = results[1].map((e) => e.text).join(' ');
        final zhText = results[2].map((e) => e.text).join(' ');
        final enText = results[3].map((e) => e.text).join(' ');

        // ─── 1. حساب نقاط الإنجليزية ───
        final englishWords = RegExp(
          r'\b(the|and|you|read|chapters|of|to|is|in|that|it|he|was|for|on|are|as|with|his|they|i|at|be|this|have|from|or|one|had|by|word|but|not|what|all|were|we|when|your|can|said|there|use|an|each|which|she|do|how|their|if|will|up|other|about|out|many|then|them|these|so|some|her|would|make|like|him|into|time|has|look|two|more|write|go|see|no|way|could|people|my|than|first|been|call|who|its|now|find|long|down|day|did|get|come|made|may|part|fortress|humanity|last|standing|fight|exclusively|thunderscans)\b',
          caseSensitive: false,
        );
        final enWordMatches = englishWords.allMatches(enText).length;
        final enScore = enWordMatches * 15;

        // ─── 2. حساب نقاط الكورية ───
        final koreanHangul = RegExp(r'[\uac00-\ud7af]');
        final koScore = koreanHangul.allMatches(koText).length * 10;

        // ─── 3. حساب نقاط اليابانية ───
        final japaneseKana = RegExp(r'[\u3040-\u309f\u30a0-\u30ff]');
        final jaScore = japaneseKana.allMatches(jaText).length * 10;

        // ─── 4. حساب نقاط الصينية ───
        final chineseHanzi = RegExp(r'[\u4e00-\u9fff]');
        int zhScore = chineseHanzi.allMatches(zhText).length * 5;
        if (japaneseKana.hasMatch(jaText)) {
          zhScore = 0;
        }

        debugPrint('📊 Page Detection Scores: en=$enScore, ko=$koScore, ja=$jaScore, zh=$zhScore');

        // إذا تم اكتشاف لغة آسيوية بثقة عالية في هذه الصفحة، نرجعها مباشرة لتسريع العملية
        if (koScore >= 40) return 'ko';
        if (jaScore >= 40) return 'ja';
        if (zhScore >= 30) return 'zh';

        // خلاف ذلك نجمع النقاط للمقارنة الإجمالية لاحقاً
        totalEn += enScore;
        totalKo += koScore;
        totalJa += jaScore;
        totalZh += zhScore;
      } catch (e) {
        debugPrint('Language Detection Page Error: $e');
      }
    }

    debugPrint('📊 Aggregated Language Scores: en=$totalEn, ko=$totalKo, ja=$totalJa, zh=$totalZh');

    // تحديد اللغة الفائزة من الإجمالي
    String detected = 'en';
    int maxScore = 0;

    if (totalEn > maxScore) {
      maxScore = totalEn;
      detected = 'en';
    }
    if (totalKo > maxScore) {
      maxScore = totalKo;
      detected = 'ko';
    }
    if (totalJa > maxScore) {
      maxScore = totalJa;
      detected = 'ja';
    }
    if (totalZh > maxScore) {
      maxScore = totalZh;
      detected = 'zh';
    }

    // إذا كانت النقاط منخفضة جداً (أقل من 10) نعتمد الإنجليزية كخيار افتراضي
    return maxScore > 10 ? detected : 'en';
  }
}
