import 'dart:async';
import 'dart:convert';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'base_scraper.dart';
import 'models/manga_metadata.dart';
import 'package:dio/dio.dart';
import '../../core/network/network_module.dart';
import '../../core/services/repository_service.dart';
import '../../features/bypass/cloudflare_bypass_service.dart';
import 'package:synchronized/synchronized.dart';

class JsExtensionScraper extends BaseScraper {
  final String scriptFile;
  final String popularPath;
  final String searchPath;

  JsExtensionScraper(
    super.dio,
    super.baseUrl, {
    required this.scriptFile,
    this.popularPath = '',
    this.searchPath = '',
  });

  String? _workingPopularPath;
  bool _forceLiveExecution = false;
  static final Lock _liveExecutionLock = Lock();

  /// تشغيل JS في HeadlessWebView مع دعم كامل للـ async/await
  /// يتم تحميل الصفحة الحقيقية من السيرفر (وليس loadData) لضمان عمل fetch()
  Future<dynamic> _runJS(String targetUrl, String functionCall, {int waitSec = 20}) async {
    if (_forceLiveExecution) {
      return await _runJSLive(targetUrl, functionCall, waitSec: 35);
    }
    
    final completer = Completer<dynamic>();
    bool disposed = false;

    // 1. أولاً: جلب HTML عبر Dio (لتشغيل CloudflareInterceptor إذا لزم)
    String htmlData;
    try {
      final response = await dio.get(targetUrl);
      htmlData = response.data.toString();
      
      // Auto-Healing: Check for domain redirect
      final targetUri = Uri.parse(baseUrl);
      if (response.realUri.host.isNotEmpty && response.realUri.host != targetUri.host) {
        String newBaseUrl = '${response.realUri.scheme}://${response.realUri.host}';
        if (response.realUri.hasPort && response.realUri.port != 80 && response.realUri.port != 443) {
          newBaseUrl += ':${response.realUri.port}';
        }
        // Update globally
        try {
          // Import might be needed, assuming repository_service is accessible
          await RepositoryService.updateSourceBaseUrl(baseUrl, newBaseUrl);
        } catch (_) {}
      }
    } catch (e) {
      if (e is DioException) {
        final statusCode = e.response?.statusCode;
        if (statusCode == 403 || statusCode == 503) {
          debugPrint('🔄 Dio strictly blocked by Cloudflare ($statusCode). Falling back to WebView execution...');
          return await _runJSLive(targetUrl, functionCall, waitSec: waitSec);
        } else if (statusCode == 404) {
          debugPrint('⚠️ Target URL not found (404): $targetUrl');
        } else {
          debugPrint('⚠️ Dio network error: $statusCode for $targetUrl');
        }
      } else {
        debugPrint('⚠️ Fetch error in _runJS: ${e.toString().split('\n').first}');
      }
      return null;
    }

    // 2. تحميل HTML في HeadlessInAppWebView
    final wv = HeadlessInAppWebView(
      initialData: InAppWebViewInitialData(
        data: htmlData,
        baseUrl: WebUri(targetUrl),
        historyUrl: WebUri(targetUrl),
      ),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        contentBlockers: [],
        useShouldInterceptRequest: false,
      ),
      onLoadStop: (ctrl, url) async {
        if (disposed) return;
        
        try {
          // حقن سكريبت الإضافة
          String actualScript = '';
          try {
            actualScript = await rootBundle.loadString('assets/extensions/$scriptFile');
          } catch (e) {
            debugPrint('⚠️ Error loading scriptFile $scriptFile: $e');
            actualScript = await rootBundle.loadString('assets/extensions/universal_madara.js'); // fallback
          }
          await ctrl.evaluateJavascript(source: actualScript);
          
          final result = await ctrl.callAsyncJavaScript(
            functionBody: '''
              try {
                var result = await $functionCall
                return JSON.stringify(result);
              } catch(e) {
                return JSON.stringify({error: e.message});
              }
            ''',
          );
          
          final value = result?.value;
          debugPrint('✅ JS Executed for $targetUrl. Result length: ${value?.toString().length ?? 0}');
          if (!completer.isCompleted) {
            completer.complete(value);
          }
        } catch (e) {
          debugPrint('⚠️ JS Eval Error: $e');
          if (!completer.isCompleted) completer.complete(null);
        }
      },
    );

    dynamic finalResult;
    try {
      await wv.run();
      finalResult = await completer.future.timeout(Duration(seconds: waitSec), onTimeout: () {
        debugPrint('⚠️ _runJS Timed out after $waitSec seconds for $targetUrl');
        return null;
      });
    } finally {
      disposed = true;
      try {
        await wv.webViewController?.stopLoading();
        await wv.dispose();
      } catch (e) {
        // Ignore dispose error
      }
    }
    
