import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// خدمة التخزين المؤقت للفصول على الجهاز
/// Chapter disk cache service for offline reading
class ChapterCacheService {
  static const String _cacheDir = 'manga_cache';

  /// الحصول على مسار مجلد التخزين المؤقت
  static Future<Directory> _getCacheDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory('${appDir.path}/$_cacheDir');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return cacheDir;
  }

  /// إنشاء معرف فريد للفصل من الرابط
  static String _chapterIdFromUrl(String url) {
    return url.hashCode.toRadixString(16);
  }

  /// حفظ صورة في التخزين المؤقت
  static Future<void> cacheImage(String chapterUrl, int index, Uint8List bytes) async {
    try {
      final dir = await _getCacheDirectory();
      final chapterId = _chapterIdFromUrl(chapterUrl);
      final chapterDir = Directory('${dir.path}/$chapterId');
      if (!await chapterDir.exists()) {
        await chapterDir.create(recursive: true);
      }
      final file = File('${chapterDir.path}/img_$index.png');
      await file.writeAsBytes(bytes);
    } catch (e) {
      debugPrint('Cache write error: $e');
    }
  }

  /// حفظ صورة مترجمة في التخزين المؤقت
  static Future<void> cacheTranslatedImage(String chapterUrl, int index, Uint8List bytes) async {
    try {
      final dir = await _getCacheDirectory();
      final chapterId = _chapterIdFromUrl(chapterUrl);
      final chapterDir = Directory('${dir.path}/$chapterId');
      if (!await chapterDir.exists()) {
        await chapterDir.create(recursive: true);
      }
      final file = File('${chapterDir.path}/tr_$index.png');
      await file.writeAsBytes(bytes);
    } catch (e) {
      debugPrint('Cache write error: $e');
    }
  }

  /// جلب صورة أصلية من التخزين المؤقت
  static Future<Uint8List?> getCachedImage(String chapterUrl, int index) async {
    try {
      final dir = await _getCacheDirectory();
      final chapterId = _chapterIdFromUrl(chapterUrl);
      final file = File('${dir.path}/$chapterId/img_$index.png');
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        // تجاهل الملفات التالفة (أقل من 500 بايت ليست صوراً حقيقية)
        if (bytes.length < 500) {
          debugPrint('🗑️ Removing corrupt cached image $index (${bytes.length} bytes)');
          await file.delete();
          return null;
        }
        return bytes;
      }
    } catch (e) {
      debugPrint('Cache read error: $e');
    }
    return null;
  }

  /// جلب صورة مترجمة من التخزين المؤقت
  static Future<Uint8List?> getCachedTranslatedImage(String chapterUrl, int index) async {
    try {
      final dir = await _getCacheDirectory();
      final chapterId = _chapterIdFromUrl(chapterUrl);
      final file = File('${dir.path}/$chapterId/tr_$index.png');
      if (await file.exists()) {
        return await file.readAsBytes();
      }
    } catch (e) {
      debugPrint('Cache read error: $e');
    }
    return null;
  }

  /// حساب حجم التخزين المؤقت الكلي
  static Future<String> getCacheSize() async {
    try {
      final dir = await _getCacheDirectory();
      if (!await dir.exists()) return '0 MB';
      int totalSize = 0;
      await for (var entity in dir.list(recursive: true)) {
        if (entity is File) {
          totalSize += await entity.length();
        }
      }
      final mb = totalSize / (1024 * 1024);
      return '${mb.toStringAsFixed(1)} MB';
    } catch (e) {
      return '0 MB';
    }
  }

  /// مسح جميع الفصول المخزنة
  static Future<void> clearAllCache() async {
    try {
      final dir = await _getCacheDirectory();
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('Cache clear error: $e');
    }
  }
}
