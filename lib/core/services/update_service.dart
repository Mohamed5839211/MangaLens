import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../constants/app_colors.dart';
import '../constants/app_constants.dart';
import '../../features/browser/providers/browser_provider.dart';
import '../providers/navigation_provider.dart';

class AppUpdateInfo {
  final String latestVersion;
  final String releaseNotes;
  final String downloadUrl;

  AppUpdateInfo({
    required this.latestVersion,
    required this.releaseNotes,
    required this.downloadUrl,
  });
}

class UpdateService {
  UpdateService._();

  static final _dio = Dio();

  /// التحقق من وجود تحديثات من مستودع GitHub
  static Future<AppUpdateInfo?> checkForUpdates() async {
    try {
      final response = await _dio.get(
        'https://api.github.com/repos/${AppConstants.githubRepo}/releases/latest',
        options: Options(
          headers: {
            'Accept': 'application/vnd.github.v3+json',
            'User-Agent': 'MangaLens-App',
          },
          sendTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        final String tagName = data['tag_name'] as String? ?? '';
        final String htmlUrl = data['html_url'] as String? ?? 'https://github.com/${AppConstants.githubRepo}/releases';
        final String body = data['body'] as String? ?? 'لا يوجد وصف للتحديث.';

        final latestVersion = tagName.replaceAll('v', '').trim();
        if (_isNewerVersion(AppConstants.appVersion, latestVersion)) {
          return AppUpdateInfo(
            latestVersion: latestVersion,
            releaseNotes: body,
            downloadUrl: htmlUrl,
          );
        }
      }
    } catch (e) {
      debugPrint('⚠️ [UpdateCheck] Failed to check for updates: $e');
    }
    return null;
  }

  static bool _isNewerVersion(String current, String latest) {
    final curClean = current.replaceAll(RegExp(r'[^0-9.]'), '');
    final latClean = latest.replaceAll(RegExp(r'[^0-9.]'), '');

    final curParts = curClean.split('.').map(int.tryParse).toList();
    final latParts = latClean.split('.').map(int.tryParse).toList();

    for (int i = 0; i < 3; i++) {
      final curVal = (i < curParts.length) ? (curParts[i] ?? 0) : 0;
      final latVal = (i < latParts.length) ? (latParts[i] ?? 0) : 0;
      if (latVal > curVal) return true;
      if (latVal < curVal) return false;
    }
    return false;
  }

  /// عرض نافذة التحديث بجماليات متناسقة ودعم RTL
  static void showUpdateDialog(BuildContext context, WidgetRef ref, AppUpdateInfo updateInfo) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.system_update_rounded, color: AppColors.primary, size: 28),
            const SizedBox(width: 12),
            Text(
              'يتوفر تحديث جديد! 🚀',
              style: GoogleFonts.cairo(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'الإصدار الحالي: ${AppConstants.appVersion}',
              style: GoogleFonts.cairo(color: AppColors.textSecondary, fontSize: 13),
            ),
            Text(
              'الإصدار الجديد: ${updateInfo.latestVersion}',
              style: GoogleFonts.cairo(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'ملاحظات الإصدار:',
              style: GoogleFonts.cairo(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              constraints: const BoxConstraints(maxHeight: 150),
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: SingleChildScrollView(
                child: Text(
                  updateInfo.releaseNotes,
                  style: GoogleFonts.cairo(color: Colors.white70, fontSize: 12),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'لاحقاً',
              style: GoogleFonts.cairo(color: AppColors.textSecondary, fontWeight: FontWeight.w600),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              // فتح صفحة التحميل في المتصفح المدمج
              ref.read(browserProvider.notifier).openInNewTab(updateInfo.downloadUrl);
              ref.read(navigationProvider.notifier).state = 1; // الانتقال للمتصفح
            },
            child: Text(
              'تحديث الآن',
              style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
