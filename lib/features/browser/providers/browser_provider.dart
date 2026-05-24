import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/storage/secure_storage_service.dart';
import '../models/browser_tab.dart';

/// حالة المتصفح المتعدد التبويبات
/// Browser state model supporting multiple tabs
class BrowserState {
  final List<BrowserTab> tabs;
  final int activeTabIndex;

  const BrowserState({
    this.tabs = const [],
    this.activeTabIndex = 0,
  });

  /// الحصول على التبويب النشط حالياً
  BrowserTab get activeTab {
    if (tabs.isEmpty) return const BrowserTab(id: 'default');
    if (activeTabIndex < 0 || activeTabIndex >= tabs.length) {
      return tabs.first;
    }
    return tabs[activeTabIndex];
  }

  // ─── حقول متوافقة للوراء لتسهيل الانتقال ───
  String get currentUrl => activeTab.currentUrl;
  String get title => activeTab.title;
  bool get isLoading => activeTab.isLoading;
  bool get canGoBack => activeTab.canGoBack;
  bool get canGoForward => activeTab.canGoForward;
  double get progress => activeTab.progress;
  int get detectedImageCount => activeTab.detectedImageCount;
  InAppWebViewController? get controller => activeTab.controller;
  List<String> get interceptedImageUrls => activeTab.interceptedImageUrls;

  BrowserState copyWith({
    List<BrowserTab>? tabs,
    int? activeTabIndex,
  }) {
    return BrowserState(
      tabs: tabs ?? this.tabs,
      activeTabIndex: activeTabIndex ?? this.activeTabIndex,
    );
  }
}

/// مزود حالة المتصفح المتعدد التبويبات
/// Browser state notifier managing multiple tabs
class BrowserNotifier extends Notifier<BrowserState> {
  final _dio = Dio();

  @override
  BrowserState build() {
    Future.microtask(() => _loadPersistedTabs());

    final defaultTab = BrowserTab(
      id: 'tab_${DateTime.now().millisecondsSinceEpoch}',
      currentUrl: 'https://www.google.com',
    );
    return BrowserState(
      tabs: [defaultTab],
      activeTabIndex: 0,
    );
  }

  /// التقاط لقطة شاشة للتبويب وحفظها كمعاينة بصرية محلياً
  Future<void> captureAndSaveScreenshot(String tabId) async {
    try {
      // التحقق من أن التبويب المطلوب هو التبويب النشط حالياً لتجنب تصوير تبويبات الخلفية
      final activeTab = state.tabs[state.activeTabIndex];
      if (tabId != activeTab.id) return;

      final tab = state.tabs.firstWhere((t) => t.id == tabId, orElse: () => const BrowserTab(id: 'dummy'));
      if (tab.id == 'dummy' || tab.controller == null) return;
      
      // التحقق من أن حجم الـ WebView حقيقي (عرض وارتفاع > 0) لتفادي الأخطاء البرمجية من جانب النظام (width and height must be > 0)
      final hasSize = await tab.controller!.evaluateJavascript(
        source: 'window.innerWidth > 0 && window.innerHeight > 0'
      );
      if (hasSize != true) return;

      final screenshot = await tab.controller!.takeScreenshot(
        screenshotConfiguration: ScreenshotConfiguration(
          compressFormat: CompressFormat.JPEG,
          quality: 50, // جودة متوسطة توفيراً للذاكرة والمساحة
        ),
      );
      
      if (screenshot != null) {
        final dir = await getApplicationDocumentsDirectory();
        final previewDir = Directory('${dir.path}/tab_previews');
        if (!await previewDir.exists()) {
          await previewDir.create(recursive: true);
        }
        final file = File('${previewDir.path}/$tabId.jpg');
        await file.writeAsBytes(screenshot);
        
        state = state.copyWith(
          tabs: state.tabs.map((t) => t.id == tabId ? t.copyWith(screenshotPath: file.path) : t).toList(),
        );
        _saveTabsToStorage();
      }
    } catch (e) {
      debugPrint('⚠️ Failed to capture/save screenshot for tab $tabId: $e');
    }
  }

