import 'dart:io';
import 'package:flutter/material.dart';

/// عنصر عرض الصور بشكل آمن — يدعم الملفات المحلية وروابط الإنترنت
/// يعطي الأولوية للملفات المحلية (التي تم تحميلها من داخل سياق المتصفح)
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
      return placeholder(context);
    }

    // ─── ملف محلي (تم حفظه من base64 في المتصفح) ───
    if (_isLocalPath(imageUrl)) {
      final file = File(imageUrl);
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: fit,
          errorBuilder: (_, __, ___) => placeholder(context),
        );
      }
      return placeholder(context);
    }

    // ─── صور Base64 ───
    if (imageUrl.startsWith('data:')) {
      return placeholder(context);
    }

    // ─── صور من الإنترنت (Fallback) ───
    return Image.network(
      imageUrl,
      fit: fit,
      errorBuilder: (_, __, ___) => placeholder(context),
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return placeholder(context);
      },
    );
  }

  /// هل هذا مسار ملف محلي؟
  bool _isLocalPath(String path) {
    // Android: /data/user/... أو /storage/...
    // Windows: C:\... أو D:\...
    if (path.startsWith('/')) return true;
    if (path.length > 2 && path[1] == ':') return true; // Windows drive letter
    if (path.startsWith('file://')) return true;
    return false;
  }
}
