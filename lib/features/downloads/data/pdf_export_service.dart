import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:share_plus/share_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

import '../models/saved_chapter.dart';
import 'downloads_service.dart';

final pdfExportProvider = Provider<PdfExportService>((ref) {
  return PdfExportService(ref.read(downloadsProvider));
});

class PdfExportService {
  final DownloadsService _downloadsService;

  PdfExportService(this._downloadsService);

  /// الحصول على المجلد العام في الذاكرة الأساسية (Public Storage)
  static Future<Directory> _getPublicExportDir(String mangaTitle) async {
    Directory? baseDir;

    if (Platform.isAndroid) {
      // طلب الصلاحيات
      if (await Permission.manageExternalStorage.isDenied || 
          await Permission.storage.isDenied) {
        await [Permission.manageExternalStorage, Permission.storage].request();
      }

      // محاولة الوصول لجذر الذاكرة (Root of emulated storage)
      baseDir = Directory('/storage/emulated/0/MangaLens/$mangaTitle');
      try {
        if (!await baseDir.exists()) {
          await baseDir.create(recursive: true);
        }
        return baseDir;
      } catch (e) {
        // إذا فشل (بسبب قيود Android 11+ ولم يعطِ المستخدم الصلاحية)
        // نستخدم مجلد التنزيلات العام كملاذ آمن
        baseDir = Directory('/storage/emulated/0/Download/MangaLens/$mangaTitle');
        if (!await baseDir.exists()) {
          await baseDir.create(recursive: true);
        }
        return baseDir;
      }
    } else {
      // للأجهزة الأخرى (مثل iOS) نستخدم مجلد المستندات
      baseDir = await getApplicationDocumentsDirectory();
      final targetDir = Directory('${baseDir.path}/MangaLens/$mangaTitle');
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }
      return targetDir;
    }
  }

  /// ضغط الصورة باستخدام flutter_image_compress (Native & Fast)
  static Future<Uint8List> _compressImageNative(Uint8List imageBytes) async {
    try {
      final compressed = await FlutterImageCompress.compressWithList(
        imageBytes,
        minWidth: 1080,
        minHeight: 1920,
        quality: 75,
        format: CompressFormat.jpeg,
      );
      return compressed;
    } catch (e) {
      // في حال الفشل، نرجع الصورة الأصلية
      return imageBytes;
    }
  }

  /// تصدير فصل كـ PDF — معالج لحل مشكلة OOM والملفات الطويلة
  Future<String> exportAndSharePdf(SavedChapter chapter) async {
    final images = await _downloadsService.getChapterImages(chapter);

    if (images.isEmpty) {
      throw Exception('لا توجد صور محفوظة في هذا الفصل لتصديرها.');
    }

    final pdf = pw.Document();
    final stopwatch = Stopwatch()..start();

    // معالجة الصور وإضافتها للـ PDF
    for (int i = 0; i < images.length; i++) {
      final file = images[i];
      Uint8List imageBytes = await file.readAsBytes();

      // ضغط الصورة دائماً لتجنب OOM باستخدام مكتبة الـ Native
      imageBytes = await _compressImageNative(imageBytes);

      final image = pw.MemoryImage(imageBytes);

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat(
            (image.width ?? 800).toDouble(),
            (image.height ?? 1200).toDouble(),
          ),
          margin: pw.EdgeInsets.zero,
          build: (pw.Context context) {
            return pw.Center(
              child: pw.Image(image, fit: pw.BoxFit.contain),
            );
          },
        ),
      );
      
      // مسح الصورة من الذاكرة لتقليل الضغط
      imageBytes = Uint8List(0);
    }

    // ─── حفظ الـ PDF ───
    final safeMangaTitle = chapter.mangaTitle.replaceAll(RegExp(r'[\\/:*?"<>| ]'), '_');
    final safeChapterTitle = chapter.chapterTitle.replaceAll(RegExp(r'[\\/:*?"<>| ]'), '_');
    
    final exportDir = await _getPublicExportDir(safeMangaTitle);
    final file = File('${exportDir.path}/$safeChapterTitle.pdf');

    final pdfBytes = await pdf.save();
    await file.writeAsBytes(pdfBytes);

    stopwatch.stop();
    final sizeMB = (pdfBytes.length / 1024 / 1024).toStringAsFixed(1);
    debugPrint('📄 PDF done in ${stopwatch.elapsedMilliseconds}ms — $sizeMB MB — ${images.length} pages');

    return file.path;
  }
}
