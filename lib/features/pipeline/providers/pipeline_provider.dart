import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../browser/providers/browser_provider.dart';
import '../../ocr/providers/ocr_provider.dart';
import '../../translation/providers/translation_provider.dart';
import '../../inpainting/providers/inpainting_provider.dart';
import '../../rendering/providers/rendering_provider.dart';
import '../models/pipeline_state.dart';

/// مزود خط أنابيب الترجمة (المنسق الرئيسي)
/// Pipeline orchestrator provider
class PipelineNotifier extends Notifier<PipelineState> {
  @override
  PipelineState build() {
    return const PipelineState();
  }

  /// إعادة تعيين الحالة
  void reset() {
    state = state.reset();
  }

  /// تنفيذ خط الأنابيب الكامل (Torii Method)
  Future<void> executePipeline() async {
    if (state.isProcessing) return;

    try {
      // 1. التقاط الشاشة
      state = state.copyWith(status: PipelineStatus.capturing, progress: 0.1);
      final image = await ref.read(browserProvider.notifier).captureScreenshot();
      if (image == null) throw Exception('فشل في التقاط الشاشة');

      // 2. التعرف على النص (OCR)
      state = state.copyWith(
        originalImage: image,
        status: PipelineStatus.recognizing,
        progress: 0.3,
      );
      final ocrResults = await ref.read(ocrServiceProvider).recognizeText(image);
      
      if (ocrResults.isEmpty) {
        state = state.copyWith(status: PipelineStatus.error, errorMessage: 'لم يتم العثور على نص');
        return;
      }
      state = state.copyWith(ocrResults: ocrResults);

      // 3. الترجمة ثم التنظيف (تتابعي لتحديد المؤثرات الصوتية)
      state = state.copyWith(status: PipelineStatus.translating, progress: 0.5);
      final translations = await ref.read(translationProvider).translateBlocks(ocrResults);
      
      state = state.copyWith(progress: 0.7);
      final cleanedImage = await ref.read(inpaintingServiceProvider).cleanBubbles(image, ocrResults, translations);

      state = state.copyWith(
        translations: translations,
        cleanedImage: cleanedImage,
        progress: 0.8,
      );

      // 4. رسم النص العربي على الصورة المنظفة
      state = state.copyWith(status: PipelineStatus.rendering, progress: 0.9);
      final finalImage = await ref.read(textRendererProvider).render(
        cleanedImage,
        translations,
        ocrResults,
      );

      // 5. الانتهاء
      state = state.copyWith(
        status: PipelineStatus.completed,
        finalImage: finalImage,
        progress: 1.0,
      );

    } catch (e) {
      state = state.copyWith(
        status: PipelineStatus.error,
        errorMessage: e.toString(),
      );
    }
  }
}

/// مزود حالة خط الأنابيب الرئيسي
final pipelineProvider = NotifierProvider<PipelineNotifier, PipelineState>(() {
  return PipelineNotifier();
});
