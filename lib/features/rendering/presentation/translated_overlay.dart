import 'dart:ui';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/localization/app_localizations.dart';
import '../../pipeline/providers/pipeline_provider.dart';

/// الشاشة المتراكبة التي تعرض النتيجة النهائية للترجمة
/// Overlay displaying the final translated image with pinch-to-zoom
class TranslatedOverlay extends ConsumerWidget {
  final Uint8List imageBytes;

  const TranslatedOverlay({
    super.key,
    required this.imageBytes,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          color: AppColors.glassDark,
          child: SafeArea(
            child: Stack(
              children: [
                // ─── عارض الصورة التفاعلي (تكبير/تصغير/تحريك) ──────────
                Positioned.fill(
              child: InteractiveViewer(
                minScale: 1.0,
                maxScale: 5.0,
                panEnabled: true,
                boundaryMargin: const EdgeInsets.all(double.infinity),
                child: Image.memory(
                  imageBytes,
                  fit: BoxFit.contain,
                ),
              ),
            ).animate().scale(begin: const Offset(0.8, 0.8), duration: 600.ms, curve: Curves.easeOutBack).fadeIn(),

            // ─── شريط الأزرار العلوي ────────────────────────────────
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // زر الإغلاق
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated.withOpacity(0.8),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white),
                      onPressed: () {
                        // إغلاق العارض وإعادة تعيين خط الأنابيب
                        ref.read(pipelineProvider.notifier).reset();
                      },
                    ),
                  ),

                  // زر الحفظ / المشاركة
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated.withOpacity(0.8),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.download_rounded, color: Colors.white),
                      tooltip: context.tr('saveImage'),
                      onPressed: () {
                        // TODO: تنفيذ حفظ الصورة في المعرض
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(context.tr('imageSaved'))),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
          ),
        ),
      ),
    ).animate().fadeIn(duration: 400.ms);
  }
}
