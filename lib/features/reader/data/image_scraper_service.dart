import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../models/scraped_image.dart';

/// خدمة استخراج صور المانغا من صفحات الويب
/// نظام هجين ثلاثي الطبقات:
///   الطبقة 1: Network Interception — اعتراض طلبات الصور من الشبكة
///   الطبقة 2: DOM Extraction — استخراج محسّن من DOM مع دعم picture/noscript/canvas/blob
///   الطبقة 3: MutationObserver — مراقبة الصور المضافة ديناميكياً أثناء التمرير
class ImageScraperService {
  /// قائمة نطاقات الإعلانات المعروفة لاستبعادها
  static const List<String> _adDomains = [
    'googlesyndication', 'googleadservices', 'doubleclick',
    'adnxs', 'adsrvr', 'adcolony', 'facebook.com/tr',
    'amazon-adsystem', 'outbrain', 'taboola', 'mgid',
    'popads', 'popcash', 'juicyads', 'exoclick',
    'trafficjunky', 'propellerads', 'adsterra',
    'pubadx', 'pubfuture', 'bidgear', 'revcontent',
    'criteo', 'rubiconproject', 'openx', 'appnexus',
    'smartadserver', 'ssp.yahoo', 'adskeeper',
    'acscdn', 'disqusads', 'monetag', 'a-ads',
    'hilltopads', 'clickadu', 'richpush', 'evadav',
    'roller-ads', 'onclicka', 'galaksion', 'clickaine',
  ];

  /// قائمة الإعلانات بصيغة JavaScript للعداد الحي
  static String get adDomainsList => _adDomains.map((d) => '"$d"').join(',');

  // ═══════════════════════════════════════════════════════════════
  //  الدالة الرئيسية: استخراج صور الفصل بنظام هجين ثلاثي الطبقات
  // ═══════════════════════════════════════════════════════════════

  /// استخراج صور الفصل من صفحة الويب
  /// [controller] — متحكم WebView الحالي
  /// [networkInterceptedUrls] — روابط الصور المعترضة من الشبكة (الطبقة 1)
  static Future<List<String>> extractChapterImages(
    InAppWebViewController controller, {
    List<String> networkInterceptedUrls = const [],
  }) async {
    try {
      // ═══ الخطوة 1: حقن IntersectionObserver Override + فك noscript ═══
      await _injectEarlyOverrides(controller);

      // ═══ الخطوة 2: حقن MutationObserver لمراقبة الصور الجديدة (الطبقة 3) ═══
      await _injectMutationObserver(controller);

      // ═══ الخطوة 3: تمرير ذكي محسّن لتحفيز Lazy Loading ═══
      await _enhancedAutoScroll(controller);

      // ═══ الخطوة 4: استخراج صور DOM المحسّن (الطبقة 2) ═══
      final domImages = await _extractDomImages(controller);
      debugPrint('📋 [Layer 2] DOM extraction: ${domImages.length} images');

      // ═══ الخطوة 5: جمع صور MutationObserver (الطبقة 3) ═══
      final mutationImages = await _collectMutationImages(controller);
      debugPrint('👁️ [Layer 3] MutationObserver: ${mutationImages.length} images');

      // ═══ الخطوة 6: دمج المصادر بذكاء ═══
      // DOM + MutationObserver دائماً (MO يلتقط صور Virtual Scroll المحذوفة من DOM)
      // Network يُتخطى عندما DOM+MO كافية (لأنه يشمل أغلفة ومصغرات غير مفلترة)
      debugPrint('🌐 [Layer 1] Network intercepted: ${networkInterceptedUrls.length} images');
      
      // دمج DOM + MutationObserver دائماً
      final domMutationMerged = _mergeAndDeduplicate(
        domImages: domImages,
        networkImages: const [], // تخطي الشبكة مؤقتاً
        mutationImages: mutationImages,
      );
      debugPrint('🔗 DOM + MutationObserver merged: ${domMutationMerged.length} images');
      
      List<ScrapedImage> merged;
      if (domMutationMerged.length >= 5) {
        // DOM+MO كافية → نستخدمها فقط
        debugPrint('✅ DOM+MO sufficient (${domMutationMerged.length} images), skipping network');
        merged = domMutationMerged;
      } else {
        // DOM+MO غير كافية → نضيف الشبكة كـ fallback
        debugPrint('⚠️ DOM+MO insufficient (${domMutationMerged.length} images), adding network');
        merged = _mergeAndDeduplicate(
          domImages: domImages,
          networkImages: networkInterceptedUrls,
          mutationImages: mutationImages,
        );
      }
      
      // ═══ فلتر مسار URL على النتيجة المدمجة ═══
      // لإزالة أي أغلفة/مصغرات التقطها MutationObserver
      if (merged.length > 5) {
        final pathGroups = <String, List<ScrapedImage>>{};
        for (final img in merged) {
          try {
            final uri = Uri.parse(img.url);
            final pathParts = uri.pathSegments;
            final pathKey = pathParts.length > 1 
                ? pathParts.sublist(0, (pathParts.length - 1).clamp(0, 3)).join('/')
                : uri.host;
            pathGroups.putIfAbsent(pathKey, () => []).add(img);
          } catch (_) {}
        }
        
        // إيجاد المجموعة المهيمنة
        String? bestPath;
        int bestSize = 0;
        for (final entry in pathGroups.entries) {
          if (entry.value.length > bestSize) {
            bestSize = entry.value.length;
            bestPath = entry.key;
          }
        }
        
        // إذا المجموعة المهيمنة >50% من الصور، نحتفظ بها فقط
        if (bestPath != null && bestSize > merged.length * 0.4 && bestSize >= 5) {
          debugPrint('🔍 URL path filter: ${merged.length} → $bestSize (path: $bestPath)');
          merged = pathGroups[bestPath]!;
        }
      }
      
      debugPrint('🔗 Final merged: ${merged.length} unique images');

      // ═══ الخطوة 7: الترتيب الذكي متعدد الطبقات ═══
      final sorted = _smartSort(merged);

      final urls = sorted.map((img) => img.url).toList();
      debugPrint('✅ Final extraction: ${urls.length} chapter images (sorted)');
      return urls;
    } catch (e) {
      debugPrint('❌ Image extraction error: $e');
      return [];
    }
  }

  // ═══════════════════════════════════════════════════════════════
  //  الخطوة 1: حقن مبكر — IntersectionObserver Override + noscript
  // ═══════════════════════════════════════════════════════════════

