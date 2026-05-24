import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/models/site_bookmark.dart';
import '../../../core/services/history_service.dart';
import '../providers/browser_provider.dart';
import 'tab_switcher.dart';

/// شريط التحكم السفلي المطور للمتصفح (7 أزرار)
class BrowserControls extends ConsumerStatefulWidget {
  final VoidCallback onHomeTap;

  const BrowserControls({super.key, required this.onHomeTap});

  @override
  ConsumerState<BrowserControls> createState() => _BrowserControlsState();
}

class _BrowserControlsState extends ConsumerState<BrowserControls> {
  @override
  Widget build(BuildContext context) {
    final browserState = ref.watch(browserProvider);
    final browserNotifier = ref.read(browserProvider.notifier);

    // التحقق من حالة المفضلة للرابط الحالي
    final currentUrl = browserState.currentUrl;
    final isOnSite = currentUrl.isNotEmpty && 
                     currentUrl != 'about:blank' && 
                     !currentUrl.contains('google.com/search');
    String baseSiteUrl = '';
    String bookmarkId = '';
    if (isOnSite) {
      final uri = Uri.tryParse(currentUrl);
      if (uri != null) {
        baseSiteUrl = '${uri.scheme}://${uri.host}';
        bookmarkId = baseSiteUrl.hashCode.abs().toString();
      } else {
        baseSiteUrl = currentUrl;
        bookmarkId = currentUrl.hashCode.abs().toString();
      }
    }
    final isBookmarked = isOnSite && bookmarkId.isNotEmpty && HistoryService.isBookmarked(bookmarkId);

    return Container(
      // شريط سفلي متكامل يغطي كامل العرض بخلفية صلبة
      height: 72 + MediaQuery.of(context).padding.bottom, 
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.border, width: 1.0)),
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 1. زر الرجوع للخلف
            _ControlButton(
              icon: Icons.arrow_back_ios_new_rounded,
              onTap: browserState.canGoBack ? () => browserNotifier.goBack() : null,
              isActive: browserState.canGoBack,
            ),

            // 2. زر التقدم للأمام
            _ControlButton(
              icon: Icons.arrow_forward_ios_rounded,
              onTap: browserState.canGoForward ? () => browserNotifier.goForward() : null,
              isActive: browserState.canGoForward,
            ),

            // 3. زر التحديث / الإيقاف
            _ControlButton(
              icon: browserState.isLoading ? Icons.close_rounded : Icons.refresh_rounded,
              onTap: browserState.isLoading ? () => browserNotifier.stopLoading() : () => browserNotifier.reload(),
              isActive: true,
            ),

            // 4. زر ترجمة الصفحة إلى العربية
            _ControlButton(
              icon: Icons.translate_rounded,
              onTap: isOnSite ? () => _translatePage(context, browserState.controller) : null,
              isActive: isOnSite,
            ),

            // 5. زر إضافة / إزالة المفضلة
            _ControlButton(
              icon: isBookmarked ? Icons.star_rounded : Icons.star_outline_rounded,
              onTap: isOnSite ? () => _toggleBookmark(context, baseSiteUrl, currentUrl, browserState.title, isBookmarked, bookmarkId) : null,
              isActive: isOnSite,
              color: isBookmarked ? Colors.amber : null,
            ),

            GestureDetector(
              onTap: () async {
                // التقاط لقطة شاشة للتبويب النشط حالياً لتحديث معاينته البصرية قبل عرض شاشة التبويبات
                final activeId = ref.read(browserProvider).activeTab.id;
                await ref.read(browserProvider.notifier).captureAndSaveScreenshot(activeId);

                if (context.mounted) {
                  showModalBottomSheet(
                    context: context,
                    backgroundColor: Colors.transparent,
                    isScrollControlled: true,
                    builder: (context) => const TabSwitcherBottomSheet(),
                  );
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: AppColors.navBarActive,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Center(
                    child: Text(
                      '${browserState.tabs.length}',
                      style: const TextStyle(
                        color: AppColors.navBarActive,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ).animate().scale(
              duration: 200.ms, 
              begin: const Offset(0.9, 0.9), 
              end: const Offset(1.0, 1.0),
              curve: Curves.easeOutBack
            ),

            // 7. زر الرئيسية للعودة للوحة تحكم التطبيق
            _ControlButton(
              icon: Icons.home_rounded,
              onTap: widget.onHomeTap,
              isActive: true,
            ),
          ],
        ),
      ),
    );
  }

