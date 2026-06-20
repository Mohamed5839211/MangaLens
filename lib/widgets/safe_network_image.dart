import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/constants/app_colors.dart';
import '../core/network/network_module.dart';
import '../core/network/cookie_store.dart';
/// عنصر عرض الصور بشكل آمن — يدعم الملفات المحلية وروابط الإنترنت
/// مع تخزين مؤقت (Cache) على القرص لمنع إعادة التحميل عند الـ scroll
class SafeNetworkImage extends StatelessWidget {
  final String imageUrl;
  final String? referrer;
  final BoxFit fit;
  final Widget Function(BuildContext) placeholder;

  const SafeNetworkImage({
    super.key,
    required this.imageUrl,
    this.referrer,
    this.fit = BoxFit.cover,
    required this.placeholder,
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrl.isEmpty) {
      return _brokenPlaceholder();
    }

    // ─── ملف محلي ───
    if (_isLocalPath(imageUrl)) {
      final file = File(imageUrl);
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: fit,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => _brokenPlaceholder(),
        );
      }
      return _brokenPlaceholder();
    }

    // ─── صور Base64 ───
    if (imageUrl.startsWith('data:')) {
      return _brokenPlaceholder();
    }

    // ─── صور من الإنترنت (مع كاش) ───
    final networkModule = NetworkModule();
    final domain = CookieStore.extractDomain(imageUrl);
    final cookies = CookieStore.getCookies(domain) ?? '';

    final headers = <String, String>{
      'User-Agent': networkModule.userAgent.isNotEmpty 
          ? networkModule.userAgent 
          : 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Mobile Safari/537.36',
      'Accept': 'image/webp,image/apng,image/*,*/*;q=0.8',
    };
    
    if (referrer != null) {
      headers['Referer'] = referrer!;
    }
    
    if (cookies.isNotEmpty) {
      headers['Cookie'] = cookies;
    }

    return CachedNetworkImage(
      imageUrl: imageUrl,
      fit: fit,
      httpHeaders: headers,
      placeholder: (context, url) => Container(
        color: AppColors.surfaceElevated,
        child: const Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.primary,
          ),
        ),
      ),
      errorWidget: (context, url, error) => _brokenPlaceholder(),
    );
  }

  /// placeholder جميل للصور المكسورة أو الفارغة
  Widget _brokenPlaceholder() {
    return Container(
      color: AppColors.surfaceElevated,
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image_not_supported_outlined, color: AppColors.textSecondary, size: 28),
            SizedBox(height: 4),
            Text('لا توجد صورة', style: TextStyle(color: AppColors.textSecondary, fontSize: 10, fontFamily: 'Cairo')),
          ],
        ),
      ),
    );
  }

  bool _isLocalPath(String path) {
    if (path.startsWith('/')) return true;
    if (path.length > 2 && path[1] == ':') return true;
    if (path.startsWith('file://')) return true;
    return false;
  }
}