  static Future<void> _injectEarlyOverrides(
      InAppWebViewController controller) async {
    await controller.evaluateJavascript(source: '''
      (function() {
        // ═══ Override IntersectionObserver لجعل كل العناصر مرئية فوراً ═══
        try {
          if (window.__mangaLensIOOverridden) return;
          window.__mangaLensIOOverridden = true;
          
          var OrigIO = window.IntersectionObserver;
          if (OrigIO) {
            window.IntersectionObserver = function(cb, opts) {
              return new OrigIO(function(entries, obs) {
                var fakeEntries = [];
                for (var i = 0; i < entries.length; i++) {
                  var entry = entries[i];
                  try {
                    // إنشاء كائن وهمي يُبلغ أن العنصر مرئي
                    fakeEntries.push({
                      target: entry.target,
                      isIntersecting: true,
                      intersectionRatio: 1.0,
                      boundingClientRect: entry.boundingClientRect,
                      intersectionRect: entry.boundingClientRect,
                      rootBounds: entry.rootBounds,
                      time: entry.time
                    });
                  } catch(e) {
                    fakeEntries.push(entry);
                  }
                }
                cb(fakeEntries, obs);
              }, opts);
            };
            window.IntersectionObserver.prototype = OrigIO.prototype;
          }
        } catch(e) {}
        
        // ═══ فك الصور المخبأة في <noscript> ═══
        try {
          var noscripts = document.querySelectorAll('noscript');
          for (var i = 0; i < noscripts.length; i++) {
            var ns = noscripts[i];
            var content = ns.textContent || ns.innerHTML || '';
            if (content.indexOf('<img') !== -1) {
              var tmp = document.createElement('div');
              tmp.innerHTML = content;
              var imgs = tmp.querySelectorAll('img');
              for (var j = 0; j < imgs.length; j++) {
                var img = imgs[j];
                if (img.src && img.src.length > 10 && img.src.indexOf('data:') !== 0) {
                  // تأكد أن الصورة ليست موجودة بالفعل
                  var existing = document.querySelector('img[src="' + img.src + '"]');
                  if (!existing && ns.parentElement) {
                    ns.parentElement.insertBefore(img, ns);
                  }
                }
              }
            }
          }
        } catch(e) {}
      })();
    ''');
  }

  // ═══════════════════════════════════════════════════════════════
  //  الخطوة 2: حقن MutationObserver (الطبقة 3)
  // ═══════════════════════════════════════════════════════════════

  static Future<void> _injectMutationObserver(
      InAppWebViewController controller) async {
    await controller.evaluateJavascript(source: '''
      (function() {
        if (window.__mangaLensMO) return;
        
        window.__mangaLensCollectedMO = [];
        
        // دالة فلترة سريعة: استبعاد الصور الصغيرة والأيقونات
        function isLikelyChapterImage(src) {
          if (!src || src.length < 10 || src.indexOf('data:') === 0) return false;
          var lower = src.toLowerCase();
          // استبعاد أنماط واضحة
          var exclude = ['icon', 'logo', 'avatar', 'badge', 'arrow', 'btn',
            'button', 'emoji', 'favicon', 'placeholder', 'sns-', 'social',
            'search_', 'my-series_', 'manta-logo', 'open-graph', 'app-store',
            'google-play', 'qr-code', 'metadata', 'default_'];
          for (var i = 0; i < exclude.length; i++) {
            if (lower.indexOf(exclude[i]) !== -1) return false;
          }
          // استبعاد أحجام صغيرة في URL
          var sizeMatch = lower.match(/(\\d+)x(\\d+)/);
          if (sizeMatch && (parseInt(sizeMatch[1]) < 200 || parseInt(sizeMatch[2]) < 200)) return false;
          return true;
        }
        
        window.__mangaLensMO = new MutationObserver(function(mutations) {
          for (var m = 0; m < mutations.length; m++) {
            var mutation = mutations[m];
            
            // مراقبة العناصر المضافة
            if (mutation.type === 'childList') {
              for (var n = 0; n < mutation.addedNodes.length; n++) {
                var node = mutation.addedNodes[n];
                if (node.nodeType !== 1) continue;
                
                if (node.tagName === 'IMG') {
                  var src = node.src || node.getAttribute('data-src') || '';
                  if (isLikelyChapterImage(src)) {
                    window.__mangaLensCollectedMO.push(src);
                  }
                }
                
                // فحص الأبناء أيضاً
                if (node.querySelectorAll) {
                  var imgs = node.querySelectorAll('img');
                  for (var i = 0; i < imgs.length; i++) {
                    var s = imgs[i].src || imgs[i].getAttribute('data-src') || '';
                    if (isLikelyChapterImage(s)) {
                      window.__mangaLensCollectedMO.push(s);
                    }
                  }
                }
              }
            }
            
            // مراقبة تغيير src
            if (mutation.type === 'attributes' && mutation.target.tagName === 'IMG') {
              var newSrc = mutation.target.src || '';
              if (isLikelyChapterImage(newSrc)) {
                window.__mangaLensCollectedMO.push(newSrc);
              }
            }
          }
        });
        
        window.__mangaLensMO.observe(document.documentElement, {
          childList: true,
          subtree: true,
          attributes: true,
          attributeFilter: ['src', 'data-src', 'data-lazy-src', 'data-original']
        });
      })();
    ''');
  }

  /// جمع الصور التي رصدها MutationObserver
  static Future<List<String>> _collectMutationImages(
      InAppWebViewController controller) async {
    try {
      final result = await controller.evaluateJavascript(source: '''
        (function() {
          var urls = window.__mangaLensCollectedMO || [];
          // تنظيف MutationObserver
          if (window.__mangaLensMO) {
            window.__mangaLensMO.disconnect();
            window.__mangaLensMO = null;
          }
          // إزالة التكرار
          var unique = [];
          var seen = {};
          for (var i = 0; i < urls.length; i++) {
            if (!seen[urls[i]]) {
              seen[urls[i]] = true;
              unique.push(urls[i]);
            }
          }
          window.__mangaLensCollectedMO = [];
          return JSON.stringify(unique);
        })();
      ''');

      if (result == null || result == 'null' || result == '[]') {
        return [];
      }
      return _parseImageUrls(result.toString());
    } catch (e) {
      debugPrint('⚠️ MutationObserver collection error: $e');
      return [];
    }
  }

  // ═══════════════════════════════════════════════════════════════
  //  الخطوة 3: التمرير التلقائي المحسّن
  // ═══════════════════════════════════════════════════════════════

