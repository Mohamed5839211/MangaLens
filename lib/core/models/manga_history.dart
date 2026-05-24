/// نموذج بيانات سجل قراءة المانغا
/// Manga reading history data model
class MangaHistory {
  final String id;           // معرف فريد (hash من URL الأساسي)
  final String title;        // اسم المانغا
  final String imageUrl;     // رابط صورة الغلاف
  final String siteUrl;      // رابط الموقع الأصلي (صفحة المانغا)
  final String lastChapterUrl; // رابط آخر فصل تمت قراءته
  final String lastChapter;  // اسم/رقم آخر فصل
  final String remoteImageUrl; // رابط الصورة البعيد الأصلي
  final DateTime lastRead;   // تاريخ آخر قراءة

  MangaHistory({
    required this.id,
    required this.title,
    required this.imageUrl,
    required this.siteUrl,
    required this.lastChapterUrl,
    this.lastChapter = '',
    this.remoteImageUrl = '',
    DateTime? lastRead,
  }) : lastRead = lastRead ?? DateTime.now();

  /// إنشاء من Map (للتخزين في Hive)
  factory MangaHistory.fromMap(Map<dynamic, dynamic> map) {
    return MangaHistory(
      id: map['id'] as String? ?? '',
      title: map['title'] as String? ?? '',
      imageUrl: map['imageUrl'] as String? ?? '',
      siteUrl: map['siteUrl'] as String? ?? '',
      lastChapterUrl: map['lastChapterUrl'] as String? ?? '',
      lastChapter: map['lastChapter'] as String? ?? '',
      remoteImageUrl: map['remoteImageUrl'] as String? ?? '',
      lastRead: map['lastRead'] != null 
          ? DateTime.fromMillisecondsSinceEpoch(map['lastRead'] as int)
          : DateTime.now(),
    );
  }

  /// تحويل إلى Map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'imageUrl': imageUrl,
      'siteUrl': siteUrl,
      'lastChapterUrl': lastChapterUrl,
      'lastChapter': lastChapter,
      'remoteImageUrl': remoteImageUrl,
      'lastRead': lastRead.millisecondsSinceEpoch,
    };
  }

  /// نسخة معدلة
  MangaHistory copyWith({
    String? title,
    String? imageUrl,
    String? lastChapterUrl,
    String? lastChapter,
    String? remoteImageUrl,
    DateTime? lastRead,
  }) {
    return MangaHistory(
      id: id,
      title: title ?? this.title,
      imageUrl: imageUrl ?? this.imageUrl,
      siteUrl: siteUrl,
      lastChapterUrl: lastChapterUrl ?? this.lastChapterUrl,
      lastChapter: lastChapter ?? this.lastChapter,
      remoteImageUrl: remoteImageUrl ?? this.remoteImageUrl,
      lastRead: lastRead ?? this.lastRead,
    );
  }
}
