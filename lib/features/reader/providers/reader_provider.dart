import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../models/chapter_data.dart';
import '../data/chapter_cache_service.dart';
import '../data/image_scraper_service.dart';
import '../../ocr/providers/ocr_provider.dart';
import '../../translation/providers/translation_provider.dart';
import '../../inpainting/providers/inpainting_provider.dart';
import '../../rendering/providers/rendering_provider.dart';

/// حالة القارئ
enum ReaderStatus {
  idle,           // في انتظار
  extracting,     // جاري استخراج الصور من الصفحة
  downloading,    // جاري تحميل الصور
  ready,          // الصور جاهزة للمعاينة
  translating,    // جاري الترجمة
  completed,      // مكتملة
  error,          // خطأ
}

/// حالة القارئ الكاملة
class ReaderState {
  final ReaderStatus status;
  final ChapterData? chapter;
  final int currentTranslatingIndex;
  final int totalImages;
  final String? errorMessage;
  final String sourceLang;
  final String targetLang;

  const ReaderState({
    this.status = ReaderStatus.idle,
    this.chapter,
    this.currentTranslatingIndex = 0,
    this.totalImages = 0,
    this.errorMessage,
    this.sourceLang = 'auto',
    this.targetLang = 'ar',
  });

  ReaderState copyWith({
    ReaderStatus? status,
    ChapterData? chapter,
    int? currentTranslatingIndex,
    int? totalImages,
    String? errorMessage,
    String? sourceLang,
    String? targetLang,
  }) {
    return ReaderState(
      status: status ?? this.status,
      chapter: chapter ?? this.chapter,
      currentTranslatingIndex: currentTranslatingIndex ?? this.currentTranslatingIndex,
      totalImages: totalImages ?? this.totalImages,
      errorMessage: errorMessage ?? this.errorMessage,
      sourceLang: sourceLang ?? this.sourceLang,
      targetLang: targetLang ?? this.targetLang,
    );
  }

  double get progress {
    if (totalImages == 0) return 0;
    return currentTranslatingIndex / totalImages;
  }
}

/// مزود حالة القارئ
class ReaderNotifier extends Notifier<ReaderState> {
  final Dio _dio = Dio();

  @override
  ReaderState build() => const ReaderState();

  /// إعادة تعيين
  void reset() {
    // Keep language settings, reset other state
    state = ReaderState(
      sourceLang: state.sourceLang,
      targetLang: state.targetLang,
    );
  }

  void setSourceLang(String lang) {
    state = state.copyWith(sourceLang: lang);
  }

  void setTargetLang(String lang) {
    state = state.copyWith(targetLang: lang);
  }

  /// الكشف التلقائي عن لغة الفصل من أول صورة متاحة
  Future<void> detectChapterLanguage() async {
    if (state.chapter == null) return;
    
    // تجميع حتى 3 صور صالحة مع استبعاد الإعلانات وصفحات الغلاف المحتملة
    final testImages = <Uint8List>[];
    for (final img in state.chapter!.images) {
      if (img.originalBytes != null && img.originalBytes!.length > 500) {
        final url = img.url.toLowerCase();
        // استبعاد روابط الإعلانات أو البنرات المعروفة
        if (url.contains('ad') || 
            url.contains('banner') || 
            url.contains('extban') || 
            url.contains('promo') ||
            url.contains('credit')) {
          continue;
        }
        testImages.add(img.originalBytes!);
        if (testImages.length >= 3) break;
      }
    }

    // إذا لم نجد أي صور بعد التصفية، نرجع للصور المتاحة كحل احتياطي
    if (testImages.isEmpty) {
      for (final img in state.chapter!.images) {
        if (img.originalBytes != null && img.originalBytes!.length > 500) {
          testImages.add(img.originalBytes!);
          if (testImages.length >= 3) break;
        }
      }
    }

    if (testImages.isEmpty) return;

    try {
      final detectedLang = await ref.read(ocrServiceProvider).detectChapterLanguage(testImages);
      debugPrint('🌐 Detected chapter language: $detectedLang');
      
      // تحديث القائمة المنسدلة تلقائياً فقط إذا كانت على Auto
      if (state.sourceLang == 'auto') {
        state = state.copyWith(sourceLang: detectedLang);
      }
    } catch (e) {
      debugPrint('⚠️ Language detection failed: $e');
    }
  }

