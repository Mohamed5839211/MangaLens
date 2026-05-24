import 'dart:typed_data';

/// نموذج بيانات الفصل المستخرج
/// Holds extracted chapter images and metadata
class ChapterData {
  final String title;
  final String sourceUrl;
  final List<ChapterImage> images;
  final DateTime extractedAt;

  const ChapterData({
    required this.title,
    required this.sourceUrl,
    required this.images,
    required this.extractedAt,
  });

  ChapterData copyWith({
    String? title,
    String? sourceUrl,
    List<ChapterImage>? images,
    DateTime? extractedAt,
  }) {
    return ChapterData(
      title: title ?? this.title,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      images: images ?? this.images,
      extractedAt: extractedAt ?? this.extractedAt,
    );
  }
}

/// صورة واحدة من الفصل
/// Single chapter image with its translation state
class ChapterImage {
  final String url;
  final int index;
  final Uint8List? originalBytes;
  final Uint8List? translatedBytes;
  final ImageTranslationStatus status;

  const ChapterImage({
    required this.url,
    required this.index,
    this.originalBytes,
    this.translatedBytes,
    this.status = ImageTranslationStatus.pending,
  });

  ChapterImage copyWith({
    String? url,
    int? index,
    Uint8List? originalBytes,
    Uint8List? translatedBytes,
    ImageTranslationStatus? status,
    bool clearOriginalBytes = false,
  }) {
    return ChapterImage(
      url: url ?? this.url,
      index: index ?? this.index,
      originalBytes: clearOriginalBytes ? null : (originalBytes ?? this.originalBytes),
      translatedBytes: translatedBytes ?? this.translatedBytes,
      status: status ?? this.status,
    );
  }
}

/// حالة ترجمة الصورة
enum ImageTranslationStatus {
  pending,      // لم تُترجم بعد
  downloading,  // جاري التحميل
  processing,   // جاري الترجمة (OCR + AI + Inpaint)
  completed,    // مكتملة
  noText,       // لا يوجد نص (لا تحتاج ترجمة)
  error,        // حدث خطأ
}
