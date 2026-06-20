import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../../features/bypass/cloudflare_interceptor.dart';

/// وحدة الشبكة المركزية — Dio واحد للتطبيق كله
/// يتبع نمط Tachiyomi حيث يتم مشاركة cookies و UA عبر جميع الطلبات
class NetworkModule {
  static final NetworkModule _instance = NetworkModule._internal();
  factory NetworkModule() => _instance;
  NetworkModule._internal();

  late final Dio dio;
  bool _initialized = false;

  /// User-Agent حقيقي من WebView الجهاز (يُستخرج مرة واحدة)
  String _deviceUserAgent = '';

  String get userAgent => _deviceUserAgent.isNotEmpty
      ? _deviceUserAgent
      : 'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.6099.43 Mobile Safari/537.36';

  /// تهيئة الوحدة (يُستدعى في main.dart بعد CookieStore.init)
  Future<void> init() async {
    if (_initialized) return;

    // 1. استخراج User-Agent الحقيقي من WebView
    await _extractRealUserAgent();

    dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 15),
      headers: {
        'User-Agent': userAgent,
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.5',
        'Sec-Fetch-Dest': 'document',
        'Sec-Fetch-Mode': 'navigate',
        'Sec-Fetch-Site': 'none',
        'Sec-Fetch-User': '?1',
        'Upgrade-Insecure-Requests': '1',
      },
    ));

    // 3. إضافة CloudflareInterceptor
    dio.interceptors.add(CloudflareInterceptor(dio));

    _initialized = true;
    debugPrint('🌐 NetworkModule initialized. UA: ${userAgent.substring(0, userAgent.length.clamp(0, 60))}...');
  }

  /// استخراج User-Agent الحقيقي من Android WebView
  /// هذا مهم لأن Cloudflare يقارن UA بين الطلب الأصلي وWebView
  Future<void> _extractRealUserAgent() async {
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        final defaultUa = await InAppWebViewController.getDefaultUserAgent();
        if (defaultUa.isNotEmpty) {
          _deviceUserAgent = defaultUa;
          return;
        }
      }
    } catch (e) {
      debugPrint('🌐 Could not get default UA: $e');
    }
  }

  /// تحديث User-Agent (مثلاً بعد bypass ناجح)
  void updateUserAgent(String ua) {
    if (ua.isNotEmpty) {
      _deviceUserAgent = ua;
      dio.options.headers['User-Agent'] = ua;
    }
  }
}
