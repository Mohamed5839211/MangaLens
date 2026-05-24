import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_text_styles.dart';
import '../core/localization/app_localizations.dart';
import '../features/pipeline/models/pipeline_state.dart';
import '../features/pipeline/providers/pipeline_provider.dart';

/// غطاء التحميل لخط الأنابيب
/// Pipeline loading overlay
class LoadingOverlay extends ConsumerWidget {
  const LoadingOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pipelineState = ref.watch(pipelineProvider);

    if (!pipelineState.isProcessing) {
      return const SizedBox.shrink();
    }

    return Positioned.fill(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: Container(
          color: AppColors.glassDark, // Glass background
          child: Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 40),
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: AppColors.glassSurface,
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: AppColors.glassBorder),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.15),
                    blurRadius: 40,
                    spreadRadius: 10,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // شعار أو أيقونة متحركة
                  const CircularProgressIndicator(
                    color: AppColors.primary,
                    strokeWidth: 3,
                  ).animate(onPlay: (controller) => controller.repeat())
                   .shimmer(duration: 1.seconds, color: AppColors.primaryLight),
                  const SizedBox(height: 32),
                  
                  // رسالة الحالة
                  Text(
                    _getStatusMessage(context, pipelineState.status),
                    style: AppTextStyles.headlineSmall,
                    textAlign: TextAlign.center,
                  ).animate(key: ValueKey(pipelineState.status)).slideY(begin: 0.5, duration: 300.ms).fadeIn(),
                  
                  const SizedBox(height: 24),
                  
                  // شريط التقدم
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: pipelineState.progress > 0 ? pipelineState.progress : null,
                      backgroundColor: Colors.black26,
                      color: AppColors.primary,
                      minHeight: 6,
                    ),
                  ),
                  
                  // زر إلغاء (في حال طال الانتظار)
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () {
                      ref.read(pipelineProvider.notifier).reset();
                    },
                    child: Text(
                      context.tr('cancel'),
                      style: AppTextStyles.button.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ).animate().scaleXY(begin: 0.8, end: 1.0, duration: 400.ms, curve: Curves.easeOutBack).fadeIn(),
          ),
        ).animate().fadeIn(duration: 300.ms),
      ),
    );
  }

  String _getStatusMessage(BuildContext context, PipelineStatus status) {
    switch (status) {
      case PipelineStatus.capturing:
        return context.tr('capturing');
      case PipelineStatus.recognizing:
        return context.tr('recognizing');
      case PipelineStatus.translating:
        return context.tr('translating');
      case PipelineStatus.rendering:
        return context.tr('rendering');
      default:
        return context.tr('loading');
    }
  }
}