  static Future<void> _enhancedAutoScroll(
      InAppWebViewController controller) async {
    final completer = Completer<void>();

    controller.addJavaScriptHandler(
      handlerName: 'scrollComplete',
      callback: (args) {
        if (!completer.isCompleted) {
          final validCount = args.isNotEmpty ? args[0] : 0;
          final totalImgs = args.length > 1 ? args[1] : 0;
          debugPrint(
              '📜 Auto-scroll complete! Found $totalImgs img tags, $validCount with valid src');
          completer.complete();
        }
      },
    );

    await controller.evaluateJavascript(source: '''
      (async function() {
        console.log('[MangaLens] === Starting Enhanced Auto-Scroll ===');
        
        // ═══ قائمة موسّعة لأنماط Lazy-Load (16+ نمط) ═══
        var lazyAttrs = [
          'data-src', 'data-lazy-src', 'data-original', 'data-image',
          'data-lazy', 'data-url', 'data-echo', 'data-srcset',
          'data-load', 'data-img', 'data-real-src', 'data-aload',
          'data-delayed-url', 'data-cfsrc', 'data-bg', 'data-source',
          'data-hi-res-src', 'data-retina', 'lazysrc', 'origsrc'
        ];
        
        // ═══ دالة: فرض تحميل الصور الكسولة (محسّنة) ═══
        function forceLazyLoad() {
          var allImgs = document.querySelectorAll('img');
          var forced = 0;
          for (var i = 0; i < allImgs.length; i++) {
            var img = allImgs[i];
            
            // إزالة سمات التحميل الكسول
            if (img.getAttribute('loading') === 'lazy') img.removeAttribute('loading');
            if (img.getAttribute('decoding') === 'async') img.removeAttribute('decoding');
            
            for (var a = 0; a < lazyAttrs.length; a++) {
              var lazySrc = img.getAttribute(lazyAttrs[a]);
              if (lazySrc && lazySrc.length > 10 && lazySrc.indexOf('data:') !== 0) {
                if (!img.src || img.src.indexOf('data:') === 0 || img.src === '' || 
                    img.src === window.location.href ||
                    img.src.indexOf('placeholder') !== -1 ||
                    img.src.indexOf('loading') !== -1 ||
                    img.src.indexOf('blank') !== -1 ||
                    img.src.indexOf('lazy') !== -1) {
                  img.src = lazySrc;
                  forced++;
                  break;
                }
              }
            }
            
            // التعامل مع srcset
            var lazySrcset = img.getAttribute('data-srcset');
            if (lazySrcset && !img.srcset) {
              img.srcset = lazySrcset;
            }
          }
          
          // فك صور <picture><source> أيضاً
          var sources = document.querySelectorAll('picture source[data-srcset]');
          for (var s = 0; s < sources.length; s++) {
            var ds = sources[s].getAttribute('data-srcset');
            if (ds && !sources[s].srcset) {
              sources[s].srcset = ds;
              forced++;
            }
          }
          
          return forced;
        }
        
        // ═══ دالة: عدّ الصور ذات src حقيقي ═══
        function countValidImages() {
          var allImgs = document.querySelectorAll('img');
          var count = 0;
          for (var i = 0; i < allImgs.length; i++) {
            var src = allImgs[i].src || '';
            if (src.length > 10 && src.indexOf('data:') !== 0) count++;
          }
          return count;
        }
        
        // ═══ دالة فلترة سريعة: استبعاد الصور الصغيرة والأيقونات والإعلانات لانتظار تحميل الفصل فقط ═══
        function isMangaImage(img) {
          var src = img.src || '';
          if (!src || src.indexOf('data:') === 0 || src.length < 10) return false;
          var lower = src.toLowerCase();
          var exclude = ['icon', 'logo', 'avatar', 'badge', 'arrow', 'btn', 'button', 'emoji', 'favicon', 'placeholder', 'sns-', 'social', 'google-play', 'app-store', 'banner', 'ad-'];
          for (var i = 0; i < exclude.length; i++) {
            if (lower.indexOf(exclude[i]) !== -1) return false;
          }
          return true;
        }

        // ═══ دالة: انتظار تحميل الصور ═══
        async function waitForImagesLoaded(timeoutMs) {
          var start = Date.now();
          while (Date.now() - start < timeoutMs) {
            var allImgs = document.querySelectorAll('img');
            var pending = 0;
            for (var i = 0; i < allImgs.length; i++) {
              if (!isMangaImage(allImgs[i])) continue;
              if (!allImgs[i].complete) pending++;
            }
            if (pending === 0) return true;
            await new Promise(function(r) { setTimeout(r, 150); });
          }
          return false;
        }

        // ═══════════════════════════════════════════
        // المرحلة 1: تمرير سريع للأسفل لتوسيع DOM
        // ═══════════════════════════════════════════
        console.log('[MangaLens] Phase 1: Fast scroll to expand DOM');
        var prevHeight = 0;
        var maxRounds = 3;
        for (var round = 0; round < maxRounds; round++) {
          var pageHeight = document.body.scrollHeight;
          if (pageHeight <= prevHeight && round >= 1) break;
          prevHeight = pageHeight;
          
          var step = Math.floor(window.innerHeight * 3.5);
          for (var pos = 0; pos < pageHeight; pos += step) {
            window.scrollTo(0, pos);
            await new Promise(function(r) { setTimeout(r, 35); });
          }
          window.scrollTo(0, document.body.scrollHeight);
          forceLazyLoad();
          await new Promise(function(r) { setTimeout(r, 300); });
        }
        
        console.log('[MangaLens] Phase 1 done. Height: ' + document.body.scrollHeight + ', imgs: ' + document.querySelectorAll('img').length);

        // ═══════════════════════════════════════════
        // المرحلة 2: التمرير لكل صورة (يُفعّل IntersectionObserver)
        // ═══════════════════════════════════════════
        console.log('[MangaLens] Phase 2: scrollIntoView for each image');
        window.scrollTo(0, 0);
        await new Promise(function(r) { setTimeout(r, 100); });
        
        var allImgs = document.querySelectorAll('img');
        for (var i = 0; i < allImgs.length; i++) {
          try { 
            allImgs[i].scrollIntoView({ behavior: 'instant', block: 'center' }); 
          } catch(e) { 
            allImgs[i].scrollIntoView(true); 
          }
          forceLazyLoad();
          if (i % 10 === 0) {
            await new Promise(function(r) { setTimeout(r, 40); });
          }
        }
        
        // فحص صور جديدة ظهرت بعد Phase 2
        var newImgs = document.querySelectorAll('img');
        if (newImgs.length > allImgs.length) {
          console.log('[MangaLens] New images appeared after phase 2: ' + (newImgs.length - allImgs.length));
          for (var i = allImgs.length; i < newImgs.length; i++) {
            try { newImgs[i].scrollIntoView({ behavior: 'instant', block: 'center' }); } catch(e) {}
            forceLazyLoad();
            await new Promise(function(r) { setTimeout(r, 40); });
          }
        }
        
        console.log('[MangaLens] Phase 2 done. Total imgs: ' + document.querySelectorAll('img').length);

        // ═══════════════════════════════════════════
        // المرحلة 3: انتظار استقرار عدد الصور
        // ═══════════════════════════════════════════
        console.log('[MangaLens] Phase 3: Waiting for stable image count...');
        var stableCount = document.querySelectorAll('img').length;
        var stableTime = 0;
        var elapsed = 0;
        var maxWait = 3000;
        
        while (elapsed < maxWait) {
          await new Promise(function(r) { setTimeout(r, 200); });
          elapsed += 200;
          forceLazyLoad();
          var currentCount = document.querySelectorAll('img').length;
          if (currentCount === stableCount) {
            stableTime += 200;
            if (stableTime >= 800) break;
          } else {
            console.log('[MangaLens] Image count changed: ' + stableCount + ' -> ' + currentCount);
            stableCount = currentCount;
            stableTime = 0;
          }
        }

        // ═══════════════════════════════════════════
        // المرحلة 4: فرض تحميل نهائي وانتظار اكتمال الصور
        // ═══════════════════════════════════════════
        forceLazyLoad();
        var allLoaded = await waitForImagesLoaded(3000);
        console.log('[MangaLens] Phase 4: All loaded = ' + allLoaded);
        
        window.scrollTo(0, 0);
        await new Promise(function(r) { setTimeout(r, 200); });
        
        var finalTotal = document.querySelectorAll('img').length;
        var validCount = countValidImages();
        
        console.log('[MangaLens] === Scroll Complete === Total: ' + finalTotal + ', Valid: ' + validCount);
        
        if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
          window.flutter_inappwebview.callHandler('scrollComplete', validCount, finalTotal);
        }
      })();
    ''');

    // انتظار الاكتمال أو timeout بعد 12 ثانية
    try {
      await completer.future.timeout(const Duration(seconds: 12));
    } catch (_) {
      debugPrint('⚠️ Auto-scroll timed out after 12s, proceeding with extraction');
    }

    await Future.delayed(const Duration(milliseconds: 300));
  }

