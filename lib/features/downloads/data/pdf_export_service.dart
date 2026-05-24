import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:image/image.dart' as img;
import '../models/saved_chapter.dart';
import 'downloads_service.dart';

final pdfExportProvider = Provider<PdfExportService>((ref) {
  return PdfExportService(ref.read(downloadsProvider));
});

class PdfExportService {
  final DownloadsService _downloadsService;

  PdfExportService(this._downloadsService);

  /// حد حجم الملف (2 ميجا) — فقط الصور الأكبر من هذا الحد يتم ضغطها
  static const int _compressThreshold = 2 * 1024 * 1024; // 2 MB

  /// ضغط صورة كبيرة في Isolate منفصل (يُستدعى فقط للصور الضخمة)
  static Uint8List _compressLargeImage(Uint8List imageBytes) {
    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) return imageBytes;

    final maxWidth = 1400;
    img.Image resized;
    if (decoded.width > maxWidth) {
      resized = img.copyResize(decoded, width: maxWidth);
    } else {
      resized = decoded;
    }

    return Uint8List.fromList(img.encodeJpg(resized, quality: 80));
  }

  /// الحصول على مجلد التصدير الدائم
  static Future<Directory> _getExportDir() async {
    final externalDir = await getExternalStorageDirectory();
    if (externalDir != null) {
      final pdfDir = Directory('${externalDir.path}/PDF');
      if (!await pdfDir.exists()) {
        await pdfDir.create(recursive: true);
      }
      return pdfDir;
    }

    final docsDir = await getApplicationDocumentsDirectory();
    final pdfDir = Directory('${docsDir.path}/PDF');
    if (!await pdfDir.exists()) {
      await pdfDir.create(recursive: true);
    }
    return pdfDir;
  }

  /// تصدير فصل كـ PDF — سريع (بدون ضغط غير ضروري)
  Future<String> exportAndSharePdf(SavedChapter chapter) async {
    final images = await _downloadsService.getChapterImages(chapter);

    if (images.isEmpty) {
      throw Exception('لا توجد صور محفوظة في هذا الفصل لتصديرها.');
    }

    final pdf = pw.Document();
    final stopwatch = Stopwatch()..start();

    for (int i = 0; i < images.length; i++) {
      final file = images[i];
      Uint8List imageBytes = await file.readAsBytes();

      // ضغط فقط الصور الضخمة (> 2 ميجا) لتوفير الذاكرة
      if (imageBytes.length > _compressThreshold) {
        debugPrint('📄 PDF: Compressing large page ${i + 1} (${(imageBytes.length / 1024 / 1024).toStringAsFixed(1)} MB)');
        imageBytes = await compute(_compressLargeImage, imageBytes);
      }

      final image = pw.MemoryImage(imageBytes);

      pdf.addPage(
        pw.Page(
          margin: pw.EdgeInsets.zero,
          build: (pw.Context context) {
            return pw.Center(
              child: pw.Image(image, fit: pw.BoxFit.contain),
            );
          },
        ),
      );
    }

    // ─── حفظ الـ PDF ───
    final exportDir = await _getExportDir();
    final safeTitle = '${chapter.mangaTitle}_${chapter.chapterTitle}'
        .replaceAll(RegExp(r'[\\/:*?"<>| ]'), '_');
    final file = File('${exportDir.path}/$safeTitle.pdf');

    final pdfBytes = await pdf.save();
    await file.writeAsBytes(pdfBytes);

    stopwatch.stop();
    final sizeMB = (pdfBytes.length / 1024 / 1024).toStringAsFixed(1);
    debugPrint('📄 PDF done in ${stopwatch.elapsedMilliseconds}ms — $sizeMB MB — ${images.length} pages');

    // ─── مشاركة ───
    final xFile = XFile(file.path, mimeType: 'application/pdf');
    await SharePlus.instance.share(ShareParams(
      files: [xFile],
      text: '${chapter.mangaTitle} - ${chapter.chapterTitle}',
    ));

    return file.path;
  }
}
