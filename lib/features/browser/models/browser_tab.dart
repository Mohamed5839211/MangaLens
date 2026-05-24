import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class BrowserTab {
  final String id;
  final String currentUrl;
  final String title;
  final bool isLoading;
  final bool canGoBack;
  final bool canGoForward;
  final double progress;
  final int detectedImageCount;
  final InAppWebViewController? controller;
  final List<String> interceptedImageUrls;
  final String? screenshotPath;

  const BrowserTab({
    required this.id,
    this.currentUrl = 'https://www.google.com',
    this.title = 'علامة تبويب جديدة',
    this.isLoading = false,
    this.canGoBack = false,
    this.canGoForward = false,
    this.progress = 0.0,
    this.detectedImageCount = 0,
    this.controller,
    this.interceptedImageUrls = const [],
    this.screenshotPath,
  });

  BrowserTab copyWith({
    String? currentUrl,
    String? title,
    bool? isLoading,
    bool? canGoBack,
    bool? canGoForward,
    double? progress,
    int? detectedImageCount,
    InAppWebViewController? controller,
    List<String>? interceptedImageUrls,
    String? screenshotPath,
  }) {
    return BrowserTab(
      id: id,
      currentUrl: currentUrl ?? this.currentUrl,
      title: title ?? this.title,
      isLoading: isLoading ?? this.isLoading,
      canGoBack: canGoBack ?? this.canGoBack,
      canGoForward: canGoForward ?? this.canGoForward,
      progress: progress ?? this.progress,
      detectedImageCount: detectedImageCount ?? this.detectedImageCount,
      controller: controller ?? this.controller,
      interceptedImageUrls: interceptedImageUrls ?? this.interceptedImageUrls,
      screenshotPath: screenshotPath ?? this.screenshotPath,
    );
  }

  /// تحويل التبويب إلى JSON لحفظه محلياً
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'currentUrl': currentUrl,
      'title': title,
      'screenshotPath': screenshotPath,
    };
  }

  /// إنشاء تبويب من JSON
  factory BrowserTab.fromJson(Map<String, dynamic> json) {
    return BrowserTab(
      id: json['id'] as String? ?? 'tab_${DateTime.now().millisecondsSinceEpoch}',
      currentUrl: json['currentUrl'] as String? ?? 'https://www.google.com',
      title: json['title'] as String? ?? 'علامة تبويب جديدة',
      screenshotPath: json['screenshotPath'] as String?,
    );
  }
}
