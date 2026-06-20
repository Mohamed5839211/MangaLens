import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../../../core/network/network_module.dart';
import '../cloudflare_bypass_service.dart';

/// صفحة تجاوز Cloudflare — Route كاملة (نمط Tachiyomi WebViewActivity)
///
/// تفتح WebView بكامل الإعدادات لعرض تحدي Cloudflare (Turnstile)
/// تراقب CookieManager للكشف عن cf_clearance
/// تُغلق تلقائياً عند النجاح وترجع BypassResult
class CloudflareBypassPage extends StatefulWidget {
  final String targetUrl;

  const CloudflareBypassPage({super.key, required this.targetUrl});

  @override
  State<CloudflareBypassPage> createState() => _CloudflareBypassPageState();
}

class _CloudflareBypassPageState extends State<CloudflareBypassPage> {
  InAppWebViewController? _controller;
  double _progress = 0.0;
  bool _bypassDone = false;
  Timer? _cookieCheckTimer;
  Timer? _autoCloseTimer;

  late final String _targetHost;
  late final String _userAgent;

  @override
  void initState() {
    super.initState();
    _targetHost = Uri.tryParse(widget.targetUrl)?.host ?? '';
    _userAgent = NetworkModule().userAgent;

    debugPrint('🛡️ 📋 BypassPage opened for: ${widget.targetUrl}');

    // Auto-close timeout — 120 ثانية كحد أقصى
    _autoCloseTimer = Timer(const Duration(seconds: 120), () {
      if (!_bypassDone && mounted) {
        debugPrint('🛡️ ⏰ Auto-close: 120s timeout');
        Navigator.of(context).pop(null);
      }
    });
  }

  @override
  void dispose() {
    _cookieCheckTimer?.cancel();
    _autoCloseTimer?.cancel();
    super.dispose();
  }

  /// بدء مراقبة cookies كل ثانية (نمط Tachiyomi CountDownLatch)
  void _startCookieMonitoring() {
    _cookieCheckTimer?.cancel();
    if (_bypassDone) return;

    _cookieCheckTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (_bypassDone || !mounted) {
        timer.cancel();
        return;
      }
      await _checkForClearanceCookie();
    });
  }

  /// الكشف الأساسي: هل وُجد cf_clearance cookie؟
  /// هذه الطريقة المعتمدة في Tachiyomi — بسيطة وموثوقة
  Future<void> _checkForClearanceCookie() async {
    if (_bypassDone || _controller == null) return;

    try {
      final currentUrl = await _controller!.getUrl();
      if (currentUrl == null) return;

      final cookieManager = CookieManager.instance();

      // فحص cookies للـ URL الحالي
      final cookies = await cookieManager.getCookies(url: currentUrl);

      // هل يوجد cf_clearance؟
      final hasClearance = cookies.any(
        (c) => c.name == 'cf_clearance' || c.name == '__cf_bm',
      );

      if (!hasClearance) return;

      // تأكيد إضافي: هل الصفحة لم تعد challenge؟
      final title = await _controller!.getTitle() ?? '';
      final lowerTitle = title.toLowerCase();
      if (lowerTitle.contains('just a moment') ||
          lowerTitle.contains('checking your browser') ||
          lowerTitle.contains('verify you are human')) {
        // لا تزال challenge رغم وجود cookie (ربما قيد المعالجة)
        return;
      }

      // ✅ نجح التحقق!
      _bypassDone = true;
      _cookieCheckTimer?.cancel();
      _autoCloseTimer?.cancel();

      final cookieString = cookies.map((c) => '${c.name}=${c.value}').join('; ');

      // استخراج UA الحقيقي من WebView
      final webViewUA = await _controller!.evaluateJavascript(
            source: 'navigator.userAgent',
          ) as String? ??
          _userAgent;

      debugPrint('🛡️ ✅ BYPASS SUCCESS!');
      debugPrint('🛡️ ✅ cf_clearance found! Cookies: ${cookies.length}');
      debugPrint('🛡️ ✅ UA: ${webViewUA.substring(0, webViewUA.length.clamp(0, 50))}...');

      if (mounted) {
        Navigator.of(context).pop(
          BypassResult(cookies: cookieString, userAgent: webViewUA),
        );
      }
    } catch (e) {
      debugPrint('🛡️ Cookie check error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(null),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'تخطي الحماية الأمنية',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                fontFamily: 'Cairo',
              ),
            ),
            Text(
              _targetHost,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 12,
              ),
            ),
          ],
        ),
        actions: [
          // زر إعادة التحميل
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70),
            onPressed: () => _controller?.reload(),
          ),
        ],
        bottom: _progress < 1.0
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(
                  value: _progress,
                  backgroundColor: Colors.transparent,
                  color: const Color(0xFF58A6FF),
                  minHeight: 2,
                ),
              )
            : null,
      ),
      body: Column(
        children: [
          // رسالة توجيهية
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: const Color(0xFF1C2128),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Color(0xFF58A6FF), size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'أكمل التحقق أدناه. سيتم الإغلاق تلقائياً بعد النجاح.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 13,
                      fontFamily: 'Cairo',
                    ),
                  ),
                ),
              ],
            ),
          ),

          // WebView
          Expanded(
            child: InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(widget.targetUrl)),
              initialSettings: InAppWebViewSettings(
                // JavaScript و DOM
                javaScriptEnabled: true,
                domStorageEnabled: true,
                databaseEnabled: true,

                // مطلوب لـ Cloudflare Turnstile
                mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
                thirdPartyCookiesEnabled: true,
                hardwareAcceleration: true,

                // عرض كمتصفح حقيقي
                preferredContentMode: UserPreferredContentMode.MOBILE,
                userAgent: _userAgent,

                // Cache
                clearCache: false,
                cacheEnabled: true,

                // سماح بأطر iframe (مطلوب لـ Turnstile widget)
                supportMultipleWindows: false,
                javaScriptCanOpenWindowsAutomatically: false,

                // الإيقاف الصريح لأي Content Blockers لتجنب أخطاء الشبكة الخلفية
                contentBlockers: [],
                useShouldInterceptRequest: false,

                // Zoom/Scroll
                supportZoom: true,
                overScrollMode: OverScrollMode.NEVER,

                // Allow file access
                allowFileAccess: true,
              ),
              onWebViewCreated: (controller) {
                _controller = controller;
              },
              onProgressChanged: (controller, progress) {
                if (mounted) {
                  setState(() => _progress = progress / 100);
                }
              },
              onLoadStop: (controller, url) async {
                debugPrint('🛡️ Page loaded: ${url?.toString().substring(0, (url.toString().length).clamp(0, 80))}');

                // فحص فوري
                await _checkForClearanceCookie();

                // بدء مراقبة دورية
                if (!_bypassDone) {
                  _startCookieMonitoring();
                }
              },
              onReceivedError: (controller, request, error) {
                if (request.isForMainFrame == true) {
                  debugPrint('🛡️ WebView error: ${error.description}');
                }
              },
              // السماح بجميع التنقلات (مطلوب لـ Cloudflare redirects)
              shouldOverrideUrlLoading: (controller, navigationAction) async {
                return NavigationActionPolicy.ALLOW;
              },
            ),
          ),
        ],
      ),
    );
  }
}
