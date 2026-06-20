import 'package:dio/dio.dart';
import 'base_scraper.dart';
import 'js_extension_scraper.dart';
import 'extensions/evascans_ext.dart';

enum SiteTheme { madara, mangastream, unknown }

class ThemeDetector {
  final Dio dio;

  ThemeDetector(this.dio);

  Future<BaseScraper?> detectAndGetScraper(String url) async {
    try {
      final baseUrl = _getBaseUrl(url);
      // جميع المواقع تستخدم JsExtensionScraper الموحد
      // الذي يدعم Madara وMangaStream وأي قالب آخر
      return JsExtensionScraper(dio, baseUrl, scriptFile: 'universal_madara.js');
    } catch (e) {
      return JsExtensionScraper(dio, _getBaseUrl(url), scriptFile: 'universal_madara.js');
    }
  }

  String _getBaseUrl(String fullUrl) {
    final uri = Uri.parse(fullUrl);
    return '${uri.scheme}://${uri.host}';
  }
}