  // ═══════════════════════════════════════════════════════════════
  //  الخطوة 4: استخراج DOM المحسّن (الطبقة 2)
  // ═══════════════════════════════════════════════════════════════

  static Future<List<ScrapedImage>> _extractDomImages(
      InAppWebViewController controller) async {
    try {
      final result = await controller.evaluateJavascript(source: '''
        (function() {
          var adDomains = ${_adDomains.map((d) => '"$d"').toList()};
          var viewportWidth = window.innerWidth || document.documentElement.clientWidth || 360;
          
          // ═══ دالة: حساب الموقع الرأسي الحقيقي ═══
          function getOffsetTop(el) {
            var top = 0;
            var current = el;
            while (current) {
              top += current.offsetTop || 0;
              current = current.offsetParent;
            }
            return top;
          }
          
          // ═══ دالة: CSS order ═══
          function getCssOrder(el) {
            try {
              var style = window.getComputedStyle(el);
              return parseInt(style.order) || 0;
            } catch(e) { return 0; }
          }
          
          // ═══ دالة: استخراج رقم الصفحة من URL ═══
          function extractPageNumber(url) {
            var patterns = [
              /[/_\\-](\\d{1,4})\\.(jpg|jpeg|png|webp|avif|gif|bmp)/i,
              /page[/_\\-]?(\\d{1,4})/i,
              /img[/_\\-]?(\\d{1,4})/i,
              /[/_\\-]p(\\d{1,4})\\./i,
              /\\/(\\d{1,4})(?:\\?|\$)/
            ];
            for (var p = 0; p < patterns.length; p++) {
              var m = url.match(patterns[p]);
              if (m) return parseInt(m[1]);
            }
            return -1;
          }
          
          // ═══ دالة: هل هذه صورة مانغا/فصل (وليست غلاف أو أيقونة)؟ ═══
          function isMangaImage(img) {
            var src = img.src || '';
            if (!src || src.indexOf('data:') === 0 || src === '' || src === window.location.href) {
              var lazyAttrs = ['data-src', 'data-lazy-src', 'data-original', 'data-image',
                'data-lazy', 'data-url', 'data-echo', 'data-load', 'data-img',
                'data-real-src', 'data-aload', 'data-delayed-url', 'data-cfsrc',
                'data-source', 'data-hi-res-src', 'lazysrc', 'origsrc'];
              for (var a = 0; a < lazyAttrs.length; a++) {
                var val = img.getAttribute(lazyAttrs[a]);
                if (val && val.length > 10 && val.indexOf('data:') !== 0) {
                  src = val;
                  break;
                }
              }
            }
            
            if (!src || src.length < 10 || src.indexOf('data:') === 0) return null;
            
            var srcLower = src.toLowerCase();
            
            // ═══ استبعاد URL: أنماط الأغلفة والمصغرات ═══
            var coverPatterns = ['cover', 'thumbnail', '/thumb/', 'poster', 'profile',
              'avatar', 'badge', 'medal', 'rank', 'grade', 'sns-', 'social',
              'header-', 'footer-', 'nav-', 'arrow-', 'open-graph',
              'app-store', 'google-play', 'download-', 'qr-code',
              'metadata', 'placeholder', 'default_', 'empty-state',
              'manta-logo', 'search_', 'my-series_'];
            for (var cp = 0; cp < coverPatterns.length; cp++) {
              if (srcLower.indexOf(coverPatterns[cp]) !== -1) return null;
            }
            
            // ═══ استبعاد: أحجام صغيرة في URL (12x12, 40x40, 100x100 الخ) ═══
            var sizeInUrl = srcLower.match(/(\\d+)x(\\d+)/);
            if (sizeInUrl) {
              var urlW = parseInt(sizeInUrl[1]);
              var urlH = parseInt(sizeInUrl[2]);
              if (urlW < 200 || urlH < 200) return null;
            }
            
            // ═══ استبعاد: إعلانات ═══
            for (var d = 0; d < adDomains.length; d++) { 
              if (srcLower.indexOf(adDomains[d]) !== -1) return null; 
            }
            
            // ═══ استبعاد: عناصر واجهة ═══
            var junk = ['logo', 'banner', 'icon', 'sponsor', 'button', 
              'captcha', 'pixel', 'tracking', 'analytics', '1x1', 'transparent', 
              'widget', 'favicon', 'emoji'];
            for (var j = 0; j < junk.length; j++) { 
              if (srcLower.indexOf(junk[j]) !== -1) return null; 
            }
            
            // ═══ فحص الحجم المعروض ═══
            var w = img.naturalWidth || img.width || 0;
            var h = img.naturalHeight || img.height || 0;
            var rect = img.getBoundingClientRect();
            var displayW = Math.max(w, rect.width);
            var displayH = Math.max(h, rect.height);
            
            if (displayW > 0 && displayH > 0 && displayW < 200 && displayH < 200) return null;
            
            // ═══ فحص العرض النسبي للشاشة (حد أدنى مرن) ═══
            // نستخدم حد منخفض هنا (15%) ونترك الفلترة الذكية التكيّفية تقرر لاحقاً
            var widthRatio = rect.width / viewportWidth;
            if (rect.width > 0 && widthRatio < 0.15) return null;
            
            // ═══ استبعاد: trackers ═══
            var trackers = ['/rec?', '/imp', 'beacon', 'collect', 'event?', 'log?'];
            for (var t = 0; t < trackers.length; t++) { 
              if (srcLower.indexOf(trackers[t]) !== -1) return null; 
            }
            
            // ═══ فحص الحاويات الأبوية ═══
            var parent = img.parentElement;
            var depth = 0;
            while (parent && depth < 4) {
              var pid = (parent.id || '').toLowerCase();
              var pcls = (typeof parent.className === 'string') ? parent.className.toLowerCase() : '';
              var excludePattern = /\\b(ad-wrap|ad-box|ad-container|banner-ad|popunder|native-ad|ad_widget|live-chat|social-share|comment-box|comment-list|comments-area|recommend|related|similar|footer|header|navigation|sidebar|nav-bar)\\b/;
              if (excludePattern.test(pid) || excludePattern.test(pcls)) return null;
              parent = parent.parentElement;
              depth++;
            }
            
            return src;
          }
          
          // ═══════════════════════════════════════════
          // المرحلة 1: البحث عن حاوية قارئ معروفة
          // ═══════════════════════════════════════════
          var readerSelectors = [
            '#readerarea', '.reading-content', '.chapter-content', '.manga-reader',
            '#chapter-content', '.reader-area', '#image-container', '.chapter_img',
            '.image_list', '#chapter_images', '.chapter-images', '.page-chapter',
            '.wp-manga-chapter-img', '.panel-read-story',
            '#viewer', '.viewer-cnt', '#comic-reader', '.comic-reader',
            '.chapter-c', '#chapter_body', '.container-chapter-reader',
            '#content-chapter', '.content-chapter', '.chapter-reading',
            '.read-container', '#manga-reading', '.manga-content',
            '.chapter-detail', '#chapter-detail', '.chapter-main'
          ];
          
          var container = null;
          for (var s = 0; s < readerSelectors.length; s++) {
            var el = document.querySelector(readerSelectors[s]);
            if (el) {
              var imgs = el.querySelectorAll('img');
              var mangaCount = 0;
              for (var i = 0; i < imgs.length; i++) {
                if (isMangaImage(imgs[i])) mangaCount++;
              }
              if (mangaCount >= 3) {
                container = el;
                console.log('[MangaLens] ✅ Found reader container: ' + readerSelectors[s] + ' with ' + mangaCount + ' manga images');
                break;
              }
            }
          }
          
          // ═══════════════════════════════════════════
          // المرحلة 2: اكتشاف تلقائي محسّن
          // ═══════════════════════════════════════════
          if (!container) {
            console.log('[MangaLens] No known reader container. Auto-detecting...');
            
            var allImgs = document.querySelectorAll('img');
            var parentScores = new Map();
            
            for (var i = 0; i < allImgs.length; i++) {
              var src = isMangaImage(allImgs[i]);
              if (!src) continue;
              
              var p = allImgs[i].parentElement;
              var d = 0;
              while (p && d < 8) {
                var tag = p.tagName.toLowerCase();
                if (tag === 'div' || tag === 'article' || tag === 'section' || tag === 'main') {
                  var pImgs = p.querySelectorAll('img');
                  var pMangaCount = 0;
                  var pWideCount = 0;
                  
                  for (var j = 0; j < pImgs.length; j++) {
                    if (isMangaImage(pImgs[j])) {
                      pMangaCount++;
                      var pRect = pImgs[j].getBoundingClientRect();
                      if (pRect.width > viewportWidth * 0.5) pWideCount++;
                    }
                  }
                  
                  if (pMangaCount >= 3) {
                    var purity = pMangaCount / Math.max(pImgs.length, 1);
                    var wideRatio = pWideCount / Math.max(pMangaCount, 1);
                    var score = pMangaCount * purity * (1 + wideRatio);
                    
                    if (!parentScores.has(p) || parentScores.get(p).score < score) {
                      parentScores.set(p, { score: score, count: pMangaCount, total: pImgs.length, wideRatio: wideRatio });
                    }
                  }
                }
                p = p.parentElement;
                d++;
              }
            }
            
            var bestContainer = null;
            var bestScore = 0;
            parentScores.forEach(function(info, el) {
              if (info.score > bestScore) {
                bestScore = info.score;
                bestContainer = el;
              }
            });
            
            if (bestContainer) {
              container = bestContainer;
              var info = parentScores.get(bestContainer);
              console.log('[MangaLens] ✅ Auto-detected container | manga: ' + info.count + '/' + info.total + ' | wideRatio: ' + info.wideRatio.toFixed(2) + ' | score: ' + bestScore.toFixed(2));
            }
          }
          
          // ═══════════════════════════════════════════
          // المرحلة 3: استخراج صور <img> من الحاوية
          // ═══════════════════════════════════════════
          var targetImgs = container ? container.querySelectorAll('img') : document.querySelectorAll('img');
          var candidates = [];
          var domIndex = 0;
          
          for (var i = 0; i < targetImgs.length; i++) {
            var src = isMangaImage(targetImgs[i]);
            if (src) {
              var imgRect = targetImgs[i].getBoundingClientRect();
              candidates.push({
                src: src,
                domIndex: domIndex++,
                offsetTop: getOffsetTop(targetImgs[i]),
                cssOrder: getCssOrder(targetImgs[i].parentElement || targetImgs[i]),
                pageNumber: extractPageNumber(src),
                displayWidth: Math.max(imgRect.width, targetImgs[i].naturalWidth || 0),
                displayHeight: Math.max(imgRect.height, targetImgs[i].naturalHeight || 0)
              });
            }
          }
          
          // ═══════════════════════════════════════════
          // المرحلة 4: استخراج من <picture><source> 
          // ═══════════════════════════════════════════
          var pictureTarget = container || document;
          var pictures = pictureTarget.querySelectorAll('picture');
          for (var p = 0; p < pictures.length; p++) {
            var sources = pictures[p].querySelectorAll('source');
            for (var s = 0; s < sources.length; s++) {
              var srcset = sources[s].srcset || sources[s].getAttribute('data-srcset') || '';
              if (srcset) {
                var bestSrc = srcset.split(',').pop().trim().split(' ')[0];
                if (bestSrc && bestSrc.length > 10) {
                  var dup = false;
                  for (var c = 0; c < candidates.length; c++) {
                    if (candidates[c].src === bestSrc) { dup = true; break; }
                  }
                  if (!dup) {
                    candidates.push({
                      src: bestSrc,
                      domIndex: domIndex++,
                      offsetTop: getOffsetTop(pictures[p]),
                      cssOrder: getCssOrder(pictures[p]),
                      pageNumber: extractPageNumber(bestSrc),
                      displayWidth: 0,
                      displayHeight: 0
                    });
                  }
                }
              }
            }
          }
          
          // ═══════════════════════════════════════════
          // المرحلة 5: استخراج من background-image
          // ═══════════════════════════════════════════
          var bgTarget = container || document;
          var bgEls = bgTarget.querySelectorAll('[style*="background-image"]');
          for (var b = 0; b < bgEls.length; b++) {
            try {
              var bgMatch = bgEls[b].style.backgroundImage.match(/url\\(['"]?(.*?)['"]?\\)/);
              if (bgMatch && bgMatch[1] && bgMatch[1].length > 10 && bgMatch[1].indexOf('data:') !== 0) {
                var bgSrc = bgMatch[1];
                // تأكد أنه غير مكرر
                var bgDup = false;
                for (var c = 0; c < candidates.length; c++) {
                  if (candidates[c].src === bgSrc) { bgDup = true; break; }
                }
                if (!bgDup) {
                  // فحص الإعلانات
                  var bgLower = bgSrc.toLowerCase();
                  var isAd = false;
                  for (var ad = 0; ad < adDomains.length; ad++) {
                    if (bgLower.indexOf(adDomains[ad]) !== -1) { isAd = true; break; }
                  }
                  if (!isAd) {
                    candidates.push({
                      src: bgSrc,
                      domIndex: domIndex++,
                      offsetTop: getOffsetTop(bgEls[b]),
                      cssOrder: getCssOrder(bgEls[b]),
                      pageNumber: extractPageNumber(bgSrc)
                    });
                  }
                }
              }
            } catch(e) {}
          }
          
          console.log('[MangaLens] After container filter: ' + candidates.length + ' images from ' + (container ? 'detected container' : 'full page'));
          
          // ═══════════════════════════════════════════
          // المرحلة 6: فلترة بالنطاق المهيمن
          // ═══════════════════════════════════════════
          if (candidates.length > 0) {
            var domainCounts = {};
            for (var i = 0; i < candidates.length; i++) {
              try {
                var url = new URL(candidates[i].src);
                var parts = url.hostname.split('.');
                var domain = parts.length >= 2 ? parts[parts.length - 2] + '.' + parts[parts.length - 1] : url.hostname;
                domainCounts[domain] = (domainCounts[domain] || 0) + 1;
              } catch(e) {}
            }
            
            var dominantDomain = '';
            var maxCount = 0;
            for (var domain in domainCounts) {
              if (domainCounts[domain] > maxCount) {
                maxCount = domainCounts[domain];
                dominantDomain = domain;
              }
            }
            
            console.log('[MangaLens] Domain distribution: ' + JSON.stringify(domainCounts) + ' -> dominant: ' + dominantDomain);
            
            if (dominantDomain && maxCount >= candidates.length * 0.5 && candidates.length > 5) {
              var filtered = [];
              for (var i = 0; i < candidates.length; i++) {
                try {
                  var url = new URL(candidates[i].src);
                  if (url.hostname.indexOf(dominantDomain) !== -1) {
                    filtered.push(candidates[i]);
                  }
                } catch(e) { filtered.push(candidates[i]); }
              }
              console.log('[MangaLens] Domain filter: ' + candidates.length + ' -> ' + filtered.length);
              candidates = filtered;
            }
          }
          
          // ═══════════════════════════════════════════
          // المرحلة 7: نظام الفلترة الذكي التكيّفي
          // يحلل الصور أولاً ثم يقرر العتبات ديناميكياً
          // ═══════════════════════════════════════════
          if (candidates.length > 3) {
            console.log('[MangaLens] 🧠 Starting adaptive analysis on ' + candidates.length + ' candidates...');
            
            // ── الخطوة أ: تحليل توزيع العرض ──
            var widthGroups = {};
            var allWidths = [];
            for (var i = 0; i < candidates.length; i++) {
              var cw = candidates[i].displayWidth || 0;
              if (cw <= 0) continue;
              allWidths.push(cw);
              var bucket = Math.round(cw / 30) * 30; // تجميع بدقة 30px
              if (!widthGroups[bucket]) widthGroups[bucket] = [];
              widthGroups[bucket].push(i); // حفظ الفهرس
            }
            
            // إيجاد مجموعة العرض المهيمنة (= عرض صور الفصل)
            var dominantWidthBucket = 0;
            var dominantWidthCount = 0;
            for (var bucket in widthGroups) {
              if (widthGroups[bucket].length > dominantWidthCount) {
                dominantWidthCount = widthGroups[bucket].length;
                dominantWidthBucket = parseInt(bucket);
              }
            }
            
            // العتبة التكيّفية = نصف عرض المجموعة المهيمنة
            // هذا يعمل سواء كانت الصور 100% أو 50% أو حتى 20% من الشاشة
            var adaptiveWidthThreshold = dominantWidthBucket > 0 ? dominantWidthBucket * 0.5 : viewportWidth * 0.2;
            console.log('[MangaLens] 🧠 Dominant width: ' + dominantWidthBucket + 'px (count: ' + dominantWidthCount + '), adaptive threshold: ' + adaptiveWidthThreshold.toFixed(0) + 'px');
            
            // ── الخطوة ب: تحليل توزيع مسارات URL ──
            var pathGroups = {};
            for (var i = 0; i < candidates.length; i++) {
              try {
                var imgUrl = new URL(candidates[i].src);
                var pathParts = imgUrl.pathname.split('/');
                // استخدام مستويات مختلفة من المسار للتجميع
                var pathKey = pathParts.slice(0, Math.min(pathParts.length - 1, 4)).join('/');
                if (!pathGroups[pathKey]) pathGroups[pathKey] = [];
                pathGroups[pathKey].push(i);
              } catch(e) {}
            }
            
            var dominantPath = '';
            var dominantPathCount = 0;
            for (var pk in pathGroups) {
              if (pathGroups[pk].length > dominantPathCount) {
                dominantPathCount = pathGroups[pk].length;
                dominantPath = pk;
              }
            }
            console.log('[MangaLens] 🧠 Dominant path: ' + dominantPath + ' (count: ' + dominantPathCount + '/' + candidates.length + ')');
            
            // ── الخطوة ج: تسجيل النقاط لكل صورة ──
            var scored = [];
            for (var i = 0; i < candidates.length; i++) {
              var score = 0;
              var cw = candidates[i].displayWidth || 0;
              var ch = candidates[i].displayHeight || 0;
              
              // معيار 1: تطابق العرض مع المجموعة المهيمنة (+40)
              if (cw > 0 && dominantWidthBucket > 0) {
                if (Math.abs(cw - dominantWidthBucket) < 80) score += 40;
                else if (cw >= adaptiveWidthThreshold) score += 15;
              } else if (cw <= 0) {
                score += 20; // صور بدون عرض معروف (lazy) تحصل على نقاط متوسطة
              }
              
              // معيار 2: تطابق مسار URL (+30)
              if (dominantPath && dominantPathCount >= 3) {
                try {
                  var imgUrl = new URL(candidates[i].src);
                  var pp = imgUrl.pathname.split('/').slice(0, Math.min(imgUrl.pathname.split('/').length - 1, 4)).join('/');
                  if (pp === dominantPath) score += 30;
                } catch(e) {}
              } else {
                score += 15; // لا يوجد مسار مهيمن واضح
              }
              
              // معيار 3: الحجم الكلي (+20)
              var area = cw * ch;
              if (area > 50000) score += 20;
              else if (area > 20000) score += 10;
              else if (cw <= 0) score += 10; // حجم غير معروف
              
              // معيار 4: ليست في حاوية مستبعدة (+10 مجاناً — فلترت سابقاً)
              score += 10;
              
              scored.push({ index: i, score: score });
            }
            
            // ── الخطوة د: تحديد عتبة القبول التكيّفية ──
            // نقبل الصور بنقاط >= 40 (من 100)
            var threshold = 40;
            var accepted = scored.filter(function(s) { return s.score >= threshold; });
            
            // إذا القبول أعطى نتائج معقولة (>= 3 صور)
            if (accepted.length >= 3) {
              var adaptiveFiltered = accepted.map(function(s) { return candidates[s.index]; });
              console.log('[MangaLens] 🧠 Adaptive filter: ' + candidates.length + ' -> ' + adaptiveFiltered.length + ' (threshold: ' + threshold + ')');
              candidates = adaptiveFiltered;
            } else {
              console.log('[MangaLens] 🧠 Adaptive filter skipped (only ' + accepted.length + ' passed), keeping all ' + candidates.length);
            }
          }
          
          console.log('[MangaLens] ✅ DOM extraction: ' + candidates.length + ' chapter images');
          return JSON.stringify(candidates);
        })();
      ''');

      if (result == null || result == 'null' || result == '[]') {
        return [];
      }

      return _parseDomResults(result.toString());
    } catch (e) {
      debugPrint('❌ DOM extraction error: $e');
      return [];
    }
  }

