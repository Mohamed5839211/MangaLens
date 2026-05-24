import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
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

        String downloadUrl = htmlUrl;
        if (data['assets'] != null && data['assets'] is List) {
          final assets = data['assets'] as List;
          for (final asset in assets) {
            if (asset is Map<String, dynamic>) {
              final name = asset['name'] as String? ?? '';
              if (name.endsWith('.apk')) {
                downloadUrl = asset['browser_download_url'] as String? ?? htmlUrl;
                break;
              }
            }
          }
        }

        final latestVersion = tagName.replaceAll('v', '').trim();
        if (_isNewerVersion(AppConstants.appVersion, latestVersion)) {
          return AppUpdateInfo(
            latestVersion: latestVersion,
            releaseNotes: body,
            downloadUrl: downloadUrl,
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
              if (updateInfo.downloadUrl.endsWith('.apk')) {
                // فتح حوار التحميل الداخلي
                showDialog(
                  context: context,
                  barrierDismissible: false, // منع الإغلاق أثناء التحميل
                  builder: (context) => DownloadProgressDialog(
                    downloadUrl: updateInfo.downloadUrl,
                  ),
                );
              } else {
                // فتح صفحة التحميل في المتصفح المدمج كخيار احتياطي
                ref.read(browserProvider.notifier).openInNewTab(updateInfo.downloadUrl);
                ref.read(navigationProvider.notifier).state = 1; // الانتقال للمتصفح
              }
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

class DownloadProgressDialog extends StatefulWidget {
  final String downloadUrl;

  const DownloadProgressDialog({super.key, required this.downloadUrl});

  @override
  State<DownloadProgressDialog> createState() => _DownloadProgressDialogState();
}

class _DownloadProgressDialogState extends State<DownloadProgressDialog> {
  final Dio _dio = Dio();
  double _progress = 0.0;
  String _statusText = 'جاري التحضير لبدء التحميل...';
  CancelToken? _cancelToken;
  bool _isDownloading = true;

  @override
  void initState() {
    super.initState();
    _startDownload();
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    super.dispose();
  }

  Future<void> _startDownload() async {
    _cancelToken = CancelToken();
    try {
      final tempDir = await getTemporaryDirectory();
      final savePath = '${tempDir.path}/MangaLens_Update.apk';

      setState(() {
        _statusText = 'جاري تحميل التحديث...';
      });

      await _dio.download(
        widget.downloadUrl,
        savePath,
        cancelToken: _cancelToken,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            setState(() {
              _progress = received / total;
              final percent = (_progress * 100).toStringAsFixed(0);
              _statusText = 'جاري تحميل ملف التحديث: $percent%';
            });
          }
        },
      );

      if (!mounted) return;

      setState(() {
        _isDownloading = false;
        _statusText = 'اكتمل التحميل! جاري فتح التثبيت...';
      });

      // فتح وتثبيت الـ APK
      final openResult = await OpenFilex.open(savePath);
      
      if (!mounted) return;
      
      if (openResult.type != ResultType.done) {
        setState(() {
          _statusText = 'فشل فتح ملف التثبيت: ${openResult.message}';
        });
      } else {
        Navigator.pop(context); // إغلاق الحوار تلقائياً عند بدء التثبيت
      }
    } catch (e) {
      if (!mounted) return;
      if (CancelToken.isCancel(e as DioException)) {
        setState(() {
          _statusText = 'تم إلغاء التحميل.';
          _isDownloading = false;
        });
      } else {
        setState(() {
          _statusText = 'حدث خطأ أثناء التحميل: $e';
          _isDownloading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'تنزيل التحديث 📥',
          style: GoogleFonts.cairo(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: _progress,
              backgroundColor: AppColors.surface,
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 16),
            Text(
              _statusText,
              textAlign: TextAlign.center,
              style: GoogleFonts.cairo(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 8),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              _cancelToken?.cancel();
              Navigator.pop(context);
            },
            child: Text(
              _isDownloading ? 'إلغاء' : 'إغلاق',
              style: GoogleFonts.cairo(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
