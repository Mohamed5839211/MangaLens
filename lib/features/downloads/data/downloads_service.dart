import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:dio/dio.dart';
import '../models/saved_chapter.dart';

final downloadsProvider = Provider<DownloadsService>((ref) {
  return DownloadsService();
});

class DownloadsService {
  static const String _boxName = 'saved_chapters_box';
  static const String _orderBoxName = 'manga_chapters_order_box';
  static late Box<String> _box;
  static late Box<List<dynamic>> _orderBox;

  static Future<void> init() async {
    _box = await Hive.openBox<String>(_boxName);
    _orderBox = await Hive.openBox<List<dynamic>>(_orderBoxName);
  }

  List<SavedChapter> getSavedChapters() {
    final chapters = <SavedChapter>[];
    for (var key in _box.keys) {
      final jsonStr = _box.get(key);
      if (jsonStr != null) {
        chapters.add(SavedChapter.fromJson(jsonStr));
      }
    }
    // Sort by savedAt descending
    chapters.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return chapters;
  }

  Future<void> saveChapter({
    required String mangaTitle,
    required String chapterTitle,
    required List<Uint8List> images,
    String? coverUrl,
  }) async {
    final uuid = const Uuid().v4();
    final appDir = await getApplicationDocumentsDirectory();
    final safeMangaTitle = mangaTitle.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final safeChapterTitle = chapterTitle.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    
    final chapterFolder = Directory('${appDir.path}/downloads/$safeMangaTitle/$safeChapterTitle\_$uuid');
    if (!await chapterFolder.exists()) {
      await chapterFolder.create(recursive: true);
    }

    // Save images
    for (int i = 0; i < images.length; i++) {
      final file = File('${chapterFolder.path}/image_$i.png');
      await file.writeAsBytes(images[i]);
    }

    // Save cover if coverUrl is provided (local path or URL)
    if (coverUrl != null && coverUrl.isNotEmpty && !coverUrl.startsWith('data:')) {
      try {
        final coverFile = File('${chapterFolder.path}/cover.png');
        
        // إذا كان مسار ملف محلي (محفوظ من base64 في المتصفح)
        if (!coverUrl.startsWith('http')) {
          final localFile = File(coverUrl);
          if (await localFile.exists()) {
            await localFile.copy(coverFile.path);
          }
        } else {
          // Fallback: تنزيل من الإنترنت
          final uri = Uri.tryParse(coverUrl);
          final ref = uri != null ? '${uri.scheme}://${uri.host}/' : '';
          final response = await Dio().get<List<int>>(
            coverUrl,
            options: Options(
              responseType: ResponseType.bytes,
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 10),
              headers: {
                'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
                'Referer': ref,
              },
            ),
          );
          if (response.data != null) {
            await coverFile.writeAsBytes(response.data!);
          }
        }
      } catch (e) {
        // Ignored, fallback to image_0.png will be used if cover.png doesn't exist
      }
    }

    final chapter = SavedChapter(
      id: uuid,
      mangaTitle: mangaTitle,
      chapterTitle: chapterTitle,
      imageCount: images.length,
      savedAt: DateTime.now(),
      folderPath: chapterFolder.path,
    );

