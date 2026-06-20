import '../services/history_service.dart';

/// نموذج بيانات تقدم القراءة لكل مانغا
/// Reading progress data model for each manga
class ReadingProgress {
  /// معرف فريد مشتق من رابط المانغا
  final String mangaId;

  /// عنوان المانغا
  final String mangaTitle;

  /// رابط صفحة المانغا الرئيسية
  final String mangaUrl;

  /// رابط صورة الغلاف
  final String coverUrl;

  /// الرابط الأساسي للمصدر
  final String sourceUrl;

  /// رابط آخر فصل كان المستخدم يقرأه
  final String lastChapterUrl;

  /// عنوان آخر فصل
  final String lastChapterTitle;

  /// فهرس الفصل في قائمة الفصول
  final int lastChapterIndex;

  /// موقع التمرير (0.0 – 1.0)
  final double scrollPosition;

  /// قائمة روابط الفصول التي تمت قراءتها
  final List<String> readChapterUrls;

  /// تاريخ آخر قراءة
  final DateTime lastReadAt;

  ReadingProgress({
    required this.mangaId,
    required this.mangaTitle,
    required this.mangaUrl,
    required this.coverUrl,
    required this.sourceUrl,
    required this.lastChapterUrl,
    this.lastChapterTitle = '',
    this.lastChapterIndex = 0,
    this.scrollPosition = 0.0,
    this.readChapterUrls = const [],
    DateTime? lastReadAt,
  }) : lastReadAt = lastReadAt ?? DateTime.now();

  // ──────────────────────────────────────────────────
  // ─── التحويل من/إلى Map للتخزين في Hive ──────────
  // ──────────────────────────────────────────────────

  /// إنشاء من Map (Hive)
  factory ReadingProgress.fromMap(Map<String, dynamic> map) {
    return ReadingProgress(
      mangaId: map['mangaId'] as String? ?? '',
      mangaTitle: map['mangaTitle'] as String? ?? '',
      mangaUrl: map['mangaUrl'] as String? ?? '',
      coverUrl: map['coverUrl'] as String? ?? '',
      sourceUrl: map['sourceUrl'] as String? ?? '',
      lastChapterUrl: map['lastChapterUrl'] as String? ?? '',
      lastChapterTitle: map['lastChapterTitle'] as String? ?? '',
      lastChapterIndex: map['lastChapterIndex'] as int? ?? 0,
      scrollPosition: (map['scrollPosition'] as num?)?.toDouble() ?? 0.0,
      readChapterUrls: (map['readChapterUrls'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      lastReadAt: map['lastReadAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['lastReadAt'] as int)
          : DateTime.now(),
    );
  }

  /// تحويل إلى Map
  Map<String, dynamic> toMap() {
    return {
      'mangaId': mangaId,
      'mangaTitle': mangaTitle,
      'mangaUrl': mangaUrl,
      'coverUrl': coverUrl,
      'sourceUrl': sourceUrl,
      'lastChapterUrl': lastChapterUrl,
      'lastChapterTitle': lastChapterTitle,
      'lastChapterIndex': lastChapterIndex,
      'scrollPosition': scrollPosition,
      'readChapterUrls': readChapterUrls,
      'lastReadAt': lastReadAt.millisecondsSinceEpoch,
    };
  }

  // ──────────────────────────────────────────────────
  // ─── نسخة معدلة ──────────────────────────────────
  // ──────────────────────────────────────────────────

  /// إنشاء نسخة معدلة من الكائن مع تغيير الحقول المحددة فقط
  ReadingProgress copyWith({
    String? mangaTitle,
    String? mangaUrl,
    String? coverUrl,
    String? sourceUrl,
    String? lastChapterUrl,
    String? lastChapterTitle,
    int? lastChapterIndex,
    double? scrollPosition,
    List<String>? readChapterUrls,
    DateTime? lastReadAt,
  }) {
    return ReadingProgress(
      mangaId: mangaId,
      mangaTitle: mangaTitle ?? this.mangaTitle,
      mangaUrl: mangaUrl ?? this.mangaUrl,
      coverUrl: coverUrl ?? this.coverUrl,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      lastChapterUrl: lastChapterUrl ?? this.lastChapterUrl,
      lastChapterTitle: lastChapterTitle ?? this.lastChapterTitle,
      lastChapterIndex: lastChapterIndex ?? this.lastChapterIndex,
      scrollPosition: scrollPosition ?? this.scrollPosition,
      readChapterUrls: readChapterUrls ?? this.readChapterUrls,
      lastReadAt: lastReadAt ?? this.lastReadAt,
    );
  }

  // ──────────────────────────────────────────────────
  // ─── توليد المعرف ────────────────────────────────
  // ──────────────────────────────────────────────────

  /// توليد معرف ثابت من رابط المانغا عبر تطبيع الرابط
  /// يستخدم نفس خوارزمية HistoryService.generateId لتوحيد المعرفات
  static String generateId(String mangaUrl) {
    return HistoryService.generateId(mangaUrl);
  }
}
