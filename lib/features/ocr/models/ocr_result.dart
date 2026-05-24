import 'package:flutter/material.dart';

/// نتيجة التعرف على النص
/// OCR result model containing text, bounding box, and metadata
class OcrResult {
  final String text;           // النص المستخرج
  final Rect boundingBox;      // الإحداثيات (x, y, width, height)
  final List<Rect> lineBoxes;  // إحداثيات كل سطر داخل هذا المربع بشكل دقيق
  final String detectedScript; // نوع النص (ja, ko, zh, en)
  final double confidence;     // نسبة الثقة

  const OcrResult({
    required this.text,
    required this.boundingBox,
    this.lineBoxes = const [],
    required this.detectedScript,
    this.confidence = 1.0,
  });

  OcrResult copyWith({
    String? text,
    Rect? boundingBox,
    List<Rect>? lineBoxes,
    String? detectedScript,
    double? confidence,
  }) {
    return OcrResult(
      text: text ?? this.text,
      boundingBox: boundingBox ?? this.boundingBox,
      lineBoxes: lineBoxes ?? this.lineBoxes,
      detectedScript: detectedScript ?? this.detectedScript,
      confidence: confidence ?? this.confidence,
    );
  }

  @override
  String toString() {
    return 'OcrResult(text: $text, script: $detectedScript, box: $boundingBox)';
  }
}
