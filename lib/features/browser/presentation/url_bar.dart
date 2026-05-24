import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/localization/app_localizations.dart';
import '../providers/browser_provider.dart';

class UrlBar extends ConsumerStatefulWidget {
  const UrlBar({super.key});

  @override
  ConsumerState<UrlBar> createState() => _UrlBarState();
}

class _UrlBarState extends ConsumerState<UrlBar> {
  final TextEditingController _urlController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _isEditing = false;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChanged);
    _urlController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _urlController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    final hasFocus = _focusNode.hasFocus;
    ref.read(isSearchFocusedProvider.notifier).state = hasFocus;
    setState(() {
      _isEditing = hasFocus;
      if (_isEditing) {
        final currentUrl = ref.read(browserProvider).currentUrl;
        
        bool isGoogleHome = false;
        try {
          final uri = Uri.parse(currentUrl);
          final host = uri.host.toLowerCase();
          final isGoogleHost = RegExp(r'^(www\.)?google\.[a-z\.]+$').hasMatch(host);
          if (isGoogleHost && 
              (uri.path == '/' || uri.path.isEmpty) && 
              !currentUrl.contains('/search')) {
            isGoogleHome = true;
          }
        } catch (_) {}

        if (currentUrl.isEmpty || currentUrl == 'about:blank' || isGoogleHome) {
          _urlController.text = '';
        } else if (currentUrl.contains('google.com/search')) {
          try {
            final uri = Uri.tryParse(currentUrl);
            final query = uri?.queryParameters['q'];
            if (query != null && query.isNotEmpty) {
              _urlController.text = Uri.decodeComponent(query);
            } else {
              _urlController.text = currentUrl;
            }
          } catch (_) {
            _urlController.text = currentUrl;
          }
        } else {
          _urlController.text = currentUrl;
        }

        _urlController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _urlController.text.length,
        );
      }
    });
  }

  void _onTextChanged() {
    if (!_isEditing) return; // جلب المقترحات فقط عندما يقوم المستخدم بالكتابة الفعلية
    
    setState(() {}); // لتحديث ظهور/إخفاء زر المسح فوراً
    
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    
    _debounceTimer = Timer(const Duration(milliseconds: 300), () async {
      final query = _urlController.text;
      if (query.trim().isNotEmpty) {
        final suggestions = await ref.read(browserProvider.notifier).fetchSearchSuggestions(query);
        ref.read(searchSuggestionsProvider.notifier).state = suggestions;
      } else {
        ref.read(searchSuggestionsProvider.notifier).state = [];
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final browserState = ref.watch(browserProvider);
    final browserNotifier = ref.read(browserProvider.notifier);

    if (!_isEditing && browserState.currentUrl.isNotEmpty) {
      _urlController.text = _formatDisplayUrl(browserState.currentUrl);
    }

    final currentUrl = browserState.currentUrl;

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(
          bottom: BorderSide(
            color: AppColors.border,
            width: 1.0,
          ),
        ),
      ),
      child: TapRegion(
        groupId: 'search_bar_region',
        child: Row(
          children: [
            // زر الصفحة الرئيسية للمتصفح (يفتح Google)
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: const Icon(
                Icons.language_rounded,
                color: AppColors.textPrimary,
                size: 24,
              ),
              onPressed: () {
                browserNotifier.navigateTo('https://www.google.com');
              },
            ),
            const SizedBox(width: 8),
            
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _isEditing ? AppColors.primary : Colors.transparent,
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    // أيقونة القفل / البحث
                    Padding(
                      padding: const EdgeInsetsDirectional.only(start: 12),
                      child: Icon(
                        currentUrl.startsWith('https') ? Icons.lock_rounded : Icons.search_rounded,
                        size: 16,
                        color: currentUrl.startsWith('https') && !_isEditing 
                            ? Colors.greenAccent 
                            : AppColors.textSecondary,
                      ),
                    ),
                    
                    const SizedBox(width: 8),
  
                    // Text Field عريض يتمدد لكامل العرض المتاح
                    Expanded(
                      child: TextField(
                        controller: _urlController,
                        focusNode: _focusNode,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          hintText: context.tr('search_or_type_url'),
                          hintStyle: const TextStyle(color: AppColors.textSecondary),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.go,
                        onSubmitted: (value) {
                          setState(() => _isEditing = false);
                          _focusNode.unfocus();
                          
                          final input = value.trim();
                          if (input.isNotEmpty) {
                            final lowerInput = input.toLowerCase();
                            if (lowerInput.startsWith('http://') ||
                                lowerInput.startsWith('https://') ||
                                lowerInput.startsWith('about:') ||
                                lowerInput.startsWith('file://')) {
                              browserNotifier.navigateTo(input);
                            } else if (input.contains('.') && !input.contains(' ')) {
                              browserNotifier.navigateTo('https://$input');
                            } else {
                              final searchQuery = Uri.encodeComponent(input);
                              browserNotifier.navigateTo('https://www.google.com/search?q=$searchQuery');
                            }
                          }
                        },
                        onTapOutside: (_) {
                          _focusNode.unfocus();
                        },
                      ),
                    ),
                    
                    // زر المسح (أثناء التحرير)
                    if (_isEditing && _urlController.text.isNotEmpty)
                      GestureDetector(
                        onTap: () => _urlController.clear(),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          child: Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      )
                    else
                      const SizedBox(width: 12),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDisplayUrl(String url) {
    if (url.isEmpty || url == 'about:blank') {
      return '';
    }

    // تحقق مما إذا كان الرابط هو الصفحة الرئيسية لجوجل (مع أو بدون معاملات زوائد مثل ?zx=...)
    try {
      final uri = Uri.parse(url);
      final host = uri.host.toLowerCase();
      final isGoogleHost = RegExp(r'^(www\.)?google\.[a-z\.]+$').hasMatch(host);
      if (isGoogleHost && 
          (uri.path == '/' || uri.path.isEmpty) && 
          !url.contains('/search')) {
        return ''; // تفريغ الشريط وعرض نص التلميح
      }
    } catch (_) {}

    // إذا كان رابط بحث في جوجل، نعرض فقط عبارة البحث المكتوبة بشكل نظيف
    if (url.contains('google.com/search')) {
      try {
        final uri = Uri.tryParse(url);
        final query = uri?.queryParameters['q'];
        if (query != null && query.isNotEmpty) {
          return Uri.decodeComponent(query);
        }
      } catch (e) {
        debugPrint('Error parsing search URL: $e');
      }
    }

    String display = url;
    display = display.replaceFirst('https://', '');
    display = display.replaceFirst('http://', '');
    display = display.replaceFirst('www.', '');
    if (display.endsWith('/')) {
      display = display.substring(0, display.length - 1);
    }
    return display;
  }
}
