import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// قواعد حجب الإعلانات — مستوحاة من EasyList
/// Ad-blocking rules derived from EasyList patterns
class AdBlockRules {
  AdBlockRules._();

  /// قائمة قواعد حجب المحتوى
  static List<ContentBlocker> get rules => [
        // ─── حجب نطاقات الإعلانات الشائعة ──────────────
        ..._adDomainRules,
        // ─── حجب أنواع الموارد الإعلانية ────────────────
        ..._resourceTypeRules,
        // ─── إخفاء العناصر الإعلانية بـ CSS ─────────────
        ..._cssHideRules,
        // ─── حجب النوافذ المنبثقة والتتبع ──────────────
        ..._popupAndTrackerRules,
      ];

  /// نطاقات إعلانية شائعة للحجب
  static final List<ContentBlocker> _adDomainRules = [
    // Google Ads
    '.*googlesyndication\\.com.*',
    '.*googleadservices\\.com.*',
    '.*doubleclick\\.net.*',
    '.*google-analytics\\.com.*',
    '.*googletagmanager\\.com.*',
    '.*googletagservices\\.com.*',
    '.*googlesyndication\\.com.*',
    // شبكات إعلانية شائعة
    '.*adcolony\\.com.*',
    '.*admob\\.com.*',
    '.*adnxs\\.com.*',
    '.*adsrvr\\.org.*',
    '.*advertising\\.com.*',
    '.*amazon-adsystem\\.com.*',
    '.*applovin\\.com.*',
    '.*bidswitch\\.net.*',
    '.*casalemedia\\.com.*',
    '.*chartboost\\.com.*',
    '.*criteo\\.com.*',
    '.*criteo\\.net.*',
    '.*facebook\\.com\\/tr.*',
    '.*fbcdn\\.net\\/.*ads.*',
    '.*inmobi\\.com.*',
    '.*ironSource\\.com.*',
    '.*mopub\\.com.*',
    '.*outbrain\\.com.*',
    '.*pubmatic\\.com.*',
    '.*revcontent\\.com.*',
    '.*rubiconproject\\.com.*',
    '.*smaato\\.net.*',
    '.*taboola\\.com.*',
    '.*tapjoy\\.com.*',
    '.*unity3d\\.com\\/.*ads.*',
    '.*unityads\\.unity3d\\.com.*',
    '.*vungle\\.com.*',
    '.*yieldmo\\.com.*',
    // تتبع
    '.*amplitude\\.com.*',
    '.*appsflyer\\.com.*',
    '.*branch\\.io.*',
    '.*hotjar\\.com.*',
    '.*mixpanel\\.com.*',
    '.*segment\\.io.*',
    '.*quantserve\\.com.*',
    '.*scorecardresearch\\.com.*',
    // إعلانات مواقع المانغا
    '.*exoclick\\.com.*',
    '.*exosrv\\.com.*',
    '.*juicyads\\.com.*',
    '.*popads\\.net.*',
    '.*popcash\\.net.*',
    '.*propellerads\\.com.*',
    '.*trafficjunky\\.net.*',
    '.*tsyndicate\\.com.*',
    '.*a-ads\\.com.*',
    '.*ad\\.plus.*',
    '.*adsterra\\.com.*',
    '.*disqusads\\.com.*',
    '.*mgid\\.com.*',
    '.*realsrv\\.com.*',
    '.*richads\\.com.*',
    '.*zergnet\\.com.*',
    '.*adskeeper\\.com.*',
    '.*ad-maven\\.com.*',
    '.*onclickads\\.net.*',
    '.*popmyads\\.com.*',
    '.*bidgear\\.com.*',
    '.*bidgear\\.com.*',
    '.*wpadm\\.com.*',
    '.*monetag\\.com.*',
    '.*infolinks\\.com.*',
    '.*yllix\\.com.*',
    '.*hilltopads\\.com.*',
  ].map((pattern) => ContentBlocker(
        trigger: ContentBlockerTrigger(
          urlFilter: pattern,
          // استثناء نطاقات التحقق الأمني لكي لا نكسر Cloudflare/hCaptcha
          unlessDomain: [
            'challenges.cloudflare.com',
            'cloudflare.com',
            'hcaptcha.com',
            'recaptcha.net',
            'gstatic.com',
            'turnstile.com',
          ],
        ),
        action: ContentBlockerAction(
          type: ContentBlockerActionType.BLOCK,
        ),
      )).toList();