  // ═══════════════════════════════════════════════════════════════
  //  الخطوة 5: تحليل نتائج DOM إلى ScrapedImage
  // ═══════════════════════════════════════════════════════════════

  static List<ScrapedImage> _parseDomResults(String raw) {
    try {
      String cleaned = raw;
      if (cleaned.startsWith('"') && cleaned.endsWith('"')) {
        cleaned = cleaned.substring(1, cleaned.length - 1);
        cleaned = cleaned.replaceAll(r'\"', '"');
      }

      final List<dynamic> list = json.decode(cleaned);
      return list.map((item) {
        final map = item as Map<String, dynamic>;
        String src = (map['src'] as String?) ?? '';

        // تطبيع الرابط
        if (src.startsWith('//')) src = 'https:$src';

        return ScrapedImage(
          url: src,
          source: ImageSource.dom,
          domIndex: (map['domIndex'] as int?) ?? 0,
          offsetTop: ((map['offsetTop'] as num?) ?? 0).toDouble(),
          cssOrder: (map['cssOrder'] as int?) ?? 0,
          pageNumber: (map['pageNumber'] as int?) ?? -1,
        );
      }).where((img) => img.url.isNotEmpty && (img.url.startsWith('http') || img.url.startsWith('data:image'))).toList();
    } catch (e) {
      debugPrint('Parse DOM results error: $e');
      // Fallback: محاولة تحليل كمصفوفة نصية بسيطة
      final urls = _parseImageUrls(raw);
      return urls
          .asMap()
          .entries
          .map((entry) => ScrapedImage(
                url: entry.value,
                source: ImageSource.dom,
                domIndex: entry.key,
              ))
          .toList();
    }
  }

