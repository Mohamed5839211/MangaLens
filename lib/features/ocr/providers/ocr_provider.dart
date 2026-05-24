import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/ocr_service.dart';

/// مزود خدمة التعرف على النصوص
/// OCR Service Provider
final ocrServiceProvider = Provider<OcrService>((ref) {
  final service = OcrService();
  
  // إغلاق الموارد عند تدمير المزود
  ref.onDispose(() {
    service.dispose();
  });
  
  return service;
});
