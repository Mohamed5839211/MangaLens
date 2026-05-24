import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_text_styles.dart';
import '../core/localization/app_localizations.dart';

/// ديالوج لعرض الأخطاء
/// Dialog for displaying errors
class ErrorDialog extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const ErrorDialog({
    super.key,
    required this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.error),
          const SizedBox(width: 8),
          Text(context.tr('error'), style: AppTextStyles.headlineSmall),
        ],
      ),
      content: Text(message, style: AppTextStyles.bodyMedium),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            context.tr('close'),
            style: AppTextStyles.button.copyWith(color: AppColors.textSecondary),
          ),
        ),
        if (onRetry != null)
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              onRetry!();
            },
            child: Text(context.tr('retry')),
          ),
      ],
    );
  }

  /// إظهار الديالوج بسهولة
  static Future<void> show(
    BuildContext context,
    String message, {
    VoidCallback? onRetry,
  }) {
    return showDialog(
      context: context,
      builder: (context) => ErrorDialog(
        message: message,
        onRetry: onRetry,
      ),
    );
  }
}