  /// استعادة التبويبات والتبويب النشط من التخزين الآمن
  Future<void> _loadPersistedTabs() async {
    try {
      final tabsJson = await SecureStorageService.getBrowserTabs();
      final activeIndex = await SecureStorageService.getActiveTabIndex();
      
      if (tabsJson != null && tabsJson.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(tabsJson);
        final persistedTabs = decoded.map((item) => BrowserTab.fromJson(item as Map<String, dynamic>)).toList();
        if (persistedTabs.isNotEmpty) {
          int validIndex = activeIndex;
          if (validIndex < 0 || validIndex >= persistedTabs.length) {
            validIndex = 0;
          }
          state = BrowserState(
            tabs: persistedTabs,
            activeTabIndex: validIndex,
          );
          return;
        }
      }
      
      // في حال عدم وجود تبويبات مخزنة، نحاول قراءة آخر رابط تمت زيارته
      final lastUrl = await SecureStorageService.getLastUrl();
      if (lastUrl != null && lastUrl.isNotEmpty && lastUrl != 'about:blank') {
        state = BrowserState(
          tabs: [
            BrowserTab(
              id: 'tab_${DateTime.now().millisecondsSinceEpoch}',
              currentUrl: lastUrl,
            )
          ],
          activeTabIndex: 0,
        );
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load persisted tabs: $e');
    }
  }

  /// حفظ قائمة التبويبات والتبويب النشط في التخزين الآمن
  Future<void> _saveTabsToStorage() async {
    try {
      final tabsList = state.tabs.map((tab) => tab.toJson()).toList();
      final tabsJson = jsonEncode(tabsList);
      await SecureStorageService.saveBrowserTabs(tabsJson, state.activeTabIndex);
    } catch (e) {
      debugPrint('⚠️ Failed to save tabs to storage: $e');
    }
  }

  /// جلب مقترحات البحث التنبؤية من Google
  Future<List<String>> fetchSearchSuggestions(String query) async {
    if (query.trim().isEmpty) return [];
    try {
      final response = await _dio.get<dynamic>(
        'https://suggestqueries.google.com/complete/search',
        queryParameters: {'client': 'firefox', 'q': query},
      );
      if (response.statusCode == 200 && response.data != null) {
        dynamic data = response.data;
        if (data is String) {
          data = jsonDecode(data);
        }
        if (data is List && data.length > 1) {
          final suggestionsList = data[1];
          if (suggestionsList is List) {
            return suggestionsList.map((e) => e.toString()).toList();
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ Failed to fetch suggestions: $e');
    }
    return [];
  }

  // ─── إدارة التبويبات الفردية باستخدام المعرّف (ID) ───

  /// تعيين متحكم لتبويب معين
  void setControllerForTab(String id, InAppWebViewController controller) {
    state = state.copyWith(
      tabs: state.tabs.map((tab) => tab.id == id ? tab.copyWith(controller: controller) : tab).toList(),
    );
  }

  /// تحديث رابط تبويب معين
  void updateUrlForTab(String id, String url) {
    state = state.copyWith(
      tabs: state.tabs.map((tab) => tab.id == id ? tab.copyWith(currentUrl: url) : tab).toList(),
    );
    if (state.activeTab.id == id) {
      SecureStorageService.saveLastUrl(url);
    }
    _saveTabsToStorage();
  }

  /// تحديث عنوان تبويب معين
  void updateTitleForTab(String id, String title) {
    state = state.copyWith(
      tabs: state.tabs.map((tab) => tab.id == id ? tab.copyWith(title: title) : tab).toList(),
    );
    _saveTabsToStorage();
  }

  /// تحديث حالة التحميل لتبويب معين
  void updateLoadingForTab(String id, bool isLoading) {
    state = state.copyWith(
      tabs: state.tabs.map((tab) => tab.id == id ? tab.copyWith(isLoading: isLoading) : tab).toList(),
    );
  }

  /// تحديث أزرار التنقل لتبويب معين
  Future<void> updateNavigationStateForTab(String id) async {
    final tab = state.tabs.firstWhere((t) => t.id == id, orElse: () => const BrowserTab(id: 'dummy'));
    if (tab.controller == null) return;
    final canGoBack = await tab.controller!.canGoBack();
    final canGoForward = await tab.controller!.canGoForward();
    state = state.copyWith(
      tabs: state.tabs.map((t) => t.id == id ? t.copyWith(canGoBack: canGoBack, canGoForward: canGoForward) : t).toList(),
    );
  }

  /// تحديث نسبة التحميل لتبويب معين
  void updateProgressForTab(String id, double progress) {
    state = state.copyWith(
      tabs: state.tabs.map((tab) => tab.id == id ? tab.copyWith(progress: progress) : tab).toList(),
    );
  }

  /// تحديث عدد الصور المكتشفة لتبويب معين
  void updateImageCountForTab(String id, int count) {
    state = state.copyWith(
      tabs: state.tabs.map((tab) => tab.id == id ? tab.copyWith(detectedImageCount: count) : tab).toList(),
    );
  }

  /// تسجيل رابط معترض لتبويب معين
  void onResourceLoadedForTab(String id, String url) {
    if (url.isEmpty || url.startsWith('data:')) return;
    final lower = url.toLowerCase();

    // فحص: هل هذا رابط صورة؟
    final isImage = const ['.jpg', '.jpeg', '.png', '.webp', '.avif', '.gif', '.bmp']
        .any((ext) => lower.contains(ext));
    if (!isImage) return;

    // فحص: هل هذا إعلان؟
    final isAd = _adDomains.any((ad) => lower.contains(ad));
    if (isAd) return;

    // فحص: استبعاد عناصر الواجهة الصغيرة
    final junk = ['logo', 'avatar', 'icon', 'favicon', 'pixel', '1x1', 'tracking', 'analytics', 'beacon'];
    if (junk.any((j) => lower.contains(j))) return;

    state = state.copyWith(
      tabs: state.tabs.map((tab) {
        if (tab.id == id) {
          if (!tab.interceptedImageUrls.contains(url)) {
            return tab.copyWith(
              interceptedImageUrls: [...tab.interceptedImageUrls, url],
            );
          }
        }
        return tab;
      }).toList(),
    );
  }

  /// مسح قائمة الصور المعترضة لتبويب معين
  void clearInterceptedImagesForTab(String id) {
    state = state.copyWith(
      tabs: state.tabs.map((tab) => tab.id == id ? tab.copyWith(interceptedImageUrls: const []) : tab).toList(),
    );
  }

  // ─── الدوال القديمة المتوافقة للوراء (تطبق على التبويب النشط) ───

  void setController(InAppWebViewController controller) {
    setControllerForTab(state.activeTab.id, controller);
  }

  void updateUrl(String url) {
    updateUrlForTab(state.activeTab.id, url);
  }

  void updateTitle(String title) {
    updateTitleForTab(state.activeTab.id, title);
  }

  void updateLoading(bool isLoading) {
    updateLoadingForTab(state.activeTab.id, isLoading);
  }

  Future<void> updateNavigationState() async {
    await updateNavigationStateForTab(state.activeTab.id);
  }

  void updateProgress(double progress) {
    updateProgressForTab(state.activeTab.id, progress);
  }

  void updateImageCount(int count) {
    updateImageCountForTab(state.activeTab.id, count);
  }

  void onResourceLoaded(String url) {
    onResourceLoadedForTab(state.activeTab.id, url);
  }

  void clearInterceptedImages() {
    clearInterceptedImagesForTab(state.activeTab.id);
  }

  // ─── إدارة وتعديل التبويبات المتعددة ───

  String _normalizeUrl(String url) {
    String u = url.trim().toLowerCase();
    if (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  /// فتح رابط في علامة تبويب جديدة وتفعيلها
  void openInNewTab(String url) {
    String formattedUrl = url.trim();

    if (formattedUrl.isNotEmpty && 
        formattedUrl != 'about:blank' && 
        !formattedUrl.startsWith('file://') &&
        !formattedUrl.startsWith('http://') &&
        !formattedUrl.startsWith('https://')) {
      if (formattedUrl.contains('.') && !formattedUrl.contains(' ')) {
        formattedUrl = 'https://$formattedUrl';
      } else {
        formattedUrl = 'https://www.google.com/search?q=${Uri.encodeComponent(formattedUrl)}';
      }
    } else if (formattedUrl.isEmpty) {
      formattedUrl = 'https://www.google.com';
    }

    // التحقق مما إذا كان الرابط موجوداً بالفعل في علامات التبويب المفتوحة (مع استثناء الصفحات العامة)
    final normUrl = _normalizeUrl(formattedUrl);
    final isGeneric = normUrl == 'https://www.google.com' ||
                      normUrl == 'about:blank' ||
                      normUrl.startsWith('https://www.google.com/search');

    if (!isGeneric) {
      final existingIndex = state.tabs.indexWhere(
        (tab) => _normalizeUrl(tab.currentUrl) == normUrl
      );
      if (existingIndex != -1) {
        // إذا كان التبويب موجوداً بالفعل، نقوم بتنشيطه وتجاوز إنشاء تبويب جديد
        setActiveTab(existingIndex);
        return;
      }
    }

    final newId = 'tab_${DateTime.now().millisecondsSinceEpoch}_${state.tabs.length}';
    final newTab = BrowserTab(
      id: newId,
      currentUrl: formattedUrl,
    );

    state = state.copyWith(
      tabs: [...state.tabs, newTab],
      activeTabIndex: state.tabs.length,
    );

    SecureStorageService.saveLastUrl(formattedUrl);
    _saveTabsToStorage();
  }

  /// إغلاق علامة تبويب معينة
  void closeTab(String id) {
    // حذف ملف صورة المعاينة للتبويب المغلق لحفظ مساحة التخزين
    try {
      final tab = state.tabs.firstWhere((t) => t.id == id, orElse: () => const BrowserTab(id: 'dummy'));
      if (tab.screenshotPath != null) {
        final file = File(tab.screenshotPath!);
        if (file.existsSync()) {
          file.deleteSync();
        }
      }
    } catch (e) {
      debugPrint('Failed to delete preview file on closing tab: $e');
    }

    if (state.tabs.length <= 1) {
      // إعادة تعيين التبويب الأخير بدلاً من حذفه بالكامل
      state = state.copyWith(
        tabs: [
          BrowserTab(
            id: 'tab_${DateTime.now().millisecondsSinceEpoch}',
            currentUrl: 'https://www.google.com',
          )
        ],
        activeTabIndex: 0,
      );
      _saveTabsToStorage();
      return;
    }

    final index = state.tabs.indexWhere((tab) => tab.id == id);
    if (index == -1) return;

    final newTabs = state.tabs.where((tab) => tab.id != id).toList();
    int newActiveIndex = state.activeTabIndex;

    if (state.activeTabIndex == index) {
      newActiveIndex = index < newTabs.length ? index : newTabs.length - 1;
    } else if (state.activeTabIndex > index) {
      newActiveIndex = state.activeTabIndex - 1;
    }

    state = state.copyWith(
      tabs: newTabs,
      activeTabIndex: newActiveIndex,
    );
    _saveTabsToStorage();
  }

  /// تفعيل تبويب معين
  void setActiveTab(int index) {
    if (index >= 0 && index < state.tabs.length) {
      // تصوير التبويب النشط القديم قبل التبديل لحفظ حالته بصرية
      final oldActiveId = state.activeTab.id;
      captureAndSaveScreenshot(oldActiveId);

      state = state.copyWith(activeTabIndex: index);
      SecureStorageService.saveLastUrl(state.tabs[index].currentUrl);
      _saveTabsToStorage();
    }
  }

  // ─── فلاتر الشبكة للإعلانات ───
  static const _adDomains = [
    'googlesyndication', 'googleadservices', 'doubleclick',
    'adnxs', 'adsrvr', 'facebook.com/tr', 'amazon-adsystem',
    'outbrain', 'taboola', 'mgid', 'popads', 'popcash',
    'juicyads', 'exoclick', 'trafficjunky', 'propellerads',
    'adsterra', 'criteo', 'rubiconproject', 'openx',
    'monetag', 'a-ads', 'hilltopads', 'clickadu',
  ];

  // ─── التنقل والتحكم ───

  Future<void> goBack() async {
    final controller = state.activeTab.controller;
    if (controller != null && state.activeTab.canGoBack) {
      await controller.goBack();
    }
  }

  Future<void> goForward() async {
    final controller = state.activeTab.controller;
    if (controller != null && state.activeTab.canGoForward) {
      await controller.goForward();
    }
  }

  Future<void> reload() async {
    await state.activeTab.controller?.reload();
  }

  Future<void> stopLoading() async {
    await state.activeTab.controller?.stopLoading();
  }

  Future<void> navigateTo(String url) async {
    String formattedUrl = url.trim();
    
    if (formattedUrl == 'about:blank' || formattedUrl.startsWith('file://')) {
      await state.activeTab.controller?.loadUrl(
        urlRequest: URLRequest(url: WebUri(formattedUrl)),
      );
      return;
    }

    if (!formattedUrl.startsWith('http://') &&
        !formattedUrl.startsWith('https://')) {
      if (formattedUrl.contains('.') && !formattedUrl.contains(' ')) {
        formattedUrl = 'https://$formattedUrl';
      } else {
        formattedUrl =
            'https://www.google.com/search?q=${Uri.encodeComponent(formattedUrl)}';
      }
    }
    await state.activeTab.controller?.loadUrl(
      urlRequest: URLRequest(url: WebUri(formattedUrl)),
    );
  }

  Future<void> goHome(String homeUrl) async {
    await navigateTo(homeUrl);
  }

  Future<Uint8List?> captureScreenshot() async {
    final controller = state.activeTab.controller;
    if (controller == null) return null;

    // التحقق من الحجم الفعلي لتفادي أخطاء النظام الناتجة عن أبعاد صفرية
    final hasSize = await controller.evaluateJavascript(
      source: 'window.innerWidth > 0 && window.innerHeight > 0'
    );
    if (hasSize != true) return null;

    return await controller.takeScreenshot(
      screenshotConfiguration: ScreenshotConfiguration(
        compressFormat: CompressFormat.PNG,
        quality: 100,
      ),
    );
  }
}

/// مزود المتصفح الرئيسي
final browserProvider =
    NotifierProvider<BrowserNotifier, BrowserState>(() {
  return BrowserNotifier();
});

/// مزود مقترحات البحث التنبؤية
final searchSuggestionsProvider = StateProvider<List<String>>((ref) => []);

/// مزود حالة تركيز حقل البحث
final isSearchFocusedProvider = StateProvider<bool>((ref) => false);