  // ═══════════════════════════════════════════════════════════════
  //  الخطوة 6: دمج المصادر الثلاثة وإزالة التكرار
  // ═══════════════════════════════════════════════════════════════

  static List<ScrapedImage> _mergeAndDeduplicate({
    required List<ScrapedImage> domImages,
    required List<String> networkImages,
    required List<String> mutationImages,
  }) {
    final Map<String, ScrapedImage> merged = {};

    // الأولوية 1: DOM images (تحتوي معلومات الموقع والترتيب)
    for (final img in domImages) {
      final normalized = _normalizeUrl(img.url);
      if (normalized.isNotEmpty) {
        merged[normalized] = img;
      }
    }

    // الأولوية 2: Network images (تكمل ما فاته DOM)
    for (int i = 0; i < networkImages.length; i++) {
      final url = networkImages[i];
      final normalized = _normalizeUrl(url);
      if (normalized.isNotEmpty && !merged.containsKey(normalized)) {
        merged[normalized] = ScrapedImage(
          url: url.startsWith('//') ? 'https:$url' : url,
          source: ImageSource.network,
          networkOrder: i,
          pageNumber: _extractPageNumberDart(url),
        );
      }
    }

    // الأولوية 3: MutationObserver images
    for (int i = 0; i < mutationImages.length; i++) {
      final url = mutationImages[i];
      final normalized = _normalizeUrl(url);
      if (normalized.isNotEmpty && !merged.containsKey(normalized)) {
        merged[normalized] = ScrapedImage(
          url: url.startsWith('//') ? 'https:$url' : url,
          source: ImageSource.mutation,
          networkOrder: i,
          pageNumber: _extractPageNumberDart(url),
        );
      }
    }

    return merged.values.toList();
  }

