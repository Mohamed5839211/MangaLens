import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/foundation.dart';
import '../models/reading_progress.dart';

/// خدمة إدارة تقدم القراءة (الفصول المقروءة، موقع التمرير، آخر فصل)
/// Reading progress management service (Hive-backed)
class ReadingProgressService {
  static const String _boxName = 'reading_progress';
  static Box? _box;

  /// تهيئة صندوق Hive – يُستدعى مرة واحدة عند بدء التطبيق
  static Future<void> init() async {
    _box = await Hive.openBox(_boxName);
    debugPrint(
        '📊 ReadingProgress initialized: entries=${_box!.length}');
  }

  // ══════════════════════════════════════════════════
  // ─── حفظ وجلب التقدم ─────────────────────────────
  // ══════════════════════════════════════════════════

  /// حفظ تقدم القراءة بالكامل
  static Future<void> saveProgress(ReadingProgress progress) async {
    await _box?.put(progress.mangaId, progress.toMap());
    debugPrint('📊 Saved reading progress: ${progress.mangaTitle}');
  }

  /// جلب تقدم القراءة لمانغا معينة بالرابط
  static ReadingProgress? getProgress(String mangaUrl) {
    final id = ReadingProgress.generateId(mangaUrl);
    final data = _box?.get(id);
    if (data == null) return null;
    return ReadingProgress.fromMap(Map<String, dynamic>.from(data as Map));
  }

  // ══════════════════════════════════════════════════
  // ─── تتبع الفصول المقروءة ─────────────────────────
  // ══════════════════════════════════════════════════

  /// هل تمت قراءة فصل محدد؟
  static bool isChapterRead(String mangaUrl, String chapterUrl) {
    final progress = getProgress(mangaUrl);
    if (progress == null) return false;
    return progress.readChapterUrls.contains(chapterUrl);
  }

  /// تسجيل فصل كمقروء وتحديث آخر فصل تمت قراءته
  static Future<void> markChapterRead(
    String mangaUrl,
    String chapterUrl, {
    required String mangaTitle,
    required String coverUrl,
    required String sourceUrl,
    required String chapterTitle,
    required int chapterIndex,
  }) async {
    var progress = getProgress(mangaUrl);
    final readUrls =
        List<String>.from(progress?.readChapterUrls ?? []);
    if (!readUrls.contains(chapterUrl)) readUrls.add(chapterUrl);

    progress = (progress ??
            ReadingProgress(
              mangaId: ReadingProgress.generateId(mangaUrl),
              mangaTitle: mangaTitle,
              mangaUrl: mangaUrl,
              coverUrl: coverUrl,
              sourceUrl: sourceUrl,
              lastChapterUrl: chapterUrl,
              lastChapterTitle: chapterTitle,
              lastChapterIndex: chapterIndex,
            ))
        .copyWith(
      lastChapterUrl: chapterUrl,
      lastChapterTitle: chapterTitle,
      lastChapterIndex: chapterIndex,
      readChapterUrls: readUrls,
      lastReadAt: DateTime.now(),
    );

    await saveProgress(progress);
  }

  // ══════════════════════════════════════════════════
  // ─── موقع التمرير ─────────────────────────────────
  // ══════════════════════════════════════════════════

  /// حفظ موقع التمرير للفصل الحالي فقط
  static Future<void> saveScrollPosition(
    String mangaUrl,
    String chapterUrl,
    double position,
  ) async {
    var progress = getProgress(mangaUrl);
    if (progress != null && progress.lastChapterUrl == chapterUrl) {
      progress = progress.copyWith(scrollPosition: position);
      await saveProgress(progress);
    }
  }

  /// جلب موقع التمرير لفصل محدد
  static double getScrollPosition(String mangaUrl, String chapterUrl) {
    final progress = getProgress(mangaUrl);
    if (progress != null && progress.lastChapterUrl == chapterUrl) {
      return progress.scrollPosition;
    }
    return 0.0;
  }

  // ══════════════════════════════════════════════════
  // ─── استعلامات عامة ───────────────────────────────
  // ══════════════════════════════════════════════════

  /// جلب جميع سجلات التقدم مرتبة بالأحدث أولاً
  static List<ReadingProgress> getAllProgress() {
    if (_box == null || _box!.isEmpty) return [];

    final list = _box!.values
        .map((data) =>
            ReadingProgress.fromMap(Map<String, dynamic>.from(data as Map)))
        .toList();

    // ترتيب بالأحدث أولاً
    list.sort((a, b) => b.lastReadAt.compareTo(a.lastReadAt));
    return list;
  }

  /// حذف تقدم القراءة لمانغا معينة
  static Future<void> deleteProgress(String mangaUrl) async {
    final id = ReadingProgress.generateId(mangaUrl);
    await _box?.delete(id);
  }

  /// مسح جميع سجلات التقدم
  static Future<void> clearAll() async {
    await _box?.clear();
  }
}
