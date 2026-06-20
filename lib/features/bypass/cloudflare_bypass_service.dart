import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/network/cookie_store.dart';
import '../../core/network/network_module.dart';
import '../../app.dart';
import 'presentation/cloudflare_bypass_page.dart';

/// نتيجة عملية تجاوز Cloudflare
class BypassResult {
  final String cookies;
  final String userAgent;

  BypassResult({required this.cookies, required this.userAgent});
}

/// خدمة تجاوز Cloudflare — تنسق بين Interceptor (خلفي) والـ UI
/// تتبع نمط Tachiyomi: تفتح Route كاملة وتنتظر النتيجة
class CloudflareBypassService {
  static final CloudflareBypassService _instance = CloudflareBypassService._internal();
  factory CloudflareBypassService() => _instance;
  CloudflareBypassService._internal();

  /// هل عملية bypass جارية حالياً
  bool _isBypassing = false;

  /// طلب bypass — يفتح صفحة WebView كاملة وينتظر النتيجة
  /// يُرجع BypassResult إذا نجح، أو null إذا فشل/ألغي
  Future<BypassResult?> requestBypass(String url) async {
    // منع فتح أكثر من صفحة bypass في نفس الوقت
    if (_isBypassing) {
      debugPrint('🛡️ Bypass already in progress, skipping duplicate request');
      return null;
    }

    final navigator = MangaLensApp.navigatorKey.currentState;
    if (navigator == null) {
      debugPrint('🛡️ ❌ Navigator not available!');
      return null;
    }

    _isBypassing = true;

    try {
      debugPrint('🛡️ Opening bypass page for: $url');

      // فتح صفحة التحقق كـ Route كاملة (نمط Tachiyomi WebViewActivity)
      final result = await navigator.push<BypassResult>(
        MaterialPageRoute(
          builder: (_) => CloudflareBypassPage(targetUrl: url),
          fullscreenDialog: true, // يُعرض كـ dialog بشكل كامل
        ),
      );

      if (result != null) {
        final domain = CookieStore.extractDomain(url);

        // حفظ الـ cookies في التخزين الدائم
        await CookieStore.saveCookies(
          domain: domain,
          cookies: result.cookies,
          userAgent: result.userAgent,
        );

        // تحديث UA في NetworkModule
        NetworkModule().updateUserAgent(result.userAgent);

        debugPrint('🛡️ ✅ Bypass result stored for domain: $domain');
        return result;
      }

      debugPrint('🛡️ ❌ Bypass page returned null (cancelled/failed)');
      return null;
    } catch (e) {
      debugPrint('🛡️ ❌ Bypass error: $e');
      return null;
    } finally {
      _isBypassing = false;
    }
  }
}
