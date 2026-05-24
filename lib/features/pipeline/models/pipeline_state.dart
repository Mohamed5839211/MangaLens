import 'dart:typed_data';
import '../../ocr/models/ocr_result.dart';

/// حالات خط أنابيب الترجمة
/// Translation pipeline statuses
enum PipelineStatus {
  idle,        // في انتظار طلب المستخدم
  capturing,   // التقاط صورة الشاشة
  recognizing, // التعرف على النص (OCR)
  translating, // إرسال النص لـ Groq + معالجة الصورة OpenCV بالتوازي
  rendering,   // رسم النص العربي على الصورة المنظفة
  completed,   // اكتملت العملية
  error,       // حدث خطأ
}

/// نموذج حالة خط الأنابيب
/// Pipeline state model
class PipelineState {
  final PipelineStatus status;
  final Uint8List? originalImage;
  final List<OcrResult>? ocrResults;
  final List<String>? translations;
  final Uint8List? cleanedImage;
  final Uint8List? finalImage;
  final String? errorMessage;
  final double progress; // من 0.0 إلى 1.0 لتمثيل التقدم الكلي

  const PipelineState({
    this.status = PipelineStatus.idle,
    this.originalImage,
    this.ocrResults,
    this.translations,
    this.cleanedImage,
    this.finalImage,
    this.errorMessage,
    this.progress = 0.0,
  });

  PipelineState copyWith({
    PipelineStatus? status,
    Uint8List? originalImage,
    List<OcrResult>? ocrResults,
    List<String>? translations,
    Uint8List? cleanedImage,
    Uint8List? finalImage,
    String? errorMessage,
    double? progress,
  }) {
    return PipelineState(
      status: status ?? this.status,
      originalImage: originalImage ?? this.originalImage,
      ocrResults: ocrResults ?? this.ocrResults,
      translations: translations ?? this.translations,
      cleanedImage: cleanedImage ?? this.cleanedImage,
      finalImage: finalImage ?? this.finalImage,
      errorMessage: errorMessage ?? this.errorMessage,
      progress: progress ?? this.progress,
    );
  }

  /// إعادة تعيين الحالة إلى البداية
  PipelineState reset() {
    return const PipelineState(status: PipelineStatus.idle);
  }

  /// هل هو قيد المعالجة؟
  bool get isProcessing =>
      status != PipelineStatus.idle &&
      status != PipelineStatus.completed &&
      status != PipelineStatus.error;
}
