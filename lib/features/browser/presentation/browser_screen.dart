import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/models/manga_history.dart';
import '../../../core/services/history_service.dart';
import '../../../core/providers/navigation_provider.dart';
import '../data/adblock_rules.dart';
import '../providers/browser_provider.dart';
import '../../reader/data/image_scraper_service.dart';
import '../../reader/data/chapter_cache_service.dart';
import '../../reader/providers/reader_provider.dart';
import '../../reader/presentation/chapter_preview_screen.dart';
import '../../settings/providers/settings_provider.dart';
import 'browser_controls.dart';
import 'url_bar.dart';

/// الشاشة الرئيسية للمتصفح المدمج
/// Main browser screen with Smart Scraper
class BrowserScreen extends ConsumerStatefulWidget {
  final String initialUrl;
  const BrowserScreen({super.key, required this.initialUrl});

  @override
  ConsumerState<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends ConsumerState<BrowserScreen> {
  String? _lastExtractedUrl;
  bool _isExtracting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = ref.read(browserProvider);
      if (state.tabs.length == 1 &&
          state.activeTab.currentUrl == 'https://www.google.com' &&
          widget.initialUrl != 'https://www.google.com') {
        ref.read(browserProvider.notifier).navigateTo(widget.initialUrl);
      }
    });
  }

  /// ─── محرك الاستخراج الذكي (Smart Scraper) ────────
  /// يحقن JavaScript لاستخراج بيانات og:tags من الصفحة وحفظها
  Future<void> _extractAndSaveMetadata(InAppWebViewController controller, String url, {int retryCount = 0}) async {
    if (retryCount == 0 && _lastExtractedUrl == url) return;
    _lastExtractedUrl = url;

    if (retryCount > 0) {
      final currentWebUrl = (await controller.getUrl())?.toString();
      if (currentWebUrl != url) {
        debugPrint('🚫 [Cover] Aborting retry: URL has changed from $url to $currentWebUrl');
        return;
      }
    }

    final uri = Uri.tryParse(url);
    if (uri == null) return;

    // استثناء الصفحات الفارغة، محركات البحث، الصفحات الرئيسية، وصفحات تسجيل الدخول أو الكلاودفلير الواضحة
    final lowerUrl = url.toLowerCase();
    final path = uri.path;
    if (url == 'about:blank' ||
        lowerUrl.contains('google.com') ||
        lowerUrl.contains('bing.com') ||
        lowerUrl.contains('yahoo.com') ||
        lowerUrl.contains('facebook.com') ||
        lowerUrl.contains('twitter.com') ||
        lowerUrl.contains('login') ||
        lowerUrl.contains('signup') ||
        lowerUrl.contains('register') ||
        lowerUrl.contains('challenge') || // cloudflare
        path == '' ||
        path == '/' ||
        path == '/manga' ||
        path == '/manga/') {
      return;
    }

    try {
      final jsResult = await controller.callAsyncJavaScript(
        functionBody: r'''
          var data = {};
          var currentUrl = window.location.href;
          
          // دالة مساعدة للحصول على الرابط الفعلي للصورة
          function getImgSrc(img) {
            if (!img) return '';
            var src = img.getAttribute('data-original') ||
                      img.getAttribute('data-src') ||
                      img.getAttribute('data-lazy-src') ||
                      img.getAttribute('data-srcset') ||
                      img.getAttribute('data-cfsrc') ||
                      img.src || '';
            src = src.trim();
            if (src.indexOf(' ') !== -1) {
              src = src.split(/\s+/)[0];
            }
            return src;
          }
          
          // دالة لتنظيف العنوان محلياً في JS لتقييمه
          function getCleanMangaTitle(title) {
            if (!title) return '';
            var parts = title.split(/\s*[|\-–—_~]\s*/);
            for (var i = 0; i < parts.length; i++) {
              var segment = parts[i].trim();
              if (!segment) continue;
              var cleaned = segment.replace(/\b(chapter|ch\.|ch|episode|ep\.|ep|vol\.|volume)\s*\d+.*/i, '');
              cleaned = cleaned.replace(/\b(فصل|شابتر|حلقة)\s*\d+.*/i, '');
              cleaned = cleaned.trim();
              var isGeneric = !cleaned || cleaned.length < 3 || 
                              /^(chapter|episode|read|viewer|manga|ch|ep|volume|فصل|شابتر|حلقة|قراءة|mangas|comics|manhua|manhwa|webtoon|raw)$/i.test(cleaned);
              if (!isGeneric) {
                return cleaned;
              }
            }
            var t = title.trim();
            t = t.replace(/\b(chapter|ch\.|ch|episode|ep\.|ep|vol\.|volume)\s*\d+.*/i, '');
            t = t.replace(/\b(فصل|شابتر|حلقة)\s*\d+.*/i, '');
            return t.trim();
          }

          // ─── التحقق من صحة الـ Meta لتفادي بيانات الـ SPA الشبحية ───
          var isMetaValid = true;
          var ogUrlEl = document.querySelector('meta[property="og:url"]') || document.querySelector('link[rel="canonical"]');
          var metaUrl = ogUrlEl ? (ogUrlEl.content || ogUrlEl.href || '') : '';
          if (metaUrl) {
            try {
              var currUri = new URL(currentUrl);
              var metaUri = new URL(metaUrl);
              
              function getSlugFromUrl(urlObj) {
                var parts = urlObj.pathname.split('/').filter(Boolean);
                var seriesKeywords = ['series', 'manga', 'mangas', 'comic', 'comics', 'manhwa', 'manhwas', 'manhua', 'manhuas', 'title', 'titles', 'book', 'books', 'webtoon', 'webtoons', 'project', 'projects'];
                for (var i = 0; i < parts.length - 1; i++) {
                  if (seriesKeywords.indexOf(parts[i].toLowerCase()) !== -1) {
                    return parts[i + 1].toLowerCase();
                  }
                }
                if (parts.length > 0) {
                  var last = parts[parts.length - 1].toLowerCase();
                  if (/^(chapter|ch|ep|episode|chap|c|\d+)/.test(last) && parts.length > 1) {
                    return parts[parts.length - 2].toLowerCase();
                  }
                  return last;
                }
                return '';
              }
              
              var currSlug = getSlugFromUrl(currUri);
              var metaSlug = getSlugFromUrl(metaUri);
              
              if (currSlug && metaSlug && currSlug !== metaSlug) {
                isMetaValid = false;
              }
            } catch(e) {}
          }

          // 1. استخراج العنوان الأساسي
          var rawTitle = '';
          var ogTitle = isMetaValid ? (document.querySelector('meta[property="og:title"]') || document.querySelector('meta[name="twitter:title"]')) : null;
          if (ogTitle && ogTitle.content) {
            rawTitle = ogTitle.content;
          } else {
            rawTitle = document.title;
          }
          
          var cleanTitleCandidate = getCleanMangaTitle(rawTitle);
          
          // إذا كان العنوان المستخرج قصيراً جداً أو غير موجود أو يحتوي فقط على كلمات عامة (مثل "شابتر 1" أو "فصل 1" أو "Chapter 1")
          var isGenericTitle = !cleanTitleCandidate || cleanTitleCandidate.length < 3 || 
                               /^(chapter|episode|read|viewer|manga|ch|ep|volume|فصل|شابتر|حلقة|قراءة)$/i.test(cleanTitleCandidate);
          
          if (isGenericTitle) {
            // نحاول استخراج اسم المانجا من الـ DOM (Breadcrumbs أو العناصر المخصصة)
            var selectors = [
              '.breadcrumb a', '.breadcrumbs a', 'ol.breadcrumb a', 'nav.breadcrumb a',
              '.c-breadcrumb a', '.back-to-manga a', '.manga-title a', '.series-title a', '.comic-title a', '.title a',
              '.manga-title', '.series-title', '.comic-title', '.manga-name', '.series-name', '.comic-name',
              'h1 a', 'h2 a', 'h1', 'h2', '.title', '.entry-title', '.post-title', '.manga-link'
            ];
            for (var i = 0; i < selectors.length; i++) {
              var el = document.querySelector(selectors[i]);
              if (el && el.textContent) {
                var txt = el.textContent.trim();
                var cleanTxt = getCleanMangaTitle(txt);
                if (cleanTxt && cleanTxt.length >= 3 && !/^(chapter|episode|read|viewer|manga|ch|ep|volume|فصل|شابتر|حلقة|قراءة)$/i.test(cleanTxt)) {
                  rawTitle = txt; // وجدنا اسم المانجا الحقيقي!
                  break;
                }
              }
            }
          }
          
          // ─── كشف عدم مزامنة الـ DOM ───
          var domTitle = '';
          var domTitleSelectors = ['h1', '.manga-title', '.series-title', '.comic-title', '.manga-name', '.entry-title', '.post-title'];
          for (var i = 0; i < domTitleSelectors.length; i++) {
            var el = document.querySelector(domTitleSelectors[i]);
            if (el && el.textContent) {
              var txt = el.textContent.trim();
              var cleanTxt = getCleanMangaTitle(txt);
              if (cleanTxt && cleanTxt.length >= 3 && !/^(chapter|episode|read|viewer|manga|ch|ep|volume|فصل|شابتر|حلقة|قراءة)$/i.test(cleanTxt)) {
                domTitle = cleanTxt;
                break;
              }
            }
          }
          
          var docTitleCleaned = getCleanMangaTitle(document.title);
          if (domTitle && docTitleCleaned) {
            var domWords = domTitle.toLowerCase().split(/\s+/).filter(function(w) { return w.length > 2; });
            var docWords = docTitleCleaned.toLowerCase().split(/\s+/).filter(function(w) { return w.length > 2; });
            var hasMatch = false;
            for (var wIdx = 0; wIdx < domWords.length; wIdx++) {
              if (docWords.indexOf(domWords[wIdx]) !== -1) {
                hasMatch = true;
                break;
              }
            }
            if (!hasMatch && domWords.length > 0 && docWords.length > 0) {
              data.staleData = true;
            }
          }
          
          data.title = rawTitle;
          data.url = currentUrl;
          
          // 2. فحص هل الصفحة الحالية هي صفحة فصل (Chapter Page) أم تفاصيل (Details Page) بناءً على الـ DOM
          var isChapterPage = false;
          var isDetailsPage = false;
          
          // أ. كشف صفحة الفصل (Chapter):
          // - وجود صور مانغا متتالية (عادة أكثر من 3 صور بأبعاد متوسطة/كبيرة)
          // - وجود أزرار "الفصل التالي/السابق" (Next/Prev Chapter)
          // - حاويات القراءة الشائعة (.read-container, .viewer-images, .manga-box, .wp-manga-chapter-img)
          var readerContainers = document.querySelectorAll('.read-container, .viewer-images, .manga-box, .wp-manga-chapter-img, #chapter-video-frame, .reading-content, .reader-area, #readerarea, .vung-doc, #vungdoc, .image-placeholder, .chapter-content, .entry-content');
          var nextPrevButtons = document.querySelectorAll('a[href*="chapter"], a[href*="ch-"], .next-post, .prev-post, .next_page, .prev_page, select[class*="chapter"], select[id*="chapter"], .next-btn, .prev-btn, .nextChapter, .prevChapter');
          var largeImagesCount = 0;
          var imgs = document.querySelectorAll('img');
          for (var i = 0; i < imgs.length; i++) {
            var img = imgs[i];
            var h = img.naturalHeight || img.height || 0;
            var w = img.naturalWidth || img.width || 0;
            var src = getImgSrc(img);
            
            // صور صفحات المانغا تكون طويلة نسبياً وعريضة
            if ((h > 400 && w > 350) || (src.toLowerCase().includes('chapter') && !src.toLowerCase().includes('cover') && !src.toLowerCase().includes('logo'))) {
              largeImagesCount++;
            }
          }
          
          if (readerContainers.length > 0 || largeImagesCount >= 3 || (nextPrevButtons.length >= 2 && largeImagesCount >= 1)) {
            isChapterPage = true;
          }
          
          // ب. كشف صفحة التفاصيل (Details/Manga Info Page):
          // - وجود قائمة فصول (روابط تحتوي كلمة chapter/ch/episode/ep)
          // - وجود عناصر معلومات المانغا (القصة، التقييم، الكاتب)
          // - عدم كونها صفحة فصل
          if (!isChapterPage) {
            var chapterLinks = document.querySelectorAll('a[href*="chapter"], a[href*="ch-"], a[href*="episode"], a[href*="ep-"], .wp-manga-chapter a, .chapter-list a, a[href*="/read/"]');
            var mangaDetailsElements = document.querySelectorAll('.manga-info, .manga-detail, .summary-content, .post-content_item, .manga-about, .comic-info, .detail-info, .description-info, .synopsis-content, .story-info-right, .manga-summary, .series-description');
            if (chapterLinks.length >= 3 || mangaDetailsElements.length > 0) {
              isDetailsPage = true;
            }
          }
          
          data.isChapterPage = isChapterPage;
          data.isDetailsPage = isDetailsPage;
          
          // 3. البحث عن غلاف المانجا الأصلي
          var coverUrl = "";
          var coverImgElement = null;
          
          var coverSelectors = [
            '.summary_image img',
            '.manga-about img',
            '.tab-summary img',
            '.manga-info img',
            '.post-content img',
            '.manga-page img',
            '.book-cover img',
            '.story-cover img',
            '.manga-detail img',
            '.manga-info-pic img',
            '.info-image img',
            '.comic-cover img',
            'img[class*="cover"]',
            'img[src*="cover"]',
            'img[class*="thumb"]',
            'img[src*="thumb"]',
            'img[class*="poster"]',
            'img[src*="poster"]',
            'img[id*="cover"]',
            'img[id*="thumb"]',
            '.thumb img',
            '.poster img'
          ];
          
          function isValidCoverUrl(url) {
            if (!url || url.length < 15 || url.indexOf('data:') === 0) return false;
            var urlLower = url.toLowerCase();
            var invalidKeywords = [
              '/chapter/', '/chapters/', '/reader/', '/pages/', '/page_', '/image_',
              'page_0', 'image_0', '001.', '002.', '003.', '-00', '_00',
              'wp-content/uploads/wp-manga/data/'
            ];
            for (var i = 0; i < invalidKeywords.length; i++) {
              if (urlLower.indexOf(invalidKeywords[i]) !== -1) return false;
            }
            var junkKeywords = ['logo', 'banner', 'avatar', 'icon', 'button', 'popup', 'captcha', 'pixel', 'tracking', 'analytics', 'live', 'widget'];
            for (var i = 0; i < junkKeywords.length; i++) {
              if (urlLower.indexOf(junkKeywords[i]) !== -1) return false;
            }
            return true;
          }
          
          if (isDetailsPage) {
            // نحن في صفحة التفاصيل: نبحث عن الغلاف مباشرة في الصفحة المفتوحة حالياً
            for (var s = 0; s < coverSelectors.length; s++) {
              var el = document.querySelector(coverSelectors[s]);
              if (el) {
                var src = getImgSrc(el);
                if (isValidCoverUrl(src)) {
                  if (src.startsWith('/')) {
                    var urlObj = new URL(currentUrl);
                    src = urlObj.origin + src;
                  } else if (!src.startsWith('http')) {
                    var urlObj2 = new URL(currentUrl);
                    src = urlObj2.origin + '/' + src;
                  }
                  coverUrl = src;
                  coverImgElement = el;
                  break;
                }
              }
            }
            
            if (!coverUrl && isMetaValid) {
              var ogImage = document.querySelector('meta[property="og:image"]') || document.querySelector('meta[name="twitter:image"]');
              if (ogImage && ogImage.content && isValidCoverUrl(ogImage.content)) {
                coverUrl = ogImage.content;
              }
            }
            
            // احتياطي ذكي للمانغات غير المسجلة: البحث عن أي صورة كبيرة بحجم الغلاف
            if (!coverUrl) {
              var allImgs = document.querySelectorAll('img');
              for (var i = 0; i < allImgs.length; i++) {
                var img = allImgs[i];
                var w = img.naturalWidth || img.width || 0;
                var h = img.naturalHeight || img.height || 0;
                var src = getImgSrc(img);
                if (((w > 150 && h > 200) || (w === 0 && h === 0 && src.length > 20)) && isValidCoverUrl(src)) {
                  if (src.startsWith('/')) {
                    var urlObj = new URL(currentUrl);
                    src = urlObj.origin + src;
                  } else if (!src.startsWith('http')) {
                    var urlObj2 = new URL(currentUrl);
                    src = urlObj2.origin + '/' + src;
                  }
                  coverUrl = src;
                  coverImgElement = img;
                  break;
                }
              }
            }
          } else if (isChapterPage) {
            // نحن في صفحة فصل: نحاول تحديد رابط صفحة التفاصيل وجلبها في الخلفية
            var detailsUrl = "";
            
            var breadcrumbs = document.querySelectorAll('a[href*="/manga/"], a[href*="/mangas/"], a[href*="/series/"], a[href*="/comic/"], a[href*="/comics/"], a[href*="/manhua/"], a[href*="/manhwa/"], a[href*="/book/"], a[href*="/books/"], a[href*="/project/"], a[href*="/projects/"], .breadcrumbs a, .breadcrumb a, ol.breadcrumb a, nav.breadcrumb a, .c-breadcrumb a, .back-to-manga a');
            for (var i = 0; i < breadcrumbs.length; i++) {
              var a = breadcrumbs[i];
              if (a.href && a.href !== currentUrl && !a.href.match(/(chapter|ch\- |episode|ep\- |\d+\-chapter)/i)) {
                detailsUrl = a.href;
                break;
              }
            }
            
            // منطق ذكي للروابط المسطحة: مطابقة الرابط الأب (مثل /slug من /slug/1)
            if (!detailsUrl) {
              try {
                var currentPath = window.location.pathname;
                var pathParts = currentPath.split('/').filter(Boolean);
                if (pathParts.length > 1) {
                  var parentPath = '/' + pathParts.slice(0, pathParts.length - 1).join('/');
                  var allLinks = document.querySelectorAll('a');
                  for (var i = 0; i < allLinks.length; i++) {
                    var link = allLinks[i];
                    if (link.href) {
                      var linkPath = new URL(link.href).pathname;
                      if (linkPath === parentPath || linkPath === parentPath + '/') {
                        detailsUrl = link.href;
                        break;
                      }
                    }
                  }
                }
              } catch(e) {}
            }
            
            if (!detailsUrl) {
              try {
                var pathParts = window.location.pathname.split('/').filter(Boolean);
                if (pathParts.length > 1) {
                  var mangaSlug = pathParts[pathParts.length - 2];
                  if (mangaSlug && mangaSlug.length > 3 && !mangaSlug.match(/^(chapter|ch|ep|episode)$/i)) {
                    var allLinks = document.querySelectorAll('a');
                    for (var i = 0; i < allLinks.length; i++) {
                      var link = allLinks[i];
                      if (link.href && link.href.indexOf(mangaSlug) !== -1 && link.href !== currentUrl && !link.href.match(/(chapter|ch\- |episode|ep\- |\d+\-chapter)/i)) {
                        detailsUrl = link.href;
                        break;
                      }
                    }
                  }
                }
              } catch(slugErr) {}
            }
            
            if (!detailsUrl) {
              // Fallback ذكي: إزالة مقاطع الفصل والحاويات بشكل متكرر
              var urlParts = currentUrl.split('?')[0].split('/');
              if (urlParts[urlParts.length - 1] === '') urlParts.pop();
              var containerSegments = ['episodes', 'chapters', 'read', 'reader', 'viewer'];
              while (urlParts.length > 4) {
                var lastPart = urlParts[urlParts.length - 1].toLowerCase();
                if (lastPart.match(/^(chapter|ch|chap|episode|ep|c)[-_]?\d+/) ||
                    lastPart.match(/^\d+(\.\d+)?$/) ||
                    lastPart.match(/^[0-9a-f]{24}$/) ||
                    lastPart.match(/^[0-9a-f]{32}$/) ||
                    lastPart.match(/^[0-9a-f]{8,}(-[0-9a-f]{4,}){2,}/) ||
                    containerSegments.indexOf(lastPart) !== -1) {
                  urlParts.pop();
                } else {
                  break;
                }
              }
              
              // ─── ترقية الجافا سكريبت للتعامل مع الروابط المسطحة (Flat URLs) ───
              if (urlParts.length === 4) {
                var lastPart = urlParts[3];
                var chapterRegex = /[-_](chapter|ch|episode|ep|chap|c)[-_]?\d+.*$/i;
                var numberRegex = /[-_]\d+(\.\d+)?$/;
                if (chapterRegex.test(lastPart)) {
                  urlParts[3] = lastPart.replace(chapterRegex, '');
                } else if (numberRegex.test(lastPart)) {
                  urlParts[3] = lastPart.replace(numberRegex, '');
                }
              }
              
              detailsUrl = urlParts.join('/') + '/';
            }
            
            // التحقق من تطابق detailsUrl مع الرابط الحالي (كشف بيانات SPA الشبحية)
            if (detailsUrl) {
              try {
                var currentSeriesMatch = currentUrl.match(/\/series\/([^/?#]+)|\/manga\/([^/?#]+)|\/comic\/([^/?#]+)|\/manhwa\/([^/?#]+)|\/title\/([^/?#]+)/);
                var detailsSeriesMatch = detailsUrl.match(/\/series\/([^/?#]+)|\/manga\/([^/?#]+)|\/comic\/([^/?#]+)|\/manhwa\/([^/?#]+)|\/title\/([^/?#]+)/);
                if (currentSeriesMatch && detailsSeriesMatch) {
                  var currentSlug = (currentSeriesMatch[1] || currentSeriesMatch[2] || currentSeriesMatch[3] || currentSeriesMatch[4] || currentSeriesMatch[5] || '').toLowerCase();
                  var detailsSlug = (detailsSeriesMatch[1] || detailsSeriesMatch[2] || detailsSeriesMatch[3] || detailsSeriesMatch[4] || detailsSeriesMatch[5] || '').toLowerCase();
                  if (currentSlug && detailsSlug && currentSlug !== detailsSlug) {
                    // detailsUrl ينتمي لمانغا مختلفة - بيانات SPA شبحية!
                    data.staleData = true;
                  }
                }
              } catch(valErr) {}
            }
            
            if (detailsUrl && detailsUrl.length > 10) {
              try {
                var response = await fetch(detailsUrl, { credentials: 'include' });
                if (response.ok) {
                  var html = await response.text();
                  var parser = new DOMParser();
                  var doc = parser.parseFromString(html, 'text/html');
                  
                  // استخراج اسم المانغا الأصلي من صفحة التفاصيل المجلوبة في الخلفية وتحديث العنوان بها
                  var docTitleMeta = doc.querySelector('meta[property="og:title"]') || doc.querySelector('meta[name="twitter:title"]');
                  var fetchedTitle = docTitleMeta ? docTitleMeta.content : doc.title;
                  if (fetchedTitle) {
                    var cleanedFetched = getCleanMangaTitle(fetchedTitle);
                    if (cleanedFetched && cleanedFetched.length >= 3) {
                      data.title = fetchedTitle; // تحديث العنوان
                    }
                  }
                  
                  var docOgImage = doc.querySelector('meta[property="og:image"]') || doc.querySelector('meta[name="twitter:image"]');
                  if (docOgImage && docOgImage.content && isValidCoverUrl(docOgImage.content)) {
                    coverUrl = docOgImage.content;
                  }
                  
                  if (!coverUrl) {
                    for (var s = 0; s < coverSelectors.length; s++) {
                      var docCover = doc.querySelector(coverSelectors[s]);
                      if (docCover) {
                        var src = getImgSrc(docCover);
                        if (isValidCoverUrl(src)) {
                          if (src.startsWith('/')) {
                            var urlObj = new URL(detailsUrl);
                            src = urlObj.origin + src;
                          } else if (!src.startsWith('http')) {
                            var urlObj2 = new URL(detailsUrl);
                            src = urlObj2.origin + '/' + src;
                          }
                          coverUrl = src;
                          break;
                        }
                      }
                    }
                  }
                  
                  // فحص كافة الصور المتاحة في صفحة التفاصيل المجلوبة كحل أخير
                  if (!coverUrl) {
                    var docImgs = doc.querySelectorAll('img');
                    for (var i = 0; i < docImgs.length; i++) {
                      var img = docImgs[i];
                      var w = img.getAttribute('width') || img.width || 0;
                      var h = img.getAttribute('height') || img.height || 0;
                      var src = getImgSrc(img);
                      if (isValidCoverUrl(src)) {
                        if (src.indexOf('cover') !== -1 || src.indexOf('thumb') !== -1 || src.indexOf('poster') !== -1 || (w > 120 && h > 180)) {
                          if (src.startsWith('/')) {
                            var urlObj = new URL(detailsUrl);
                            src = urlObj.origin + src;
                          } else if (!src.startsWith('http')) {
                            var urlObj2 = new URL(detailsUrl);
                            src = urlObj2.origin + '/' + src;
                          }
                          coverUrl = src;
                          break;
                        }
                      }
                    }
                  }
                }
              } catch(e) {}
            }
            
            if (!coverUrl && isMetaValid) {
              var ogImage2 = document.querySelector('meta[property="og:image"]') || document.querySelector('meta[name="twitter:image"]');
              if (ogImage2 && ogImage2.content && isValidCoverUrl(ogImage2.content)) {
                if (!ogImage2.content.match(/[_-](001|01|1)\.(jpg|png|webp|jpeg)/i)) {
                  coverUrl = ogImage2.content;
                }
              }
            }
          }
          
          // إرسال رابط صفحة التفاصيل الذي عثرنا عليه لاستخدامه في توليد معرف موحد
          if (isChapterPage && typeof detailsUrl !== 'undefined' && detailsUrl) {
            data.detailsUrl = detailsUrl;
          }
          
          data.image = coverUrl || '';
          data.coverBase64 = '';
          
          // الاستراتيجية 1: رسم صورة DOM المحملة مسبقاً على Canvas (تتخطى CORS تماماً)
          if (coverImgElement && coverImgElement.complete && coverImgElement.naturalWidth > 50) {
            try {
              var canvas = document.createElement('canvas');
              canvas.width = coverImgElement.naturalWidth;
              canvas.height = coverImgElement.naturalHeight;
              var ctx = canvas.getContext('2d');
              ctx.drawImage(coverImgElement, 0, 0);
              data.coverBase64 = canvas.toDataURL('image/jpeg', 0.85);
            } catch(canvasErr) {}
          }
          
          // الاستراتيجية 2: fetch مع CORS من سياق المتصفح المصادق عليه
          if (!data.coverBase64 && data.image && data.image.length > 10 && data.image.indexOf('data:') !== 0) {
            try {
              var imgResponse = await fetch(data.image, { mode: 'cors', credentials: 'include' });
              if (imgResponse.ok) {
                var blob = await imgResponse.blob();
                var base64 = await new Promise(function(resolve, reject) {
                  var reader = new FileReader();
                  reader.onloadend = function() { resolve(reader.result); };
                  reader.onerror = function() { reject('FileReader error'); };
                  reader.readAsDataURL(blob);
                });
                data.coverBase64 = base64;
              }
            } catch(e) {
              // الاستراتيجية 3: fetch بدون CORS mode
              try {
                var imgResponse2 = await fetch(data.image, { credentials: 'include' });
                if (imgResponse2.ok) {
                  var blob2 = await imgResponse2.blob();
                  var base642 = await new Promise(function(resolve, reject) {
                    var reader2 = new FileReader();
                    reader2.onloadend = function() { resolve(reader2.result); };
                    reader2.onerror = function() { reject('FileReader error'); };
                    reader2.readAsDataURL(blob2);
                  });
                  data.coverBase64 = base642;
                }
              } catch(e2) {}
            }
          }
          
          return JSON.stringify(data);
        ''',
      );

      if (jsResult == null || jsResult.value == null) {
        debugPrint('📭 [Cover] JS returned null for $url');
        return;
      }

      final Map<String, dynamic> metadata = _parseJsonSafe(jsResult.value.toString());
      if (metadata.isEmpty) {
        debugPrint('📭 [Cover] Parsed metadata is empty for $url');
        return;
      }

      final title = (metadata['title'] as String?) ?? '';
      final coverBase64 = (metadata['coverBase64'] as String?) ?? '';
      final imageUrl = (metadata['image'] as String?) ?? '';
      
      // تحديد نوع الصفحة بناءً على الكشف من الـ DOM
      bool isChapter = metadata['isChapterPage'] == true;
      bool isDetails = metadata['isDetailsPage'] == true;
      
      // Fallback للمطابقة المستندة إلى الرابط إذا لم يكن كشف الـ DOM حاسماً
      if (!isChapter && !isDetails) {
        isChapter = _isMangaChapterPage(url);
        isDetails = _isMangaDetailsPage(url);
      }

      // إذا لم تكن الصفحة تفاصيل ولا فصل، نتخطى حفظها
      if (!isChapter && !isDetails) {
        debugPrint('🚫 [Cover] Skipping: Page is neither a chapter nor details page (DOM & regex check).');
        return;
      }

      debugPrint('🔍 [Cover] title="$title", isChapter=$isChapter, isDetails=$isDetails, imageUrl="${imageUrl.length > 60 ? '${imageUrl.substring(0, 60)}...' : imageUrl}", base64Length=${coverBase64.length}');

      // تنظيف العنوان (إزالة كلمة chapter أو ارقام الفصل أو اسم الموقع)
      final cleanTitle = _cleanMangaTitle(title);

      // لا نسجل صفحات بدون عنوان واضح أو صفحات فحص Cloudflare
      if (cleanTitle.isEmpty || cleanTitle.length < 3 || _isCloudflareOrError(cleanTitle)) {
        debugPrint('🚫 [Cover] Skipping: cleanTitle="$cleanTitle"');
        return;
      }

      // ─── كشف بيانات SPA الشبحية وإعادة المحاولة ───
      final isStaleData = metadata['staleData'] == true;
      if (isStaleData) {
        if (retryCount < 3) {
          final nextRetry = retryCount + 1;
          final delayMs = 600 + (retryCount * 400);
          debugPrint('⚠️ [Cover] SPA stale data detected! Scheduling retry #$nextRetry in ${delayMs}ms for URL=$url');
          Future.delayed(Duration(milliseconds: delayMs), () {
            if (mounted) {
              _extractAndSaveMetadata(controller, url, retryCount: nextRetry);
            }
          });
        } else {
          debugPrint('⚠️ [Cover] SPA stale data detected! Max retries reached, skipping URL=$url');
        }
        return;
      }
      
      // ─── توحيد المعرف: استخدام رابط التفاصيل عند التواجد في صفحة فصل ───
      final jsDetailsUrl = (metadata['detailsUrl'] as String?) ?? '';
      String idSourceUrl;
      
      // التحقق الإضافي: مقارنة slug المانغا بين الرابط الحالي و detailsUrl
      if (isChapter && jsDetailsUrl.isNotEmpty && jsDetailsUrl.length > 10) {
        final currentSlug = _extractSeriesSlug(url);
        final detailsSlug = _extractSeriesSlug(jsDetailsUrl);
        if (currentSlug.isNotEmpty && detailsSlug.isNotEmpty && currentSlug != detailsSlug) {
          debugPrint('⚠️ [Cover] SPA slug mismatch! URL slug=$currentSlug but detailsUrl slug=$detailsSlug. Skipping.');
          return;
        }
        idSourceUrl = jsDetailsUrl;
        debugPrint('🔗 [Cover] Using JS detailsUrl for ID: $jsDetailsUrl');
      } else {
        idSourceUrl = _getBaseMangaUrl(url);
        debugPrint('🔗 [Cover] Using _getBaseMangaUrl for ID: $idSourceUrl (from URL: $url)');
      }
      
      // محاولة البحث عن معرف مانغا مسجل مسبقاً بنفس العنوان على نفس النطاق لمنع التكرار
      final id = HistoryService.findExistingMangaIdByTitle(cleanTitle, url) ?? 
                 HistoryService.generateId(idSourceUrl);
      debugPrint('🆔 [Cover] Generated ID=$id from idSourceUrl=$idSourceUrl');
      final existing = HistoryService.getHistoryById(id);
      final siteUrl = existing?.siteUrl ?? _getBaseMangaUrl(url);
      debugPrint('📋 [Cover] existing=${existing != null ? "YES (title=${existing.title})" : "NO"}, siteUrl=$siteUrl');

      // هل نحتاج لتحميل أو تحديث الغلاف؟
      final bool existingIsLocal = existing != null && existing.imageUrl.isNotEmpty && !existing.imageUrl.startsWith('http') && !existing.imageUrl.startsWith('data:');
      final bool existingFileExists = existingIsLocal && File(existing.imageUrl).existsSync();
      
      bool needsUpdate = false;
      if (existing == null || existing.imageUrl.isEmpty || !existingFileExists) {
        needsUpdate = true;
      } else if (!isChapter && imageUrl.isNotEmpty && existing.remoteImageUrl != imageUrl) {
        needsUpdate = true;
      }

      debugPrint('🔎 [Cover] needsUpdate=$needsUpdate | existing=${existing != null} | existingFileExists=$existingFileExists | isChapter=$isChapter');

      // ─── حفظ صورة الغلاف محلياً ───
      String localCoverPath = '';
      final appDir = await getApplicationDocumentsDirectory();
      final coverDir = Directory('${appDir.path}/manga_covers');
      if (!await coverDir.exists()) await coverDir.create(recursive: true);
      final coverFilePath = '${coverDir.path}/$id.png';
      
      if (needsUpdate) {
        final oldFile = File(coverFilePath);
        if (oldFile.existsSync()) {
          await FileImage(oldFile).evict();
          await oldFile.delete();
          debugPrint('🗑️ [Cover] Deleted old cover file before update: $coverFilePath');
        }
      }
      
      bool savedNewCover = false;

      // 1. حفظ من base64
      if (needsUpdate && coverBase64.isNotEmpty && coverBase64.contains(',')) {
        final base64Str = coverBase64.split(',').last;
        try {
          final bytes = base64Decode(base64Str);
          if (bytes.length > 500) {
            final coverFile = File(coverFilePath);
            await coverFile.writeAsBytes(bytes);
            localCoverPath = coverFile.path;
            savedNewCover = true;
            await FileImage(coverFile).evict();
            debugPrint('🖼️ [Cover] Smart Saved/Updated from base64: $localCoverPath (${bytes.length} bytes)');
            await _propagateCoverToDownloads(cleanTitle, coverFilePath);
          }
        } catch (e) {
          debugPrint('❌ [Cover] Base64 decode failed: $e');
        }
      }

      // إعادة استخدام الغلاف القديم إن وجد ولم يتوفر جديد
      if (!needsUpdate && localCoverPath.isEmpty && existing != null && existing.imageUrl.isNotEmpty && !existing.imageUrl.startsWith('http') && !existing.imageUrl.startsWith('data:')) {
        final existingFile = File(existing.imageUrl);
        if (existingFile.existsSync()) {
          localCoverPath = existing.imageUrl;
          debugPrint('✅ [Cover] Reusing existing local cover: $localCoverPath');
        }
      }
      
      // 2. تحميل مباشر من Dart باستخدام Dio كـ fallback
      if (needsUpdate && !savedNewCover && imageUrl.isNotEmpty && imageUrl.startsWith('http')) {
        debugPrint('🔄 [Cover] Fetching/Updating cover via Dio: $imageUrl');
        try {
          final dio = Dio();
          final response = await dio.get<List<int>>(
            imageUrl,
            options: Options(
              responseType: ResponseType.bytes,
              headers: {
                'Referer': siteUrl,
                'User-Agent': 'Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
                'Accept': 'image/webp,image/avif,image/png,image/jpeg,*/*',
              },
              receiveTimeout: const Duration(seconds: 10),
              sendTimeout: const Duration(seconds: 5),
            ),
          );
          if (response.data != null && response.data!.length > 500) {
            final coverFile = File(coverFilePath);
            await coverFile.writeAsBytes(response.data!);
            localCoverPath = coverFile.path;
            savedNewCover = true;
            await FileImage(coverFile).evict();
            debugPrint('🖼️ [Cover] Saved from Dio download: $localCoverPath (${response.data!.length} bytes)');
            await _propagateCoverToDownloads(cleanTitle, coverFilePath);
          }
        } catch (e) {
          debugPrint('⚠️ [Cover] Dio download failed: $e');
        }
      }

      String titleToSave = cleanTitle;
      if (existing != null && existing.title.isNotEmpty) {
        // عند التواجد في صفحة فصل، نفضل دائماً عنوان السجل السابق (الذي جاء من صفحة التفاصيل)
        // إلا إذا كان العنوان الجديد أطول وأكثر وضوحاً (يعني جاء من fetch التفاصيل)
        if (isChapter) {
          if (cleanTitle.length > existing.title.length && !cleanTitle.toLowerCase().contains('read') && !cleanTitle.toLowerCase().contains('episode')) {
            titleToSave = cleanTitle; // العنوان الجديد أفضل (جاء من fetch الخلفية)
          } else {
            titleToSave = existing.title;
          }
        } else if (cleanTitle.toLowerCase() == 'read' || cleanTitle.toLowerCase() == 'series' || cleanTitle.isEmpty) {
          titleToSave = existing.title;
        }
      }
      
      // تحديد الغلاف الأفضل: الأولوية للغلاف المحلي الموجود مسبقاً عند التواجد في صفحة فصل
      String bestImageUrl;
      if (localCoverPath.isNotEmpty) {
        bestImageUrl = localCoverPath;
      } else if (existing != null && existing.imageUrl.isNotEmpty && !existing.imageUrl.startsWith('http') && !existing.imageUrl.startsWith('data:') && File(existing.imageUrl).existsSync()) {
        bestImageUrl = existing.imageUrl;
      } else if (existing?.imageUrl.isNotEmpty == true) {
        bestImageUrl = existing!.imageUrl;
      } else {
        bestImageUrl = imageUrl;
      }

      final manga = MangaHistory(
        id: id,
        title: titleToSave,
        imageUrl: bestImageUrl,
        remoteImageUrl: imageUrl.isNotEmpty ? imageUrl : (existing?.remoteImageUrl ?? ''),
        siteUrl: siteUrl,
        lastChapterUrl: isChapter ? url : (existing?.lastChapterUrl.isNotEmpty == true ? existing!.lastChapterUrl : url),
        lastChapter: isChapter ? _extractChapterFromUrl(url) : (existing?.lastChapter ?? ''),
        lastRead: DateTime.now(),
      );

      debugPrint('💾 [Cover] Saving history: title="$titleToSave", imageUrl="${manga.imageUrl.length > 60 ? '${manga.imageUrl.substring(0, 60)}...' : manga.imageUrl}"');
      await HistoryService.saveMangaHistory(manga);
    } catch (e) {
      debugPrint('⚠️ Metadata extraction failed: $e');
    }
  }

  /// نشر الغلاف المصحح لجميع الفصول المحملة مسبقاً لهذه المانغا
  Future<void> _propagateCoverToDownloads(String cleanTitle, String coverFilePath) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final safeMangaTitle = cleanTitle.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final downloadsDir = Directory('${appDir.path}/downloads');
      if (await downloadsDir.exists()) {
        final List<FileSystemEntity> entities = downloadsDir.listSync(recursive: true);
        for (final entity in entities) {
          if (entity is Directory) {
            final String dirName = entity.path.toLowerCase();
            final String targetTitle = safeMangaTitle.toLowerCase();
            // التحقق من احتواء مسار المجلد على اسم المانغا (مطابقة ذكية مرنة)
            if (dirName.contains(targetTitle)) {
              // نتحقق مما إذا كان مجلد فصل حقيقي يحتوي على صور لتفادي نسخ الغلاف للمجلد الرئيسي
              bool hasImages = false;
              try {
                hasImages = entity.listSync().any((e) => e is File && (e.path.endsWith('.png') || e.path.endsWith('.jpg') || e.path.endsWith('.webp')));
              } catch (_) {}
              
              if (hasImages) {
                final destCoverFile = File('${entity.path}/cover.png');
                // حذف الغلاف القديم إن وجد ومسحه من الكاش قبل النسخ الجديد
                if (destCoverFile.existsSync()) {
                  await FileImage(destCoverFile).evict();
                  await destCoverFile.delete();
                }
                await File(coverFilePath).copy(destCoverFile.path);
                await FileImage(destCoverFile).evict();
                debugPrint('🔄 [Cover] Propagated corrected cover to downloaded chapter: ${destCoverFile.path}');
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ [Cover] Failed to propagate cover to downloads: $e');
    }
  }

  /// استخراج رقم الفصل من الرابط بشكل ذكي
  String _extractChapterFromUrl(String url) {
    // أنماط شائعة في روابط المانغا: chapter-10, ch-10, chapter/10, c10
    final patterns = [
      RegExp(r'chapter[/-]?(\d+)', caseSensitive: false),
      RegExp(r'ch[/-]?(\d+)', caseSensitive: false),
      RegExp(r'episode[/-]?(\d+)', caseSensitive: false),
      RegExp(r'ep[/-]?(\d+)', caseSensitive: false),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(url);
      if (match != null) {
        return 'Ch. ${match.group(1)}';
      }
    }
    return '';
  }

  /// التأكد هل الصفحة هي صفحة فصل مانغا
  bool _isMangaChapterPage(String url) {
    final lowerUrl = url.toLowerCase();
    
    // استبعاد صفحات تسجيل الدخول أو الكلاودفلير
    if (lowerUrl.contains('login') || lowerUrl.contains('signup') || lowerUrl.contains('challenge')) return false;

    final uri = Uri.tryParse(url);
    final queryParams = uri?.queryParameters ?? {};
    
    // 1. التحقق من query parameters التي تدل على فصل
    final chapterQueryKeys = ['episode', 'ep', 'chapter', 'ch', 'episode_id', 'chapter_id', 'content_id', 'page_id', 'chap'];
    for (final key in chapterQueryKeys) {
      if (queryParams.containsKey(key)) return true;
    }

    final path = uri?.path ?? '';
    if (path.isEmpty || path == '/') return false;

    // 2. هل يحتوي الرابط على مؤشر فصل؟ (أنماط المسار)
    final chapterPatterns = [
      RegExp(r'chapters?[/-]?\d+', caseSensitive: false),
      RegExp(r'ch[/-]?\d+', caseSensitive: false),
      RegExp(r'chap[/-]?\d+', caseSensitive: false),
      RegExp(r'c[/-]?\d+', caseSensitive: false),
      RegExp(r'episode[/-]?\d+', caseSensitive: false),
      RegExp(r'ep[/-]?\d+', caseSensitive: false),
      RegExp(r'\d+-chapter', caseSensitive: false),
      RegExp(r'viewer\?title_no', caseSensitive: false), // Webtoon
      RegExp(r'/read/', caseSensitive: false),
      RegExp(r'/reader/', caseSensitive: false),
      RegExp(r'/viewer/', caseSensitive: false),
    ];

    if (chapterPatterns.any((p) => p.hasMatch(url))) return true;

    // 3. التحقق الذكي للمواقع التي تستخدم مسار التفاصيل متبوعاً بمعرف الفصل
    final pathSegments = uri?.pathSegments.where((s) => s.isNotEmpty).toList() ?? [];
    final detailsKeywords = ['series', 'manga', 'mangas', 'comic', 'comics', 'title', 'titles', 'manhwa', 'manhwas', 'manhua', 'manhuas', 'webtoon', 'webtoons', 'book', 'books', 'project', 'projects'];
    for (final kw in detailsKeywords) {
      final idx = pathSegments.indexOf(kw);
      if (idx != -1 && pathSegments.length > idx + 2) {
        final lastSeg = pathSegments.last.toLowerCase();
        if (lastSeg != 'reviews' && lastSeg != 'comments' && lastSeg != 'recommendations' && lastSeg != 'edit') {
          return true;
        }
      }
    }

    // 4. إذا كان الرابط ينتهي برقم صريح أو مقطع رقمي بعد اسم المانغا (مثل /slug/1 أو /slug/1.5)
    if (pathSegments.length >= 2) {
      final lastSeg = pathSegments.last;
      if (RegExp(r'^\d+(\.\d+)?$').hasMatch(lastSeg) || 
          RegExp(r'^(ch|chapter|ep|episode|chap|c)[-_]?\d+(\.\d+)?$', caseSensitive: false).hasMatch(lastSeg)) {
        return true;
      }
      
      // 5. UUID كمعرف حلقة (مثل Manta: /series/slug/a0b1c2d3-e4f5-6789-...)
      if (RegExp(r'^[0-9a-f]{8,}(-[0-9a-f]{4,}){2,}', caseSensitive: false).hasMatch(lastSeg)) {
        return true;
      }
    }

    return false;
  }

  /// التأكد هل الصفحة هي صفحة تفاصيل مانغا (وليس فصل)
  bool _isMangaDetailsPage(String url) {
    final lowerUrl = url.toLowerCase();

    // استبعاد صفحات تسجيل الدخول أو الكلاودفلير أو البحث أو الفهرس العام
    final excludeKeywords = [
      'login', 'signup', 'register', 'challenge', 'search', 'latest', 'updates', 
      'genres', 'popular', 'bookmark', 'history', 'schedule', 'directory', 
      'list', 'filter', 'tag', 'category', 'archive', 'page/', '/page'
    ];
    if (excludeKeywords.any((kw) => lowerUrl.contains(kw))) return false;

    // إذا كانت صفحة فصل، فهي ليست صفحة تفاصيل
    if (_isMangaChapterPage(url)) return false;

    final uri = Uri.tryParse(url);
    final queryParams = uri?.queryParameters ?? {};
    
    // 1. التحقق من query parameters التي تدل على صفحة تفاصيل
    final detailsQueryKeys = ['title_no', 'series_id', 'manga_id', 'comic_id', 'id', 'manga'];
    if (detailsQueryKeys.any((k) => queryParams.containsKey(k))) {
      return true;
    }

    final path = uri?.path ?? '';
    if (path.isEmpty || path == '/' || path == '/manga' || path == '/manga/') return false;

    // 2. التحقق الذكي للمسارات التفصيلية
    final pathSegments = uri?.pathSegments.where((s) => s.isNotEmpty).toList() ?? [];
    final detailsKeywords = ['series', 'manga', 'mangas', 'comic', 'comics', 'title', 'titles', 'manhwa', 'manhwas', 'manhua', 'manhuas', 'webtoon', 'webtoons', 'book', 'books', 'project', 'projects'];
    for (final kw in detailsKeywords) {
      final idx = pathSegments.indexOf(kw);
      if (idx != -1 && pathSegments.length > idx + 1) {
        final slug = pathSegments[idx + 1];
        if (slug.isNotEmpty) {
          return true;
        }
      }
    }

    // 3. Fallback للمواقع غير المسجلة (ذات الهيكل المسطح)
    if (pathSegments.isNotEmpty) {
      final firstSeg = pathSegments.first.toLowerCase();
      final commonStaticPages = {
        'about', 'contact', 'dmca', 'privacy', 'policy', 'terms', 'faq', 'home', 
        'news', 'blog', 'support', 'assets', 'css', 'js', 'images', 'wp-admin'
      };
      if (!commonStaticPages.contains(firstSeg) && firstSeg.length > 2) {
        return true;
      }
    }
    
    return false;
  }

  String _cleanMangaTitle(String rawTitle) {
    String t = rawTitle.trim();
    
    // كلمات تدل على القراءة أو الفصل أو اسم الموقع ولا يجب أن تكون هي اسم المانغا
    final genericKeywords = {
      'read', 'reader', 'reading', 'chapter', 'episode', 'ch.', 'ep.', 'vol.', 'volume',
      'قراءة', 'فصل', 'شابتر', 'حلقة', 'مترجم', 'كامل', 'اون لاين', 'اونلاين',
      'manga', 'manhwa', 'manhua', 'webtoon', 'webcomic', 'comic', 'raw',
    };
    
    final siteKeywords = {
      'manta', 'webtoon', 'webtoons', 'mangadex', 'mangabat', 'mangakakalot',
      'tapas', 'tappytoon', 'lezhin', 'netcomics', 'toomics', 'bilibili',
    };

    // تقسيم العنوان بناءً على الفواصل الشائعة
    List<String> parts = t.split(RegExp(r'\s*[|–\-—_~]\s*'));
    
    // إزالة الأجزاء الفارغة
    parts = parts.map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
    
    // تنظيف كل جزء من كلمات الفصل والحلقة
    String cleanSegment(String seg) {
      String s = seg.trim();
      // إزالة "Read " من البداية
      s = s.replaceAll(RegExp(r'^read\s+', caseSensitive: false), '');
      // إزالة "Episode X" أو "Chapter X" وما بعدها
      s = s.replaceAll(RegExp(r'\b(chapter|ch\.?|episode|ep\.?|vol\.?|volume)\s*\d+.*$', caseSensitive: false), '');
      // إزالة "فصل X" أو "شابتر X" أو "حلقة X"
      s = s.replaceAll(RegExp(r'\b(فصل|شابتر|حلقة)\s*\d+.*$'), '');
      return s.trim();
    }
    
    // البحث عن أفضل جزء يمثل اسم المانغا الحقيقي
    for (final part in parts) {
      final cleaned = cleanSegment(part);
      if (cleaned.isEmpty || cleaned.length < 3) continue;
      
      final lower = cleaned.toLowerCase();
      // تخطي الأجزاء التي هي كلمات عامة أو اسم موقع فقط
      if (genericKeywords.contains(lower)) continue;
      if (siteKeywords.contains(lower)) continue;
      
      // تخطي الأجزاء التي هي وصف نوع المانغا (مثل "Manhwa/Webcomic")
      if (RegExp(r'^(manhwa|manga|manhua|webtoon|webcomic|comic)[\s/]+(manhwa|manga|manhua|webtoon|webcomic|comic)$', caseSensitive: false).hasMatch(lower)) continue;
      
      return cleaned;
    }
    
    // إذا لم نجد جزءاً مناسباً، ننظف العنوان بالكامل كملاذ أخير
    t = cleanSegment(t);
    if (t.isNotEmpty && t.length >= 3 && !genericKeywords.contains(t.toLowerCase())) {
      return t;
    }
    
    return rawTitle.replaceAll(RegExp(r'[|–\-—_~]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// استخراج slug المانغا/السلسلة من الرابط للمقارنة
  String _extractSeriesSlug(String url) {
    try {
      final uri = Uri.parse(url);
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      final seriesKeywords = ['series', 'manga', 'mangas', 'comic', 'comics', 'manhwa', 'manhwas', 'manhua', 'manhuas', 'title', 'titles', 'book', 'books', 'webtoon', 'webtoons', 'project', 'projects'];
      for (int i = 0; i < segments.length - 1; i++) {
        if (seriesKeywords.contains(segments[i].toLowerCase())) {
          return segments[i + 1].toLowerCase();
        }
      }
    } catch (_) {}
    return '';
  }

  /// استخراج رابط المانغا الأساسي من رابط الفصل
  String _getBaseMangaUrl(String chapterUrl) {
    try {
      final uri = Uri.parse(chapterUrl);
      
      // Webtoon handles it differently
      if (chapterUrl.contains('webtoons.com')) {
        final titleNo = uri.queryParameters['title_no'];
        if (titleNo != null) {
          return '${uri.scheme}://${uri.host}/en/manga/list?title_no=$titleNo';
        }
      }
      
      final segments = List<String>.from(uri.pathSegments.where((s) => s.isNotEmpty));
      
      // إزالة مقاطع الفصل الرقمية والنصية و UUID والحاويات بشكل متكرر من نهاية الرابط
      final containerSegments = {'episodes', 'chapters', 'read', 'reader', 'viewer'};
      bool removed = true;
      while (removed && segments.length > 0) {
        final lastSegment = segments.last.toLowerCase();
        if (RegExp(r'^\d+(\.\d+)?$').hasMatch(lastSegment) || 
            RegExp(r'^(ch|chapter|ep|episode|chap|c)[-_]?\d+', caseSensitive: false).hasMatch(lastSegment) ||
            RegExp(r'^(chapter|episode)$', caseSensitive: false).hasMatch(lastSegment) ||
            RegExp(r'^[0-9a-f]{24}$', caseSensitive: false).hasMatch(lastSegment) ||
            RegExp(r'^[0-9a-f]{32}$', caseSensitive: false).hasMatch(lastSegment) ||
            RegExp(r'^[0-9a-f]{8,}(-[0-9a-f]{4,}){2,}', caseSensitive: false).hasMatch(lastSegment) ||
            containerSegments.contains(lastSegment)) {
          if (segments.length == 1) {
            break;
          }
          segments.removeLast();
        } else {
          removed = false;
        }
      }

      // ─── ترقية للتعامل مع الروابط المسطحة (Flat URLs) ───
      if (segments.isNotEmpty) {
        final lastSeg = segments.last;
        final chapterInSlugRegex = RegExp(r'[-_](chapter|ch|episode|ep|chap|c)[-_]?\d+.*$', caseSensitive: false);
        final trailingNumberRegex = RegExp(r'[-_]\d+(\.\d+)?$');

        if (chapterInSlugRegex.hasMatch(lastSeg)) {
          final cleaned = lastSeg.replaceFirst(chapterInSlugRegex, '');
          if (cleaned.isNotEmpty && cleaned.length > 2) {
            segments[segments.length - 1] = cleaned;
          }
        } else if (trailingNumberRegex.hasMatch(lastSeg)) {
          final cleaned = lastSeg.replaceFirst(trailingNumberRegex, '');
          if (cleaned.isNotEmpty && cleaned.length > 2) {
            segments[segments.length - 1] = cleaned;
          }
        }
      }
      
      // تصفية معاملات الاستعلام لإزالة تلك المتعلقة بالفصول فقط والاحتفاظ بمعرف المانغا
      final chapterQueryKeys = ['episode', 'ep', 'chapter', 'ch', 'episode_id', 'chapter_id', 'content_id', 'page_id', 'chap', 'episodeid', 'chapterid', 'episodeno', 'chapterno'];
      final params = Map<String, String>.from(uri.queryParameters);
      // إزالة المعاملات المتعلقة بالفصول (case-insensitive)
      final keysToRemove = <String>[];
      for (final key in params.keys) {
        if (chapterQueryKeys.contains(key.toLowerCase())) {
          keysToRemove.add(key);
        }
      }
      for (final key in keysToRemove) {
        params.remove(key);
      }
      
      return uri.replace(pathSegments: segments, queryParameters: params).toString();
    } catch (_) {}
    return chapterUrl;
  }

  bool _isCloudflareOrError(String title) {
    final t = title.toLowerCase().trim();

    // صفحات Cloudflare وحماية DDoS
    if (t.contains('just a moment') || 
        t.contains('cloudflare') || 
        t.contains('attention required') || 
        t.contains('security check') ||
        t.contains('ddos protection')) {
      return true;
    }

    // أخطاء HTTP الشائعة (521, 502, 503, 404, 500, إلخ)
    if (RegExp(r'\b(5[0-9]{2}|4[0-9]{2})\b').hasMatch(t) &&
        (t.contains('error') || t.contains('web server') || t.contains('not found') ||
         t.contains('forbidden') || t.contains('bad gateway') || t.contains('unavailable') ||
         t.contains('down') || t.contains('timeout'))) {
      return true;
    }

    // عنوان يحتوي فقط على اسم نطاق (مثل "manhwaclan.com")
    if (RegExp(r'^[\w\-]+\.[\w\-]+(\.\w+)?$').hasMatch(t)) {
      return true;
    }

    // عنوان يبدأ باسم نطاق + خطأ (مثل "manhwaclan.com | 521: Web server is down")
    if (RegExp(r'^[\w\-]+\.[\w\-]+(\.\w+)?\s*\|\s*\d+').hasMatch(t)) {
      return true;
    }

    // صفحات خطأ عامة
    if (t.contains('access denied') || t.contains('server error') ||
        t.contains('web server is down') || t.contains('site maintenance') ||
        t.contains('temporarily unavailable') || t.contains('under maintenance') ||
        t.contains('service unavailable') || t.contains('page not found') ||
        t == 'error' || t == 'blocked') {
      return true;
    }

    return false;
  }

  /// تحليل JSON بشكل آمن يدعم استخراج غلاف base64
  Map<String, dynamic> _parseJsonSafe(String raw) {
    try {
      String cleaned = raw.trim();
      // إذا كانت السلسلة مغلفة بعلامات اقتباس مزدوجة إضافية (بسبب WebView)
      if (cleaned.startsWith('"') && cleaned.endsWith('"')) {
        try {
          final decodedString = json.decode(cleaned) as String;
          return json.decode(decodedString) as Map<String, dynamic>;
        } catch (_) {}
      }
      return json.decode(cleaned) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('⚠️ JSON decode failed, using regex fallback: $e');
      try {
        String cleaned = raw;
        if (cleaned.startsWith('"') && cleaned.endsWith('"')) {
          cleaned = cleaned.substring(1, cleaned.length - 1);
          cleaned = cleaned.replaceAll(r'\"', '"');
        }
        final titleMatch = RegExp(r'"title"\s*:\s*"([^"]*)"').firstMatch(cleaned);
        final imageMatch = RegExp(r'"image"\s*:\s*"([^"]*)"').firstMatch(cleaned);
        final urlMatch   = RegExp(r'"url"\s*:\s*"([^"]*)"').firstMatch(cleaned);
        final coverMatch = RegExp(r'"coverBase64"\s*:\s*"([^"]*)"').firstMatch(cleaned);

        return {
          'title': titleMatch?.group(1) ?? '',
          'image': imageMatch?.group(1) ?? '',
          'url':   urlMatch?.group(1) ?? '',
          'coverBase64': coverMatch?.group(1) ?? '',
        };
      } catch (_) {
        return {};
      }
    }
  }

  void _handleWindowOpenRedirect(InAppWebViewController controller, String url) async {
    final cleanUrl = url.trim();
    if (cleanUrl.isEmpty || cleanUrl.startsWith('javascript:')) return;
    
    final currentUrl = ref.read(browserProvider).currentUrl;
    final currentUri = Uri.tryParse(currentUrl);
    
    // محاولة تحليل الرابط المستهدف
    Uri? targetUri = Uri.tryParse(cleanUrl);
    if (targetUri == null) return;
    
    // إذا كان الرابط نسبيًا (مثال: /chapter-2)
    if (!cleanUrl.startsWith('http://') && !cleanUrl.startsWith('https://')) {
      if (currentUri != null) {
        final base = '${currentUri.scheme}://${currentUri.host}';
        targetUri = Uri.tryParse('$base${cleanUrl.startsWith('/') ? '' : '/'}$cleanUrl');
      }
    }
    
    if (currentUri != null && targetUri != null) {
      final currentHost = currentUri.host.toLowerCase();
      final targetHost = targetUri.host.toLowerCase();
      
      // إذا كان الرابط الجديد في نفس الموقع أو نطاق فرعي منه، أو نطاق فارغ/نسبي
      if (targetHost == currentHost || 
          targetHost.endsWith('.$currentHost') || 
          targetHost.isEmpty) {
        debugPrint('🔗 Navigating current tab to hijacked destination URL: ${targetUri.toString()}');
        await controller.loadUrl(urlRequest: URLRequest(url: WebUri(targetUri.toString())));
      } else {
        debugPrint('🛑 Blocked window.open redirect to ad: $cleanUrl');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final browserNotifier = ref.read(browserProvider.notifier);
    final browserState = ref.watch(browserProvider);
    final adBlockEnabled = ref.watch(settingsProvider).adBlockEnabled;
    final isSearchFocused = ref.watch(isSearchFocusedProvider);
    final suggestions = ref.watch(searchSuggestionsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      // ─── زر استخراج الفصل (FAB) ──────────────
      floatingActionButton: _isMangaChapterPage(browserState.currentUrl)
        ? ElevatedButton.icon(
            onPressed: (browserState.isLoading || _isExtracting) ? null : () => _extractChapter(context, ref),
            icon: _isExtracting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.auto_fix_high_rounded, color: Colors.white),
            label: Text(
                _isExtracting
                    ? 'جاري استخراج الفصل...'
                    : (browserState.detectedImageCount > 0 
                        ? 'استخراج الفصل (${browserState.detectedImageCount} صورة)'
                        : 'استخراج الفصل'),
                style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 8,
              shadowColor: AppColors.primary.withOpacity(0.5),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
            ),
          )
        : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                // ─── شريط العنوان ────────
                const UrlBar(),

                // ─── شريط التقدم ────────
                if (browserState.isLoading)
                  LinearProgressIndicator(
                    value: browserState.progress > 0 ? browserState.progress : null,
                    backgroundColor: Colors.transparent,
                    color: AppColors.primary,
                    minHeight: 2,
                  ),

                // ─── المتصفح ───────────
                Expanded(
                  child: IndexedStack(
                    index: browserState.activeTabIndex,
                    children: browserState.tabs.map((tab) {
                      return InAppWebView(
                        key: ValueKey(tab.id),
                        initialSettings: InAppWebViewSettings(
                          preferredContentMode: UserPreferredContentMode.MOBILE,
                          javaScriptEnabled: true,
                          transparentBackground: false,
                          supportZoom: true,
                          builtInZoomControls: false,
                          displayZoomControls: false,
                          mediaPlaybackRequiresUserGesture: true,
                          allowsInlineMediaPlayback: true,
                          mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
                          allowFileAccess: true,
                          hardwareAcceleration: true,
                          supportMultipleWindows: false,
                          javaScriptCanOpenWindowsAutomatically: false,
                          contentBlockers: adBlockEnabled ? AdBlockRules.rules : [],
                          useWideViewPort: true,
                          loadWithOverviewMode: true,
                          overScrollMode: OverScrollMode.IF_CONTENT_SCROLLS,
                          decelerationRate: ScrollViewDecelerationRate.NORMAL,
                          allowsBackForwardNavigationGestures: true,
                        ),
                        initialUserScripts: UnmodifiableListView<UserScript>([
                          UserScript(
                            source: '''
                              (function() {
                                // 1. منع النوافذ المنبثقة والإعلانات الإجبارية وتوجيه الروابط الآمنة
                                window.open = function(url, target, features) {
                                  if (url) {
                                    if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                                      window.flutter_inappwebview.callHandler('windowOpenHandler', url);
                                    } else {
                                      try {
                                        var currentHost = window.location.hostname;
                                        var targetUrl = new URL(url, window.location.href);
                                        if (targetUrl.hostname === currentHost) {
                                          window.location.href = url;
                                        }
                                      } catch(e) {}
                                    }
                                  }
                                  return null;
                                };

                                // 2. حماية النقر على الروابط التي تستهدف فتح نافذة جديدة
                                document.addEventListener('click', function(e) {
                                  var target = e.target;
                                  while (target && target.tagName !== 'A') {
                                    target = target.parentElement;
                                  }
                                  if (target && target.target === '_blank') {
                                    var href = target.href || '';
                                    if (href) {
                                      try {
                                        var currentHost = window.location.hostname;
                                        var targetUrl = new URL(href, window.location.href);
                                        var lowerHref = href.toLowerCase();
                                        var isAd = ['googlesyndication', 'doubleclick', 'adnxs', 'popads', 'popcash', 'exoclick', 'propellerads', 'adsterra', 'clickadu', 'monetag'].some(function(ad) {
                                          return lowerHref.indexOf(ad) !== -1;
                                        });
                                        if (isAd) {
                                          e.preventDefault();
                                          e.stopPropagation();
                                          return false;
                                        }
                                      } catch(e) {}
                                    }
                                  }
                                }, true);

                                // 3. إشعار التطبيق عند أي نقرة لإغلاق لوحة المفاتيح
                                document.addEventListener('click', function(e) {
                                  if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                                    window.flutter_inappwebview.callHandler('webViewClick');
                                  }
                                }, false);
                              })();
                            ''',
                            injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                          ),
                          UserScript(
                            source: '''
                              setInterval(function() {
                                if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                                   var imgs = document.querySelectorAll('img');
                                   var adDomains = [${ImageScraperService.adDomainsList}];
                                   var count = 0;
                                   for (var i = 0; i < imgs.length; i++) {
                                     var img = imgs[i];
                                     
                                     var isAdContainer = false;
                                     var parent = img.parentElement;
                                     var depth = 0;
                                     while (parent && depth < 3) {
                                       var parentId = parent.id || '';
                                       var parentClass = (typeof parent.className === 'string') ? parent.className : '';
                                       
                                       if (/\\b(ad-wrap|ad-box|ad-container|banner-ad|popunder|native-ad|ad_widget|live-chat|social-share|comment-box|comment-list|comments-area)\\b/i.test(parentId) ||
                                           /\\b(ad-wrap|ad-box|ad-container|banner-ad|popunder|native-ad|ad_widget|live-chat|social-share|comment-box|comment-list|comments-area)\\b/i.test(parentClass)) {
                                         isAdContainer = true;
                                         break;
                                       }
                                       parent = parent.parentElement;
                                       depth++;
                                     }
                                     if (isAdContainer) continue;

                                     var src = img.src || img.getAttribute('data-src') || img.getAttribute('data-lazy-src') || img.getAttribute('data-original') || '';
                                     if (!src || src.length < 10 || src.indexOf('data:') === 0) continue;
                                     
                                     var srcLower = src.toLowerCase();
                                     var imageExts = ['.jpg', '.jpeg', '.png', '.webp', '.avif', '.gif', '.bmp'];
                                     var hasImageExt = false;
                                     for (var e = 0; e < imageExts.length; e++) { if (srcLower.indexOf(imageExts[e]) !== -1) { hasImageExt = true; break; } }
                                     if (!hasImageExt) continue;
                                     
                                     var srcLower = src.toLowerCase();
                                     if (/[-_]\\d{2,4}x\\d{2,4}\\./i.test(src)) continue;
                                     if (srcLower.indexOf('cover') !== -1 && srcLower.indexOf('wp-content') !== -1) continue;
                                     
                                     var adUrlPatterns = ['/rec?', '/imp', 'token=', 'uuid=', 'tbg=', 'callback=', 'beacon', 'collect', 'event?', 'log?', '.gif?', '1x1', 'transparent', 'creative', 'extban'];
                                     var isTracker = false;
                                     for (var t = 0; t < adUrlPatterns.length; t++) { if (srcLower.indexOf(adUrlPatterns[t]) !== -1) { isTracker = true; break; } }
                                     if (isTracker) continue;
                                     
                                     var w = img.naturalWidth || img.width || 0;
                                     var h = img.naturalHeight || img.height || 0;
                                     var imgRect = img.getBoundingClientRect();
                                     var maxW = Math.max(w, imgRect.width);
                                     var maxH = Math.max(h, imgRect.height);
                                     
                                     if (maxW > 0 && maxH > 0 && maxW < 250 && maxH < 250) continue;
                                     
                                     var junkKeywords = ['logo', 'avatar', 'icon', 'sponsor', 'captcha', 'pixel', 'tracking', 'analytics', '1x1', 'live', 'widget'];
                                     var isJunk = false;
                                     for (var k = 0; k < junkKeywords.length; k++) { if (srcLower.indexOf(junkKeywords[k]) !== -1) { isJunk = true; break; } }
                                     if (isJunk) continue;
                                     
                                     var isAd = false;
                                     for (var d = 0; d < adDomains.length; d++) { if (srcLower.indexOf(adDomains[d]) !== -1) { isAd = true; break; } }
                                     if (isAd) continue;
                                     
                                     count++;
                                   }
                                   window.flutter_inappwebview.callHandler('imageCountHandler', count);
                                }
                              }
                            }, 1500);
                          ''',
                            injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
                          ),
                          if (adBlockEnabled)
                            UserScript(
                              source: '''
                                window.fuckAdBlock = {
                                  onDetected: function() {},
                                  onNotDetected: function() {},
                                  setOption: function() {}
                                };
                                window.BlockAdBlock = window.fuckAdBlock;
                                window.snigelPubConf = {
                                  adsetup: function() {}
                                };
                                
                                if (typeof window !== 'undefined') {
                                  window.Notification = function() {};
                                  window.Notification.requestPermission = function() { return Promise.resolve('denied'); };
                                  window.Notification.permission = 'denied';
                                }
                                
                                const adKeywords = ['ad', 'ads', 'banner', 'popup', 'bonus', 'claim', 'reward', 'sponsor', 'tracking', 'exoclick', 'popads', 'bet', 'casino'];
                                const isAdElement = (el) => {
                                   if (el.tagName === 'IFRAME') {
                                       if (!el.src || el.src === '') return true;
                                       const src = el.src.toLowerCase();
                                       if (adKeywords.some(k => src.includes(k))) return true;
                                       if (!src.includes('youtube.com') && !src.includes('disqus.com') && !src.includes('vimeo.com') && !src.includes('recaptcha') && !src.includes('cloudflare')) return true;
                                   }
                                   return false;
                                };

                                const observer = new MutationObserver((mutations) => {
                                  let shouldFixOverflow = false;
                                  for (const mutation of mutations) {
                                    if (mutation.type === 'childList') {
                                      mutation.addedNodes.forEach(node => {
                                         if (node.nodeType === 1) { 
                                             if (isAdElement(node)) {
                                                 node.remove();
                                             } else if (node.tagName && node.querySelectorAll) {
                                                 const iframes = node.querySelectorAll('iframe');
                                                 for(let i=0; i<iframes.length; i++) {
                                                     if(isAdElement(iframes[i])) iframes[i].remove();
                                                 }
                                             }
                                         }
                                      });
                                    }
                                  }
                                  if (document.body && document.body.style.overflow === 'hidden') {
                                    document.body.style.overflow = 'auto';
                                  }
                                });
                                
                                observer.observe(document.documentElement, { childList: true, subtree: true });
                                
                                document.addEventListener('DOMContentLoaded', () => {
                                    document.querySelectorAll('iframe').forEach(el => {
                                        if(isAdElement(el)) el.remove();
                                    });
                                });
                              ''',
                              injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                            )
                        ]),
                        initialUrlRequest: URLRequest(
                          url: WebUri(tab.currentUrl),
                        ),
                        onWebViewCreated: (webViewController) {
                          browserNotifier.setControllerForTab(tab.id, webViewController);
                          
                          // مسار إغلاق لوحة المفاتيح عند النقر في الويب
                          webViewController.addJavaScriptHandler(
                            handlerName: 'webViewClick',
                            callback: (args) {
                              FocusManager.instance.primaryFocus?.unfocus();
                              ref.read(isSearchFocusedProvider.notifier).state = false;
                            },
                          );

                          // مسار اكتشاف الصور
                          webViewController.addJavaScriptHandler(
                            handlerName: 'imageCountHandler',
                            callback: (args) {
                              if (args.isNotEmpty && args[0] is int) {
                                ref.read(browserProvider.notifier).updateImageCountForTab(tab.id, args[0]);
                              }
                            },
                          );
                          
                          // مسار إعادة توجيه التبويب الفعلي للروابط الآمنة التي تعترضها النوافذ المنبثقة
                          webViewController.addJavaScriptHandler(
                            handlerName: 'windowOpenHandler',
                            callback: (args) {
                              if (args.isNotEmpty) {
                                final targetUrl = args[0] as String;
                                _handleWindowOpenRedirect(webViewController, targetUrl);
                              }
                            },
                          );
                        },
                        onLoadResource: (webViewController, resource) {
                          final url = resource.url?.toString() ?? '';
                          if (url.isNotEmpty) {
                            ref.read(browserProvider.notifier).onResourceLoadedForTab(tab.id, url);
                          }
                        },
                         onScrollChanged: (webViewController, x, y) {
                          if (ref.read(isSearchFocusedProvider)) {
                            FocusManager.instance.primaryFocus?.unfocus();
                            ref.read(isSearchFocusedProvider.notifier).state = false;
                          }
                        },
                        onLoadStart: (webViewController, url) {
                          _lastExtractedUrl = null;
                          FocusManager.instance.primaryFocus?.unfocus();
                          ref.read(isSearchFocusedProvider.notifier).state = false;
                          if (url != null) {
                            browserNotifier.updateUrlForTab(tab.id, url.toString());
                          }
                          browserNotifier.updateLoadingForTab(tab.id, true);
                          browserNotifier.clearInterceptedImagesForTab(tab.id);
                          browserNotifier.updateNavigationStateForTab(tab.id);
                        },
                        onLoadStop: (webViewController, url) async {
                          final currentUrl = url?.toString() ?? '';
                          if (currentUrl.isNotEmpty) {
                            browserNotifier.updateUrlForTab(tab.id, currentUrl);
                          }
                          
                          final title = await webViewController.getTitle();
                          if (title != null) {
                            browserNotifier.updateTitleForTab(tab.id, title);
                          }
                          
                          browserNotifier.updateLoadingForTab(tab.id, false);
                          browserNotifier.updateProgressForTab(tab.id, 0.0);
                          browserNotifier.updateNavigationStateForTab(tab.id);

                          if (currentUrl.isNotEmpty) {
                            _extractAndSaveMetadata(webViewController, currentUrl);
                            
                            if (_isMangaChapterPage(currentUrl)) {
                              await webViewController.evaluateJavascript(source: '''
                                setTimeout(function() {
                                  var imgs = document.querySelectorAll('img');
                                  for(var i = 0; i < imgs.length; i++) {
                                    var img = imgs[i];
                                    var h = img.naturalHeight || img.height || 0;
                                    var w = img.naturalWidth || img.width || 0;
                                    if (h > 400 && w > 350) {
                                      img.scrollIntoView({ behavior: 'smooth', block: 'start' });
                                      break;
                                    }
                                  }
                                }, 1000);
                              ''');
                            }

                            // جدولة التقاط لقطة شاشة للتبويب بعد فترة وجيزة لتحديث صور المعاينة
                            Future.delayed(const Duration(milliseconds: 800), () {
                              if (context.mounted) {
                                ref.read(browserProvider.notifier).captureAndSaveScreenshot(tab.id);
                              }
                            });
                          }
                        },
                        onProgressChanged: (webViewController, progress) {
                          browserNotifier.updateProgressForTab(tab.id, progress / 100.0);
                        },
                        onUpdateVisitedHistory: (webViewController, url, isReload) {
                          if (url != null) {
                            final currentUrl = url.toString();
                            browserNotifier.updateUrlForTab(tab.id, currentUrl);
                            _extractAndSaveMetadata(webViewController, currentUrl);
                          }
                          browserNotifier.updateNavigationStateForTab(tab.id);
                        },
                        shouldOverrideUrlLoading: (webViewController, navigationAction) async {
                          final requestUrl = navigationAction.request.url?.toString() ?? '';
                          final requestUri = navigationAction.request.url;
                          
                          // 1. فلترة الإعلانات والبوب أب عند التوجيه التلقائي
                          final lowerUrl = requestUrl.toLowerCase();
                          final isAdDomain = [
                            'googlesyndication', 'googleadservices', 'doubleclick',
                            'adnxs', 'adsrvr', 'facebook.com/tr', 'amazon-adsystem',
                            'outbrain', 'taboola', 'mgid', 'popads', 'popcash',
                            'juicyads', 'exoclick', 'trafficjunky', 'propellerads',
                            'adsterra', 'criteo', 'rubiconproject', 'openx',
                            'monetag', 'a-ads', 'hilltopads', 'clickadu',
                            'onclickcreative', 'popunder', 'adkeeper', 'recreativ',
                            'adplay', 'adstars', 'exdynsrv', 'adxad', 'wigetmedia',
                          ].any((ad) => lowerUrl.contains(ad));

                          if (isAdDomain) {
                            debugPrint('🛑 Blocked known ad domain redirect: $requestUrl');
                            return NavigationActionPolicy.CANCEL;
                          }

                          // 2. حماية النطاق (Domain Protection Heuristics) لمنع إعادة التوجيه القسري للإعلانات المنبثقة
                          final currentUrl = ref.read(browserProvider).currentUrl;
                          if (currentUrl.isNotEmpty && 
                              currentUrl != 'about:blank' && 
                              !currentUrl.contains('google.com/search') &&
                              !currentUrl.contains('google.com/')) {
                            
                            final currentUri = Uri.tryParse(currentUrl);
                            if (currentUri != null && requestUri != null) {
                              final currentHost = currentUri.host.toLowerCase();
                              final requestHost = requestUri.host.toLowerCase();
                              
                              // إذا تغير النطاق بالكامل وكان النطاق الجديد غير معروف وليس فرعياً من النطاق الحالي
                              if (requestHost != currentHost && 
                                  !requestHost.endsWith('.$currentHost') &&
                                  requestHost.isNotEmpty) {
                                
                                // السماح بالنطاقات الموثوقة الأساسية فقط (مثل حسابات جوجل، أو فيسبوك للتسجيل، أو خدمات الدفع والترجمة)
                                final isTrustedHost = [
                                  'google.com', 'accounts.google.com', 'apis.google.com',
                                  'facebook.com', 'm.facebook.com', 'twitter.com',
                                  'github.com', 'apple.com', 'cloudflare.com',
                                ].any((trusted) => requestHost == trusted || requestHost.endsWith('.$trusted'));
                                
                                if (!isTrustedHost) {
                                  debugPrint('🛑 Blocked unauthorized popup redirect to: $requestUrl from current page: $currentUrl');
                                  return NavigationActionPolicy.CANCEL; // إلغاء إعادة التوجيه الإعلاني المنبثق!
                                }
                              }
                            }
                          }

                          return NavigationActionPolicy.ALLOW;
                        },
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
            
            // ─── لوحة مقترحات البحث العائمة ───
            if (isSearchFocused && suggestions.isNotEmpty)
              Positioned(
                top: 56, // مباشرة أسفل شريط العنوان الذي ارتفاعه 56
                left: 12,
                right: 12,
                child: TapRegion(
                  groupId: 'search_bar_region',
                  child: Material(
                    elevation: 8,
                    borderRadius: BorderRadius.circular(8),
                    color: AppColors.surfaceElevated,
                    child: Container(
                      constraints: const BoxConstraints(maxHeight: 250),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.border, width: 1.0),
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: suggestions.length,
                        separatorBuilder: (context, index) => const Divider(
                          color: AppColors.border,
                          height: 1,
                        ),
                        itemBuilder: (context, index) {
                          final suggestion = suggestions[index];
                          return ListTile(
                            leading: const Icon(
                              Icons.search_rounded,
                              color: AppColors.textSecondary,
                              size: 20,
                            ),
                            title: Text(
                              suggestion,
                              style: GoogleFonts.cairo(
                                color: AppColors.textPrimary,
                                fontSize: 14,
                              ),
                            ),
                            onTap: () {
                              // الانتقال للبحث في جوجل بعد تحويل الكلمة إلى رابط
                              final input = suggestion.trim();
                              final lowerInput = input.toLowerCase();
                              if (lowerInput.startsWith('http://') || lowerInput.startsWith('https://')) {
                                browserNotifier.navigateTo(input);
                              } else {
                                final searchQuery = Uri.encodeComponent(input);
                                browserNotifier.navigateTo('https://www.google.com/search?q=$searchQuery');
                              }
  
                              // إخفاء الكيبورد ووضع البحث
                              FocusScope.of(context).unfocus();
                              ref.read(isSearchFocusedProvider.notifier).state = false;
                              ref.read(searchSuggestionsProvider.notifier).state = [];
                            },
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: BrowserControls(
        onHomeTap: () {
          ref.read(navigationProvider.notifier).state = 0;
        },
      ),
    );
  }

  /// ─── استخراج صور الفصل وفتح شاشة المعاينة ──────────
  Future<void> _extractChapter(BuildContext context, WidgetRef ref) async {
    final controller = ref.read(browserProvider).controller;
    if (controller == null) return;

    setState(() {
      _isExtracting = true;
    });

    try {
      // عرض رسالة الاستخراج
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('جاري استخراج صور الفصل...',
              style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 4),
        ),
      );

      final imageUrls = await ImageScraperService.extractChapterImages(
        controller,
        networkInterceptedUrls: ref.read(browserProvider).interceptedImageUrls,
      );

      if (!context.mounted) return;

      if (imageUrls.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('لم يتم العثور على صور مانغا في هذه الصفحة',
                style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
        return;
      }

      // تحميل الفصل مع تمرير المتصفح لتجاوز حماية Hotlink
      final browserState = ref.read(browserProvider);
      
      // مسح الكاش القديم لهذا الفصل لمنع استخدام بيانات فاسدة
      await ChapterCacheService.clearAllCache();
      
      // فتح شاشة المعاينة فوراً
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ChapterPreviewScreen()),
      );

      // بدء تحميل الصور في الخلفية (الشاشة ستتحدث تلقائياً عبر Riverpod)
      ref.read(readerProvider.notifier).loadChapter(
        title: browserState.title.isNotEmpty ? browserState.title : 'فصل',
        sourceUrl: browserState.currentUrl,
        imageUrls: imageUrls,
        webViewController: controller,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isExtracting = false;
        });
      }
    }
  }
}