  /// تطبيع URL لمقارنة صحيحة (إزالة بروتوكول + query params غير ضرورية)
  static String _normalizeUrl(String url) {
    if (url.isEmpty) return '';
    try {
      String normalized = url;
      // إزالة البروتوكول للمقارنة
      normalized = normalized.replaceFirst(RegExp(r'^https?://'), '');
      normalized = normalized.replaceFirst(RegExp(r'^//'), '');
      // إزالة trailing slash
      if (normalized.endsWith('/')) {
        normalized = normalized.substring(0, normalized.length - 1);
      }
      return normalized;
    } catch (_) {
      return url;
    }
  }

  /// استخراج رقم الصفحة من URL (Dart side)
  static int _extractPageNumberDart(String url) {
    final patterns = [
      RegExp(r'[/_\-](\d{1,4})\.(jpg|jpeg|png|webp|avif|gif|bmp)', caseSensitive: false),
      RegExp(r'page[/_\-]?(\d{1,4})', caseSensitive: false),
      RegExp(r'img[/_\-]?(\d{1,4})', caseSensitive: false),
      RegExp(r'[/_\-]p(\d{1,4})\.', caseSensitive: false),
      RegExp(r'/(\d{1,4})(?:\?|$)'),
    ];
    for (final p in patterns) {
      final m = p.firstMatch(url);
      if (m != null) return int.tryParse(m.group(1) ?? '') ?? -1;
    }
    return -1;
  }

  // ═══════════════════════════════════════════════════════════════
  //  الخطوة 7: الترتيب الذكي متعدد الطبقات
  // ═══════════════════════════════════════════════════════════════

