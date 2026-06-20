import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../core/network/cookie_store.dart';
import '../../core/network/network_module.dart';
import 'cloudflare_bypass_service.dart';

/// Cloudflare Interceptor — نمط Tachiyomi/Mihon
///
/// التدفق:
/// 1. onRequest: أضف cookies مخزنة + UA الموحد
/// 2. onError: إذا كان 403/503 + Cloudflare markers:
///    a. تحقق من cookies مخزنة صالحة → أعد المحاولة
///    b. اطلب bypass عبر صفحة WebView كاملة
///    c. خزّن cookies جديدة → أعد المحاولة
class CloudflareInterceptor extends Interceptor {
  final Dio dio;

  /// قفل لمنع bypass متعدد في نفس الوقت (طلبات متزامنة)
  static Completer<bool>? _bypassLock;

  CloudflareInterceptor(this.dio);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final domain = CookieStore.extractDomain(options.uri.toString());
    final networkModule = NetworkModule();

    // 1. أضف User-Agent الموحد
    options.headers['User-Agent'] = networkModule.userAgent;

    // 2. أضف cookies مخزنة إن وُجدت
    final storedCookies = CookieStore.getCookies(domain);
    if (storedCookies != null && storedCookies.isNotEmpty) {
      // دمج مع أي cookies موجودة في الطلب
      final existing = options.headers['Cookie'] as String? ?? '';
      if (existing.isNotEmpty) {
        options.headers['Cookie'] = '$existing; $storedCookies';
      } else {
        options.headers['Cookie'] = storedCookies;
      }
    }

    super.onRequest(options, handler);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    if (!_isCloudflareChallenge(err)) {
      return super.onError(err, handler);
    }

    final url = err.requestOptions.uri.toString();
    debugPrint('🛡️ Cloudflare challenge detected on: $url');

    // حماية من التكرار اللانهائي
    final retries = err.requestOptions.extra['cf_retries'] as int? ?? 0;
    if (retries >= 2) {
      debugPrint('🛡️ Max retries reached. Aborting.');
      return super.onError(err, handler);
    }

    // إذا كان bypass جارٍ بالفعل (من طلب آخر)، انتظر نتيجته
    if (_bypassLock != null) {
      debugPrint('🛡️ Bypass already in progress. Waiting...');
      final success = await _bypassLock!.future;
      if (success) {
        return _retryRequest(err.requestOptions, retries, handler);
      }
      return super.onError(err, handler);
    }

    // ابدأ عملية bypass جديدة
    _bypassLock = Completer<bool>();

    try {
      // افتح صفحة التحقق الكاملة
      debugPrint('🛡️ Opening bypass page...');
      final result = await CloudflareBypassService().requestBypass(url);

      if (result != null) {
        debugPrint('🛡️ ✅ Bypass successful! Retrying request...');
        _bypassLock!.complete(true);
        _bypassLock = null;
        return _retryRequest(err.requestOptions, retries, handler);
      } else {
        debugPrint('🛡️ ❌ Bypass failed or cancelled.');
        _bypassLock!.complete(false);
        _bypassLock = null;
      }
    } catch (e) {
      debugPrint('🛡️ Bypass error: $e');
      if (_bypassLock != null && !_bypassLock!.isCompleted) {
        _bypassLock!.complete(false);
      }
      _bypassLock = null;
    }

    super.onError(err, handler);
  }

  /// إعادة الطلب مع cookies جديدة
  Future<void> _retryRequest(
    RequestOptions requestOptions,
    int retries,
    ErrorInterceptorHandler handler,
  ) async {
    try {
      final domain = CookieStore.extractDomain(requestOptions.uri.toString());
      final storedCookies = CookieStore.getCookies(domain) ?? '';
      final networkModule = NetworkModule();

      requestOptions.extra['cf_retries'] = retries + 1;

      // دمج Cookies
      String finalCookies = storedCookies;
      final existingCookie = requestOptions.headers['Cookie'] as String? ?? '';
      if (existingCookie.isNotEmpty && !existingCookie.contains(storedCookies)) {
        finalCookies = '$existingCookie; $storedCookies';
      }

      final options = Options(
        method: requestOptions.method,
        headers: {
          ...requestOptions.headers,
          'User-Agent': networkModule.userAgent,
          if (finalCookies.isNotEmpty) 'Cookie': finalCookies,
        },
        responseType: requestOptions.responseType,
        extra: requestOptions.extra,
      );

      final response = await dio.request<dynamic>(
        requestOptions.path,
        data: requestOptions.data,
        queryParameters: requestOptions.queryParameters,
        options: options,
      );
      return handler.resolve(response);
    } on DioException catch (e) {
      e.requestOptions.extra['cf_retries'] = retries + 1;
      return handler.reject(e);
    } catch (e) {
      return handler.reject(
        DioException(requestOptions: requestOptions, error: e),
      );
    }
  }

  /// كشف Cloudflare Challenge من Response
  bool _isCloudflareChallenge(DioException err) {
    final response = err.response;
    if (response == null) return false;

    if (response.statusCode == 503 || response.statusCode == 403) {
      final body = response.data?.toString().toLowerCase() ?? '';
      return body.contains('cf-browser-verification') ||
          body.contains('just a moment') ||
          body.contains('please stand by') ||
          body.contains('verify you are human') ||
          body.contains('challenge-platform');
    }
    return false;
  }
}
