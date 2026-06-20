import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/foundation.dart';

/// تخزين دائم للـ Cookies لكل Domain
/// يُستخدم لحفظ cf_clearance و cookies أخرى بعد تجاوز Cloudflare
/// مستوحى من AndroidCookieJar في Tachiyomi/Mihon
class CookieStore {
  static const _boxName = 'cf_cookies';
  static late Box _box;

  /// تهيئة التخزين (يُستدعى في main.dart)
  static Future<void> init() async {
    _box = await Hive.openBox(_boxName);
    debugPrint('🍪 CookieStore initialized: ${_box.length} domains cached');
  }

  /// حفظ cookies لنطاق معين مع وقت الحفظ
  static Future<void> saveCookies({
    required String domain,
    required String cookies,
    required String userAgent,
  }) async {
    final data = {
      'cookies': cookies,
      'userAgent': userAgent,
      'savedAt': DateTime.now().millisecondsSinceEpoch,
    };
    await _box.put(domain, data);
    debugPrint('🍪 Cookies saved for $domain (${cookies.length} chars)');
  }

  /// استرجاع cookies صالحة لنطاق معين
  /// الـ cf_clearance صالح عادةً لـ 30 دقيقة، نستخدم 25 دقيقة كحد أمان
  static String? getCookies(String domain) {
    final data = _box.get(domain) as Map?;
    if (data == null) return null;

    final savedAt = data['savedAt'] as int? ?? 0;
    final age = DateTime.now().millisecondsSinceEpoch - savedAt;
    const maxAge = 25 * 60 * 1000; // 25 دقيقة

    if (age > maxAge) {
      debugPrint('🍪 Cookies expired for $domain (age: ${age ~/ 1000}s)');
      _box.delete(domain);
      return null;
    }

    return data['cookies'] as String?;
  }

  /// استرجاع User-Agent المحفوظ لنطاق معين
  static String? getUserAgent(String domain) {
    final data = _box.get(domain) as Map?;
    return data?['userAgent'] as String?;
  }

  /// التحقق من وجود cf_clearance صالح لنطاق معين
  static bool hasValidClearance(String domain) {
    final cookies = getCookies(domain);
    if (cookies == null) return false;
    return cookies.contains('cf_clearance');
  }

  /// حذف cookies لنطاق معين
  static Future<void> clearDomain(String domain) async {
    await _box.delete(domain);
    debugPrint('🍪 Cookies cleared for $domain');
  }

  /// حذف جميع الـ cookies المخزنة
  static Future<void> clearAll() async {
    await _box.clear();
    debugPrint('🍪 All cookies cleared');
  }

  /// استخراج اسم النطاق من URL
  static String extractDomain(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host;
    } catch (_) {
      return url;
    }
  }
}
