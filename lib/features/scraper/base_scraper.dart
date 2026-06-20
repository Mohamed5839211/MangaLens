import 'package:dio/dio.dart';
import 'models/manga_metadata.dart';

abstract class BaseScraper {
  final Dio dio;
  final String baseUrl;

  BaseScraper(this.dio, this.baseUrl);

  /// جلب المانجا الشائعة أو آخر التحديثات
  Future<List<MangaMetadata>> getPopularManga({int page = 1});

  /// البحث عن مانجا
  Future<List<MangaMetadata>> searchManga(String query, {int page = 1});

  /// جلب تفاصيل مانجا وقائمة فصولها
  Future<MangaMetadata> getMangaDetails(String mangaUrl);

  /// جلب روابط صور الفصل
  Future<List<String>> getChapterImages(String chapterUrl);
}