  /// إنشاء فصل من الروابط المستخرجة
  /// [webViewController] - يستخدم لتحميل الصور مباشرة من المتصفح (يتجاوز Hotlink Protection)
  Future<void> loadChapter({
    required String title,
    required String sourceUrl,
    required List<String> imageUrls,
    InAppWebViewController? webViewController,
  }) async {
    if (imageUrls.isEmpty) {
      state = state.copyWith(
        status: ReaderStatus.error,
        errorMessage: 'لم يتم العثور على صور في هذه الصفحة',
      );
      return;
    }

    state = state.copyWith(
      status: ReaderStatus.downloading,
      totalImages: imageUrls.length,
      currentTranslatingIndex: 0,
    );

    // إنشاء قائمة الصور الأولية
    final images = <ChapterImage>[];
    for (int i = 0; i < imageUrls.length; i++) {
      images.add(ChapterImage(url: imageUrls[i], index: i));
    }

    final chapter = ChapterData(
      title: title,
      sourceUrl: sourceUrl,
      images: images,
      extractedAt: DateTime.now(),
    );

    state = state.copyWith(chapter: chapter);

    // تحميل الصور
    await _downloadAllImages(chapter, webViewController);
  }

  /// تحميل جميع الصور - يستخدم كوكيز المتصفح مع Dio للتحميل المباشر
  Future<void> _downloadAllImages(ChapterData chapter, InAppWebViewController? webController) async {
    final updatedImages = List<ChapterImage>.from(chapter.images);
    
    // ═══ استخراج كوكيز المتصفح لتمريرها مع طلبات التحميل ═══
    String cookieString = '';
    if (webController != null) {
      try {
        final sourceUri = WebUri(chapter.sourceUrl);
        final cookies = await CookieManager.instance().getCookies(url: sourceUri);
        cookieString = cookies.map((c) => '${c.name}=${c.value}').join('; ');
        debugPrint('🍪 Got ${cookies.length} cookies from browser');
      } catch (e) {
        debugPrint('⚠️ Could not get cookies: $e');
      }
    }

    for (int i = 0; i < updatedImages.length; i++) {
      try {
        state = state.copyWith(currentTranslatingIndex: i + 1);

        // فحص التخزين المؤقت أولاً
        final cached = await ChapterCacheService.getCachedImage(
            chapter.sourceUrl, i);
        if (cached != null) {
          updatedImages[i] = updatedImages[i].copyWith(
            originalBytes: cached,
            status: ImageTranslationStatus.pending,
          );
          state = state.copyWith(
            chapter: chapter.copyWith(images: List.from(updatedImages)),
          );
          continue;
        }

        updatedImages[i] = updatedImages[i].copyWith(
          status: ImageTranslationStatus.downloading,
        );
        state = state.copyWith(
          chapter: chapter.copyWith(images: List.from(updatedImages)),
        );

        Uint8List? bytes;
        final imageUrl = updatedImages[i].url;

        // ═══ الطريقة الأساسية: Dio مع كوكيز المتصفح ═══
        debugPrint('📥 Downloading image ${i + 1}/${updatedImages.length}: $imageUrl');
        try {
          final headers = <String, String>{
            'Referer': chapter.sourceUrl,
            'Origin': Uri.parse(chapter.sourceUrl).origin,
            'User-Agent': 'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
            'Accept': 'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
            'Accept-Language': 'en-US,en;q=0.9',
            'Sec-Fetch-Dest': 'image',
            'Sec-Fetch-Mode': 'no-cors',
            'Sec-Fetch-Site': 'cross-site',
          };
          if (cookieString.isNotEmpty) {
            headers['Cookie'] = cookieString;
          }

          final response = await _dio.get<List<int>>(
            imageUrl,
            options: Options(
              responseType: ResponseType.bytes,
              followRedirects: true,
              validateStatus: (status) => status != null && status < 400,
              headers: headers,
            ),
          );
          if (response.data != null && response.data!.length > 500) {
            bytes = Uint8List.fromList(response.data!);
          }
        } catch (dioErr) {
          debugPrint('⚠️ Dio with cookies failed for image ${i + 1}: $dioErr');
        }

        // ═══ الطريقة البديلة: تحميل من WebView مباشرة (للصور المحمية بشدة) ═══
        if (bytes == null && webController != null) {
          debugPrint('🔄 Trying WebView fetch for image ${i + 1}...');
          bytes = await ImageScraperService.downloadImageViaWebView(
            webController, imageUrl,
          );
        }

        if (bytes != null && bytes.length > 500) {
          updatedImages[i] = updatedImages[i].copyWith(
            originalBytes: bytes,
            status: ImageTranslationStatus.pending,
          );
          await ChapterCacheService.cacheImage(chapter.sourceUrl, i, bytes);
          debugPrint('✅ Image ${i + 1} downloaded (${(bytes.length / 1024).toStringAsFixed(1)} KB)');
        } else {
          debugPrint('❌ Image ${i + 1} failed (${bytes?.length ?? 0} bytes)');
          updatedImages[i] = updatedImages[i].copyWith(
            status: ImageTranslationStatus.error,
          );
        }

      } catch (e) {
        debugPrint('❌ Failed to download image $i: $e');
        updatedImages[i] = updatedImages[i].copyWith(
          status: ImageTranslationStatus.error,
        );
      }

      // تحديث الحالة بعد كل صورة
      state = state.copyWith(
        chapter: chapter.copyWith(images: List.from(updatedImages)),
      );
    }

    state = state.copyWith(status: ReaderStatus.ready);
  }