  /// حفظ / إزالة المفضلة
  void _toggleBookmark(BuildContext context, String baseSiteUrl, String url, String title, bool isBookmarked, String id) async {
    if (isBookmarked) {
      await HistoryService.removeBookmark(id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('bookmark_removed'))),
        );
      }
    } else {
      final uri = Uri.tryParse(url);
      String siteName = '';
      if (uri != null) {
        final host = uri.host.replaceFirst('www.', '');
        if (host.contains('.')) {
          final parts = host.split('.');
          siteName = parts[0].substring(0, 1).toUpperCase() + parts[0].substring(1);
        } else {
          siteName = host;
        }
      } else {
        siteName = url;
      }
      
      final favicon = uri != null ? 'https://www.google.com/s2/favicons?domain=${uri.host}&sz=128' : null;

      await HistoryService.addBookmark(SiteBookmark(
        id: id,
        name: siteName,
        url: baseSiteUrl.isNotEmpty ? baseSiteUrl : url,
        favicon: favicon,
      ));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('bookmark_added'))),
        );
      }
    }
    setState(() {}); // تحديث حالة النجمة محلياً
  }

  /// ترجمة صفحة الويب الحالية إلى العربية مع تعديل الاتجاه (RTL)
  void _translatePage(BuildContext context, InAppWebViewController? controller) async {
    if (controller == null) return;
    
    await controller.evaluateJavascript(source: '''
      (function() {
        if (document.getElementById('google_translate_element')) return;

        // إخفاء الشريط العلوي الخاص بجوجل
        var style = document.createElement('style');
        style.innerHTML = 'body { top: 0 !important; } .skiptranslate, #google_translate_element { display: none !important; }';
        document.head.appendChild(style);

        // وضع الكوكي ليترجم للعربية تلقائيا
        document.cookie = 'googtrans=/auto/ar; path=/; domain=' + window.location.hostname;
        document.cookie = 'googtrans=/auto/ar; path=/;';

        var div = document.createElement('div');
        div.id = 'google_translate_element';
        document.body.appendChild(div);

        var script = document.createElement('script');
        script.type = 'text/javascript';
        script.src = 'https://translate.google.com/translate_a/element.js?cb=googleTranslateElementInit';
        document.head.appendChild(script);

        window.googleTranslateElementInit = function() {
            new google.translate.TranslateElement({
                pageLanguage: 'auto',
                includedLanguages: 'ar',
                autoDisplay: false
            }, 'google_translate_element');
            
            // محاولة فرض الترجمة بحدث برمجي كل نصف ثانية حتى تنجح
            var interval = setInterval(function() {
                var select = document.querySelector('.goog-te-combo');
                if (select) {
                    if (select.value !== 'ar') {
                        select.value = 'ar';
                        select.dispatchEvent(new Event('change', { bubbles: true }));
                    } else {
                        clearInterval(interval); // التوقف عند نجاح الترجمة
                    }
                }
            }, 500);
        };

        // تعديل اتجاه النص للعربية (من اليمين لليسار)
        document.body.style.direction = 'rtl';
        document.body.style.textAlign = 'right';
      })();
    ''');
    
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('جاري ترجمة الصفحة إلى العربية...', style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
          backgroundColor: AppColors.primary,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool isActive;
  final Color? color;

  const _ControlButton({
    required this.icon,
    required this.onTap,
    this.isActive = true,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        splashColor: AppColors.primary.withOpacity(0.1),
        highlightColor: AppColors.primary.withOpacity(0.05),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: color ?? (isActive ? AppColors.navBarActive : AppColors.navBarInactive),
                size: 24,
              ),
            ],
          ),
        ),
      ),
    ).animate(target: isActive ? 1 : 0).scale(
      duration: 200.ms, 
      begin: const Offset(0.9, 0.9), 
      end: const Offset(1.0, 1.0),
      curve: Curves.easeOutBack
    );
  }
}