  static List<ScrapedImage> _smartSort(List<ScrapedImage> images) {
    if (images.isEmpty) return images;

    // ═══ استخراج رقم تسلسلي من URL لكل صورة ═══
    // هذا هو المعيار الأكثر موثوقية لأن CDNs تسمي الصور بأرقام تسلسلية
    int extractUrlSequence(String url) {
      // محاولة 1: رقم الصفحة المعروف
      final pageNum = _extractPageNumberDart(url);
      if (pageNum >= 0) return pageNum;
      
      // محاولة 2: آخر رقم في مسار URL (قبل الامتداد)
      // مثال: .../chapter1/015.jpg → 15
      // مثال: .../images/cut_1689234567_42.webp → 42
      try {
        final uri = Uri.parse(url);
        final path = uri.path;
        // استخراج كل الأرقام من المسار
        final numbers = RegExp(r'(\d+)').allMatches(path).map((m) => int.parse(m.group(1)!)).toList();
        if (numbers.isNotEmpty) {
          // آخر رقم في المسار عادة هو رقم الصورة التسلسلي
          return numbers.last;
        }
      } catch (_) {}
      
      return -1;
    }

    // حساب رقم تسلسلي لكل صورة
    final withSequence = images.map((img) {
      final seq = extractUrlSequence(img.url);
      return MapEntry(img, seq);
    }).toList();

    // كم صورة لها رقم تسلسلي؟
    final withNums = withSequence.where((e) => e.value >= 0).length;
    final numRatio = withNums / images.length;

    if (numRatio > 0.5) {
      // ═══ الترتيب بأرقام URL (الأكثر موثوقية) ═══
      debugPrint('📊 Sorting by URL sequence numbers (${(numRatio * 100).toStringAsFixed(0)}% have nums)');
      
      // فحص: هل الأرقام فريدة أم مكررة؟
      final seqSet = withSequence.where((e) => e.value >= 0).map((e) => e.value).toSet();
      final hasUniqueNums = seqSet.length > withNums * 0.8; // >80% فريدة
      
      if (hasUniqueNums) {
        withSequence.sort((a, b) {
          if (a.value >= 0 && b.value >= 0) {
            return a.value.compareTo(b.value);
          }
          // الصور بدون رقم تسلسلي → تبقى بترتيبها النسبي
          if (a.value >= 0) return -1;
          if (b.value >= 0) return 1;
          return images.indexOf(a.key).compareTo(images.indexOf(b.key));
        });
        return withSequence.map((e) => e.key).toList();
      }
    }

    // ═══ الترتيب بموقع DOM (للصور التي لها offsetTop) ═══
    final domImages = images.where((img) => img.source == ImageSource.dom).toList();
    final moImages = images.where((img) => img.source != ImageSource.dom).toList();
    
    if (domImages.length > moImages.length) {
      debugPrint('📊 Sorting by DOM position (${domImages.length} DOM + ${moImages.length} MO)');
      
      // ترتيب DOM بـ offsetTop/domIndex
      domImages.sort((a, b) {
        if (a.cssOrder != b.cssOrder) return a.cssOrder.compareTo(b.cssOrder);
        if ((a.offsetTop - b.offsetTop).abs() > 10) return a.offsetTop.compareTo(b.offsetTop);
        return a.domIndex.compareTo(b.domIndex);
      });
      
      // صور MO: نضعها حسب رقمها التسلسلي بين صور DOM
      if (moImages.isNotEmpty) {
        final result = <ScrapedImage>[...domImages];
        for (final mo in moImages) {
          final moSeq = extractUrlSequence(mo.url);
          if (moSeq >= 0) {
            // إيجاد المكان الصحيح بين صور DOM
            int insertAt = result.length;
            for (int i = 0; i < result.length; i++) {
              final domSeq = extractUrlSequence(result[i].url);
              if (domSeq >= 0 && domSeq > moSeq) {
                insertAt = i;
                break;
              }
            }
            result.insert(insertAt, mo);
          } else {
            result.add(mo);
          }
        }
        return result;
      }
      
      return domImages;
    }

    // ═══ Fallback: ترتيب حسب ترتيب الالتقاط ═══
    debugPrint('📊 Sorting by capture order (fallback)');
    return images;
  }

  // ═══════════════════════════════════════════════════════════════
  //  أدوات مساعدة
  // ═══════════════════════════════════════════════════════════════

  /// تحليل روابط الصور من JSON
  static List<String> _parseImageUrls(String raw) {
    try {
      String cleaned = raw;
      if (cleaned.startsWith('"') && cleaned.endsWith('"')) {
        cleaned = cleaned.substring(1, cleaned.length - 1);
        cleaned = cleaned.replaceAll(r'\"', '"');
      }
      // تحليل المصفوفة يدوياً
      cleaned = cleaned.replaceAll('[', '').replaceAll(']', '');
      if (cleaned.isEmpty) return [];

      return cleaned
          .split(',')
          .map((s) => s.trim().replaceAll('"', '').replaceAll("'", ''))
          .where((s) => s.isNotEmpty && (s.startsWith('http') || s.startsWith('//')))
          .map((s) => s.startsWith('//') ? 'https:$s' : s)
          .toList();
    } catch (e) {
      debugPrint('Parse error: $e');
      return [];
    }
  }

  /// تحميل صورة واحدة مباشرة من المتصفح باستخدام fetch
  /// هذا يتجاوز حماية Hotlink لأن الطلب يأتي من نفس جلسة المتصفح
  static Future<Uint8List?> downloadImageViaWebView(
      InAppWebViewController controller, String imageUrl) async {
    try {
      final result = await controller.evaluateJavascript(source: '''
        (async function() {
          try {
            // محاولة أولى: استخدام fetch مع كوكيز الجلسة
            var response = await fetch('$imageUrl', { 
              credentials: 'include',
              headers: { 'Accept': 'image/*,*/*' }
            });
            if (!response.ok) return 'ERROR:' + response.status;
            var blob = await response.blob();
            return new Promise(function(resolve) {
              var reader = new FileReader();
              reader.onload = function() { resolve(reader.result); };
              reader.onerror = function() { resolve('ERROR:FileReader'); };
              reader.readAsDataURL(blob);
            });
          } catch(e) {
            // محاولة ثانية: رسم الصورة على canvas (fallback)
            try {
              var img = document.querySelector('img[src="$imageUrl"]');
              if (!img) {
                img = document.querySelector('img[data-src="$imageUrl"]');
              }
              if (img && img.naturalWidth > 0) {
                var canvas = document.createElement('canvas');
                canvas.width = img.naturalWidth;
                canvas.height = img.naturalHeight;
                var ctx = canvas.getContext('2d');
                ctx.drawImage(img, 0, 0);
                return canvas.toDataURL('image/png');
              }
              return 'ERROR:' + e.message;
            } catch(e2) {
              return 'ERROR:' + e2.message;
            }
          }
        })();
      ''');

      if (result == null || result.toString().startsWith('ERROR:')) {
        debugPrint('⚠️ WebView fetch failed for: $imageUrl → $result');
        return null;
      }

      // تحويل data:image/...;base64,XXXX إلى Uint8List
      final String dataUrl = result.toString();
      final commaIndex = dataUrl.indexOf(',');
      if (commaIndex == -1) return null;

      final base64Data = dataUrl.substring(commaIndex + 1);
      return base64Decode(base64Data);
    } catch (e) {
      debugPrint('❌ WebView download error: $e');
      return null;
    }
  }
}