  /// حجب موارد إعلانية بناءً على أنماط URL
  static final List<ContentBlocker> _resourceTypeRules = [
    // حجب سكريبتات الإعلانات (فقط الأنماط المؤكدة)
    ContentBlocker(
      trigger: ContentBlockerTrigger(
        urlFilter: '.*\\/adsbygoogle\\.js.*',
        resourceType: [ContentBlockerTriggerResourceType.SCRIPT],
      ),
      action: ContentBlockerAction(
        type: ContentBlockerActionType.BLOCK,
      ),
    ),
    // حجب سكريبتات مكافحة حجب الإعلانات (Anti-Adblock)
    ContentBlocker(
      trigger: ContentBlockerTrigger(
        urlFilter: '.*(fuckadblock|blockadblock|adblock-detector|anti-adblock|antiadblock).*',
        resourceType: [ContentBlockerTriggerResourceType.SCRIPT],
      ),
      action: ContentBlockerAction(
        type: ContentBlockerActionType.BLOCK,
      ),
    ),
    // حجب إطارات الإعلانات (احذر من حجب كلمات مثل read أو load)
    ContentBlocker(
      trigger: ContentBlockerTrigger(
        urlFilter: '.*\\/(ad|ads|advert|banner)\\.html.*',
        resourceType: [ContentBlockerTriggerResourceType.DOCUMENT],
      ),
      action: ContentBlockerAction(
        type: ContentBlockerActionType.BLOCK,
      ),
    ),
    // حجب صور البيكسل للتتبع
    ContentBlocker(
      trigger: ContentBlockerTrigger(
        urlFilter: '.*pixel\\..*',
        resourceType: [ContentBlockerTriggerResourceType.IMAGE],
      ),
      action: ContentBlockerAction(
        type: ContentBlockerActionType.BLOCK,
      ),
    ),
    // حجب أنماط URL إعلانية شائعة
    ContentBlocker(
      trigger: ContentBlockerTrigger(
        urlFilter: '.*\\/ads\\/.*',
      ),
      action: ContentBlockerAction(
        type: ContentBlockerActionType.BLOCK,
      ),
    ),
    ContentBlocker(
      trigger: ContentBlockerTrigger(
        urlFilter: '.*\\/adserver\\/.*',
      ),
      action: ContentBlockerAction(
        type: ContentBlockerActionType.BLOCK,
      ),
    ),
    ContentBlocker(
      trigger: ContentBlockerTrigger(
        urlFilter: '.*\\/banner\\/.*',
      ),
      action: ContentBlockerAction(
        type: ContentBlockerActionType.BLOCK,
      ),
    ),
    ContentBlocker(
      trigger: ContentBlockerTrigger(
        urlFilter: '.*\\/popup\\/.*',
      ),
      action: ContentBlockerAction(
        type: ContentBlockerActionType.BLOCK,
      ),
    ),
  ];

  /// إخفاء عناصر HTML الإعلانية الشائعة بـ CSS
  static final List<ContentBlocker> _cssHideRules = [
    ContentBlocker(
      trigger: ContentBlockerTrigger(urlFilter: '.*'),
      action: ContentBlockerAction(
        type: ContentBlockerActionType.CSS_DISPLAY_NONE,
        selector:
            '[class^="ad-"], [class*=" ad-"], [class^="ads-"], [class*=" ads-"], [class*="advert"], '
            '[id^="ad-"], [id*=" ad-"], [id^="ads-"], [id*=" ads-"], [id*="advert"], '
            '[class*="banner"], [id*="banner"], '
            '.ad, .ads, .adsbygoogle, .ad-container, .ad-wrapper, '
            '#ad, #ads, #adContainer, #adWrapper, '
            '[class*="popup"], [id*="popup"], '
            '[class*="overlay-ad"], [id*="overlay-ad"], '
            '.sponsored, .sponsor, '
            'iframe[src*="ad"], iframe[src*="banner"], '
            '[class*="sticky-ad"], [id*="sticky-ad"], '
            // إخفاء النوافذ المنبثقة لمكافحة الإعلانات
            '[class*="anti-ad"], [id*="anti-ad"], '
            '[class*="adblock-message"], [id*="adblock-message"], '
            '[class*="fc-ab-root"], .fc-ab-root, .ad-blocker-overlay, '
            '[class*="detect-adblock"]',
      ),
    ),
    // إخفاء الإشعارات المزعجة
    ContentBlocker(
      trigger: ContentBlockerTrigger(urlFilter: '.*'),
      action: ContentBlockerAction(
        type: ContentBlockerActionType.CSS_DISPLAY_NONE,
        selector:
            '[class*="cookie-banner"], [id*="cookie-banner"], '
            '[class*="cookie-consent"], [id*="cookie-consent"], '
            '[class*="gdpr"], [id*="gdpr"], '
            '[class*="notification-bar"], [id*="notification-bar"]',
      ),
    ),
  ];

  /// حجب النوافذ المنبثقة وسكريبتات التتبع
  static final List<ContentBlocker> _popupAndTrackerRules = [
    // حجب سكريبتات فتح نوافذ جديدة
    ContentBlocker(
      trigger: ContentBlockerTrigger(
        urlFilter: '.*\\.popunder\\..*',
      ),
      action: ContentBlockerAction(
        type: ContentBlockerActionType.BLOCK,
      ),
    ),
    ContentBlocker(
      trigger: ContentBlockerTrigger(
        urlFilter: '.*clickunder.*',
      ),
      action: ContentBlockerAction(
        type: ContentBlockerActionType.BLOCK,
      ),
    ),
    ContentBlocker(
      trigger: ContentBlockerTrigger(
        urlFilter: '.*\\/tracking\\/.*',
      ),
      action: ContentBlockerAction(
        type: ContentBlockerActionType.BLOCK,
      ),
    ),
    ContentBlocker(
      trigger: ContentBlockerTrigger(
        urlFilter: '.*\\/analytics\\/.*',
      ),
      action: ContentBlockerAction(
        type: ContentBlockerActionType.BLOCK,
      ),
    ),
  ];
}