    if (finalResult == null) {
      debugPrint('🔄 _runJS failed/timed out. Falling back to WebView execution...');
      _forceLiveExecution = true;
      finalResult = await _runJSLive(targetUrl, functionCall, waitSec: 35);
    }
    return finalResult;
  }

  /// تشغيل JS في HeadlessWebView يفتح الصفحة مباشرة من السيرفر
  /// مخصص لـ getMangaDetails لضمان عمل AJAX/fetch
  Future<dynamic> _runJSLive(String targetUrl, String functionCall, {int waitSec = 35}) async {
    return await _liveExecutionLock.synchronized(() async {
      final completer = Completer<dynamic>();
      bool disposed = false;
      bool hasResult = false;

      final wv = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(targetUrl)),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        domStorageEnabled: true,
        userAgent: NetworkModule().userAgent,
        contentBlockers: [],
        useShouldInterceptRequest: false,
      ),
      onLoadStop: (ctrl, url) async {
        debugPrint('🌐 _runJSLive onLoadStop fired for: $url');
        if (disposed || hasResult) return;
        try {
          final title = await ctrl.getTitle() ?? '';
          final lowerTitle = title.toLowerCase();
          if (lowerTitle.contains('just a moment') ||
              lowerTitle.contains('checking your browser') ||
              lowerTitle.contains('verify you are human')) {
            debugPrint('🛡️ Cloudflare challenge detected in HeadlessWebView: $url');
            final bypassResult = await CloudflareBypassService().requestBypass(targetUrl);
            if (bypassResult != null) {
               await ctrl.reload();
            } else {
               if (!completer.isCompleted) completer.complete(null);
            }
            return;
          }

          String actualScript = '';
          try {
            actualScript = await rootBundle.loadString('assets/extensions/$scriptFile');
          } catch (e) {
            actualScript = await rootBundle.loadString('assets/extensions/universal_madara.js');
          }
          await ctrl.evaluateJavascript(source: actualScript);
          
          // استدعاء الدالة مع دعم async
          final result = await ctrl.callAsyncJavaScript(
            functionBody: '''
              try {
                var result = await $functionCall
                return JSON.stringify(result);
              } catch(e) {
                return JSON.stringify({error: e.message});
              }
            ''',
          );
          
          final value = result?.value;
          debugPrint('✅ JS Live Executed for $targetUrl. Result length: ${value?.toString().length ?? 0}');
          hasResult = true;
          if (!completer.isCompleted) {
            completer.complete(value);
          }
        } catch (e) {
          debugPrint('⚠️ JS Live Eval Error: $e');
          if (!completer.isCompleted) completer.complete(null);
        }
      },
    );

      try {
        await wv.run();
        final result = await completer.future.timeout(Duration(seconds: waitSec), onTimeout: () async {
          debugPrint('⚠️ _runJSLive Timed out after $waitSec seconds for $targetUrl. Attempting forced JS extraction...');
          try {
            final ctrl = wv.webViewController;
            if (ctrl != null) {
              String actualScript = '';
              try {
                actualScript = await rootBundle.loadString('assets/extensions/$scriptFile');
              } catch (e) {
                actualScript = await rootBundle.loadString('assets/extensions/universal_madara.js');
              }
              await ctrl.evaluateJavascript(source: actualScript);
              final jsResult = await ctrl.callAsyncJavaScript(
                functionBody: '''
                  try {
                    var result = await $functionCall
                    return JSON.stringify(result);
                  } catch(e) {
                    return JSON.stringify({error: e.message});
                  }
                ''',
              );
              final value = jsResult?.value;
              if (value != null && value.toString().length > 10) {
                debugPrint('✅ Forced JS Live Executed for $targetUrl. Result length: ${value.toString().length}');
                return value;
              }
            }
          } catch (e) {
            debugPrint('⚠️ Forced JS failed: $e');
          }
          return null;
        });
        return result;
      } finally {
        disposed = true;
        try {
          await wv.webViewController?.stopLoading();
          await wv.dispose();
        } catch (e) {
          // Ignore dispose error
        }
      }
    });
  }

  @override
  Future<List<MangaMetadata>> getPopularManga({int page = 1}) async {
    List<String> pathsToTry = _workingPopularPath != null
        ? [_workingPopularPath!]
        : popularPath.isNotEmpty
            ? [popularPath]
            : [
                '$baseUrl/series/page/{page}/?m_orderby=views',
                '$baseUrl/comic/page/{page}/?m_orderby=views',
                '$baseUrl/page/{page}/?s=&post_type=wp-manga&m_orderby=views', // محاولة أخيرة عبر مسار البحث
              ];

    for (final path in pathsToTry) {
      if (path.isEmpty) continue;
      
      final targetUrl = path.replaceAll('{page}', page.toString());
      final result = await _runJS(targetUrl, 'ExtensionScraper.scrapePopularManga(document)');
      
      if (result != null) {
        try {
          dynamic parsed = result;
          if (result is String) {
            try { parsed = jsonDecode(result); } catch (_) {}
          }
          if (parsed is String) {
            try { parsed = jsonDecode(parsed); } catch (_) {}
          }
          if (parsed is List && parsed.isNotEmpty) {
            _workingPopularPath = path; // حفظ المسار الناجح لعدم تكرار المحاولة
            return parsed.map((e) => MangaMetadata(
              title: e['title'] ?? '',
              url: e['url'] ?? '',
              coverUrl: e['imageUrl'] ?? e['coverUrl'] ?? '',
            )).toList();
          }
        } catch (e) {
          debugPrint('⚠️ Error parsing popular manga JS for $path: $e');
        }
      }
    }
    return [];
  }

  @override
  Future<List<MangaMetadata>> searchManga(String query, {int page = 1}) async {
    final targetUrl = searchPath.isEmpty ? '$baseUrl/?s=$query' : searchPath.replaceAll('{page}', page.toString()).replaceAll('{query}', Uri.encodeComponent(query));
    final result = await _runJS(targetUrl, 'ExtensionScraper.scrapePopularManga(document)');
    
    if (result == null) return [];
    
    try {
      dynamic parsed = result;
      if (result is String) {
        try { parsed = jsonDecode(result); } catch (_) {}
      }
      if (parsed is String) {
        try { parsed = jsonDecode(parsed); } catch (_) {}
      }
      if (parsed is List) {
        return parsed.map((e) => MangaMetadata(
          title: e['title'] ?? '',
          url: e['url'] ?? '',
          coverUrl: e['imageUrl'] ?? e['coverUrl'] ?? '',
        )).toList();
      }
      return [];
    } catch (e) {
      debugPrint('⚠️ Error parsing search JS: $e');
      return [];
    }
  }

  @override
  Future<MangaMetadata> getMangaDetails(String mangaUrl) async {
    // استخدم _runJSLive لفتح الصفحة الحقيقية من السيرفر
    // هذا ضروري لكي يعمل fetch() لجلب الفصول عبر AJAX
    final result = await _runJSLive(mangaUrl, 'ExtensionScraper.scrapeMangaDetails(document)');
    
    if (result == null) {
      debugPrint('⚠️ getMangaDetails returned null for $mangaUrl');
      return MangaMetadata(title: 'Unknown', url: mangaUrl, coverUrl: '');
    }
    
    try {
      dynamic e = result;
      if (result is String) {
        try { e = jsonDecode(result); } catch (_) {}
      }
      
      if (e is Map) {
        debugPrint('📖 Details parsed: title=${e['title']}, chapters=${(e['chapters'] as List?)?.length ?? 0}, desc=${(e['description'] ?? '').toString().length} chars');
        
        return MangaMetadata(
        title: e['title'] ?? '',
        url: e['url'] ?? mangaUrl,
        coverUrl: e['imageUrl'] ?? e['coverUrl'] ?? '',
        description: e['description'] ?? '',
        author: e['author'] ?? '',
        status: e['status'] ?? '',
        genres: List<String>.from(e['genres'] ?? []),
        chapters: (e['chapters'] as List?)?.map((c) => ChapterMetadata(
          title: c['title'] ?? '',
          url: c['url'] ?? '',
          date: null,
        )).toList() ?? [],
      );
      }
      return MangaMetadata(title: 'Unknown', url: mangaUrl, coverUrl: '');
    } catch (e) {
      debugPrint('⚠️ Error parsing details JS: $e');
      return MangaMetadata(title: 'Unknown', url: mangaUrl, coverUrl: '');
    }
  }

  @override
  Future<List<String>> getChapterImages(String chapterUrl) async {
    final result = await _runJS(chapterUrl, 'ExtensionScraper.scrapeChapterPages(document)');
    
    if (result == null) return [];
    
    try {
      dynamic parsed = result;
      if (result is String) {
        try { parsed = jsonDecode(result); } catch (_) {}
      }
      if (parsed is List) {
        return parsed.map((e) => e.toString()).toList();
      }
      return [];
    } catch (e) {
      debugPrint('⚠️ Error parsing pages JS: $e');
      return [];
    }
  }
}