  /// حذف صورة من الفصل (إعلان تسرب مثلاً)
  void removeImage(int index) {
    if (state.chapter == null) return;
    final images = List<ChapterImage>.from(state.chapter!.images);
    images.removeAt(index);
    // إعادة ترقيم الصور
    final reindexed = <ChapterImage>[];
    for (int i = 0; i < images.length; i++) {
      reindexed.add(images[i].copyWith(index: i));
    }
    state = state.copyWith(
      chapter: state.chapter!.copyWith(images: reindexed),
      totalImages: reindexed.length,
    );
  }

  /// ترجمة جميع الصور (Batch Translation)
  Future<void> translateAll() async {
    if (state.chapter == null) return;

    state = state.copyWith(
      status: ReaderStatus.translating,
      currentTranslatingIndex: 0,
    );

    final images = List<ChapterImage>.from(state.chapter!.images);

    for (int i = 0; i < images.length; i++) {
      // تخطي الصور التي بها خطأ أو بدون بيانات
      if (images[i].originalBytes == null ||
          images[i].status == ImageTranslationStatus.error) {
        continue;
      }

      // فحص التخزين المؤقت للترجمة
      final cachedTr = await ChapterCacheService.getCachedTranslatedImage(
          state.chapter!.sourceUrl, i);
      if (cachedTr != null) {
        images[i] = images[i].copyWith(
          translatedBytes: cachedTr,
          status: ImageTranslationStatus.completed,
        );
        state = state.copyWith(
          chapter: state.chapter!.copyWith(images: List.from(images)),
          currentTranslatingIndex: i + 1,
        );
        continue;
      }

      try {
        images[i] = images[i].copyWith(status: ImageTranslationStatus.processing);
        state = state.copyWith(
          chapter: state.chapter!.copyWith(images: List.from(images)),
          currentTranslatingIndex: i,
        );

        final original = images[i].originalBytes!;

        // 1. OCR
        final ocrResults = await ref.read(ocrServiceProvider).recognizeText(
          original,
          sourceLangCode: state.sourceLang,
        );

        if (ocrResults.isEmpty) {
          images[i] = images[i].copyWith(
            translatedBytes: original,
            status: ImageTranslationStatus.noText,
          );
          state = state.copyWith(
            chapter: state.chapter!.copyWith(images: List.from(images)),
          );
          continue;
        }

        // 2. ترجمة ثم تنظيف (تتابعي لتحديد المؤثرات الصوتية)
        final translations = await ref.read(translationProvider).translateBlocks(
          ocrResults,
          targetLangCode: state.targetLang,
        );
        final cleanedImage = await ref.read(inpaintingServiceProvider).cleanBubbles(
          original,
          ocrResults,
          translations,
        );

        // 3. رسم النص العربي
        final finalImage = await ref.read(textRendererProvider).render(
          cleanedImage,
          translations,
          ocrResults,
        );

        images[i] = images[i].copyWith(
          translatedBytes: finalImage,
          status: ImageTranslationStatus.completed,
        );

        // حفظ الترجمة في التخزين المؤقت
        await ChapterCacheService.cacheTranslatedImage(
            state.chapter!.sourceUrl, i, finalImage);

      } catch (e) {
        debugPrint('❌ Translation failed for image $i: $e');
        images[i] = images[i].copyWith(
          translatedBytes: images[i].originalBytes,
          status: ImageTranslationStatus.error,
        );
      }

      // تحديث الحالة بعد كل صورة
      state = state.copyWith(
        chapter: state.chapter!.copyWith(images: List.from(images)),
        currentTranslatingIndex: i + 1,
      );
    }

    state = state.copyWith(status: ReaderStatus.completed);
  }
}

/// مزود القارئ الرئيسي
final readerProvider = NotifierProvider<ReaderNotifier, ReaderState>(() {
  return ReaderNotifier();
});