    await _box.put(uuid, chapter.toJson());
  }

  /// تعديل اسم فصل محفوظ
  Future<void> renameChapter(SavedChapter chapter, String newTitle) async {
    final updated = SavedChapter(
      id: chapter.id,
      mangaTitle: chapter.mangaTitle,
      chapterTitle: newTitle,
      imageCount: chapter.imageCount,
      savedAt: chapter.savedAt,
      folderPath: chapter.folderPath,
    );
    await _box.put(chapter.id, updated.toJson());
  }

  Future<List<File>> getChapterImages(SavedChapter chapter) async {
    final folder = Directory(chapter.folderPath);
    if (!await folder.exists()) return [];

    // استثناء ملف الغلاف cover.png لتجنب أخطاء الفرز ومشاكل التصدير كـ PDF
    final files = folder.listSync()
        .whereType<File>()
        .where((file) => !file.path.endsWith('cover.png'))
        .toList();
    // Sort by image index
    files.sort((a, b) {
      final aIndex = int.parse(a.path.split('_').last.split('.').first);
      final bIndex = int.parse(b.path.split('_').last.split('.').first);
      return aIndex.compareTo(bIndex);
    });
    return files;
  }

  Future<void> deleteChapter(SavedChapter chapter) async {
    final folder = Directory(chapter.folderPath);
    if (await folder.exists()) {
      await folder.delete(recursive: true);
    }
    await _box.delete(chapter.id);

    // تحديث قائمة الترتيب المخصصة وحذف معرّف الفصل المحذوف منها
    final cleanTitle = chapter.mangaTitle.trim().toLowerCase();
    final currentOrder = getChapterOrder(cleanTitle);
    if (currentOrder != null && currentOrder.contains(chapter.id)) {
      currentOrder.remove(chapter.id);
      await saveChapterOrder(chapter.mangaTitle, currentOrder);
    }
  }

  Future<void> saveChapterOrder(String mangaTitle, List<String> orderedChapterIds) async {
    final cleanMangaTitle = mangaTitle.trim().toLowerCase();
    await _orderBox.put(cleanMangaTitle, orderedChapterIds);
  }

  List<String>? getChapterOrder(String mangaTitle) {
    final cleanMangaTitle = mangaTitle.trim().toLowerCase();
    final list = _orderBox.get(cleanMangaTitle);
    return list?.cast<String>();
  }

  /// إعادة تسمية قصة مصورة ونقل مجلداتها ودمج ترتيب فصولها
  Future<void> renameManga(String oldTitle, String newTitle) async {
    final cleanOld = oldTitle.trim().toLowerCase();
    final cleanNew = newTitle.trim().toLowerCase();
    if (cleanOld == cleanNew) return;

    final appDir = await getApplicationDocumentsDirectory();
    final safeNewMangaTitle = newTitle.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final newMangaDir = Directory('${appDir.path}/downloads/$safeNewMangaTitle');
    if (!await newMangaDir.exists()) {
      await newMangaDir.create(recursive: true);
    }

    final allChapters = getSavedChapters();
    final chaptersToUpdate = allChapters.where(
      (c) => c.mangaTitle.trim().toLowerCase() == cleanOld
    ).toList();

    for (final chapter in chaptersToUpdate) {
      final oldFolder = Directory(chapter.folderPath);
      final folderName = oldFolder.path.split(Platform.pathSeparator).last;
      final newFolderPath = '${newMangaDir.path}/$folderName';
      
      // نقل المجلد الفعلي على القرص إن وجد
      if (await oldFolder.exists()) {
        try {
          await oldFolder.rename(newFolderPath);
        } catch (e) {
          // في حال فشل الـ rename المباشر، نقوم بالنسخ والحذف يدوياً
          try {
            final newDir = Directory(newFolderPath);
            await newDir.create(recursive: true);
            await for (final file in oldFolder.list(recursive: true)) {
              if (file is File) {
                final relativePath = file.path.substring(oldFolder.path.length);
                final destFile = File('${newDir.path}$relativePath');
                await destFile.parent.create(recursive: true);
                await file.copy(destFile.path);
              }
            }
            await oldFolder.delete(recursive: true);
          } catch (innerErr) {
            // تجاهل الخطأ، سنحافظ على المسار القديم لو تعذر النقل بالكامل
          }
        }
      }

      // تحديث بيانات الفصل في النموذج
      final updatedChapter = SavedChapter(
        id: chapter.id,
        mangaTitle: newTitle,
        chapterTitle: chapter.chapterTitle,
        imageCount: chapter.imageCount,
        savedAt: chapter.savedAt,
        folderPath: newFolderPath,
      );

      // حفظ التحديث في Hive
      await _box.put(chapter.id, updatedChapter.toJson());
    }

    // دمج ترتيب الفصول
    final oldOrder = getChapterOrder(oldTitle);
    if (oldOrder != null && oldOrder.isNotEmpty) {
      final newOrder = getChapterOrder(newTitle) ?? [];
      // منع التكرار
      final mergedOrder = <String>[...newOrder];
      for (final id in oldOrder) {
        if (!mergedOrder.contains(id)) {
          mergedOrder.add(id);
        }
      }
      await saveChapterOrder(newTitle, mergedOrder);
      await _orderBox.delete(cleanOld);
    }

    // تنظيف المجلد القديم الفارغ
    final safeOldMangaTitle = oldTitle.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final oldMangaDir = Directory('${appDir.path}/downloads/$safeOldMangaTitle');
    try {
      if (await oldMangaDir.exists() && oldMangaDir.listSync().isEmpty) {
        await oldMangaDir.delete();
      }
    } catch (_) {}
  }

  /// تحديث توقيت حفظ الفصل لتحديث ترتيبه في الفصول المحفوظة
  Future<void> updateChapterSavedAt(String chapterId, DateTime newSavedAt) async {
    final jsonStr = _box.get(chapterId);
    if (jsonStr != null) {
      final chapter = SavedChapter.fromJson(jsonStr);
      final updated = SavedChapter(
        id: chapter.id,
        mangaTitle: chapter.mangaTitle,
        chapterTitle: chapter.chapterTitle,
        imageCount: chapter.imageCount,
        savedAt: newSavedAt,
        folderPath: chapter.folderPath,
      );
      await _box.put(chapterId, updated.toJson());
    }
  }
}
