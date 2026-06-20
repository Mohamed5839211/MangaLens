import 'dart:async';
import 'package:flutter/material.dart';
import '../../scraper/base_scraper.dart';
import '../../scraper/models/manga_metadata.dart';
import '../../../widgets/safe_network_image.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/reading_progress_service.dart';

/// شاشة القراءة الكاملة مع تنقل بين الفصول + حفظ تقدم تلقائي
class NativeReaderScreen extends StatefulWidget {
  final BaseScraper scraper;
  final String chapterUrl;
  // context إضافي للتنقل بين الفصول
  final String? mangaUrl;
  final String? mangaTitle;
  final String? coverUrl;
  final List<ChapterMetadata>? chapters;
  final int? currentChapterIndex;

  const NativeReaderScreen({
    super.key,
    required this.scraper,
    required this.chapterUrl,
    this.mangaUrl,
    this.mangaTitle,
    this.coverUrl,
    this.chapters,
    this.currentChapterIndex,
  });

  @override
  State<NativeReaderScreen> createState() => _NativeReaderScreenState();
}

class _NativeReaderScreenState extends State<NativeReaderScreen> {
  List<String> _imageUrls = [];
  bool _isLoading = true;
  bool _showUI = true;

  late ScrollController _scrollController;
  Timer? _scrollSaveTimer;
  int _currentImageIndex = 0;

  late String _currentChapterUrl;
  late int _currentChapterIdx;

  @override
  void initState() {
    super.initState();
    _currentChapterUrl = widget.chapterUrl;
    _currentChapterIdx = widget.currentChapterIndex ?? 0;
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    _loadImages();
  }

  @override
  void dispose() {
    _scrollSaveTimer?.cancel();
    _saveScrollPosition();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final max = _scrollController.position.maxScrollExtent;
    if (max <= 0) return;
    final fraction = _scrollController.position.pixels / max;

    // حساب الصورة الحالية
    if (_imageUrls.isNotEmpty) {
      final idx = (fraction * _imageUrls.length).floor().clamp(0, _imageUrls.length - 1);
      if (idx != _currentImageIndex) {
        setState(() => _currentImageIndex = idx);
      }
    }

    // حفظ الموقع كل 3 ثوان
    _scrollSaveTimer?.cancel();
    _scrollSaveTimer = Timer(const Duration(seconds: 3), () {
      _saveScrollPosition();
    });

    // إذا وصل لنهاية الفصل → علّمه كمقروء
    if (fraction > 0.95) {
      _markCurrentChapterRead();
    }
  }

  void _saveScrollPosition() {
    if (widget.mangaUrl == null || !_scrollController.hasClients) return;
    final max = _scrollController.position.maxScrollExtent;
    if (max <= 0) return;
    final fraction = _scrollController.position.pixels / max;
    ReadingProgressService.saveScrollPosition(
      widget.mangaUrl!, _currentChapterUrl, fraction,
    );
  }

  void _markCurrentChapterRead() {
    if (widget.mangaUrl == null) return;
    ReadingProgressService.markChapterRead(
      widget.mangaUrl!,
      _currentChapterUrl,
      mangaTitle: widget.mangaTitle ?? '',
      coverUrl: widget.coverUrl ?? '',
      sourceUrl: widget.scraper.baseUrl,
      chapterTitle: _currentChapterTitle,
      chapterIndex: _currentChapterIdx,
    );
  }

  String get _currentChapterTitle {
    if (widget.chapters != null && _currentChapterIdx >= 0 && _currentChapterIdx < widget.chapters!.length) {
      return widget.chapters![_currentChapterIdx].title;
    }
    return 'Chapter';
  }

  bool get _hasPrevChapter {
    if (widget.chapters == null) return false;
    return _currentChapterIdx < widget.chapters!.length - 1;
  }

  bool get _hasNextChapter {
    if (widget.chapters == null) return false;
    return _currentChapterIdx > 0;
  }

  Future<void> _loadImages() async {
    setState(() => _isLoading = true);
    try {
      final list = await widget.scraper.getChapterImages(_currentChapterUrl);

      // حفظ تقدم القراءة
      if (widget.mangaUrl != null) {
        ReadingProgressService.markChapterRead(
          widget.mangaUrl!,
          _currentChapterUrl,
          mangaTitle: widget.mangaTitle ?? '',
          coverUrl: widget.coverUrl ?? '',
          sourceUrl: widget.scraper.baseUrl,
          chapterTitle: _currentChapterTitle,
          chapterIndex: _currentChapterIdx,
        );
      }

      if (mounted) {
        setState(() {
          _imageUrls = list;
          _isLoading = false;
          _currentImageIndex = 0;
        });

        // استعادة موقع التمرير
        if (widget.mangaUrl != null) {
          final savedPos = ReadingProgressService.getScrollPosition(
            widget.mangaUrl!, _currentChapterUrl,
          );
          if (savedPos > 0.01) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_scrollController.hasClients) {
                final target = _scrollController.position.maxScrollExtent * savedPos;
                _scrollController.animateTo(target,
                    duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
              }
            });
          }
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _goToChapter(int index) {
    if (widget.chapters == null || index < 0 || index >= widget.chapters!.length) return;
    _saveScrollPosition();
    setState(() {
      _currentChapterIdx = index;
      _currentChapterUrl = widget.chapters![index].url;
    });
    _scrollController.jumpTo(0);
    _loadImages();
  }

  void _nextChapter() {
    if (_hasNextChapter) _goToChapter(_currentChapterIdx - 1);
  }

  void _prevChapter() {
    if (_hasPrevChapter) _goToChapter(_currentChapterIdx + 1);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => setState(() => _showUI = !_showUI),
        child: Stack(
          children: [
            // ─── المحتوى الرئيسي ───
            _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : _imageUrls.isEmpty
                    ? const Center(child: Text('لا توجد صور', style: TextStyle(color: Colors.white, fontFamily: 'Cairo')))
                    : InteractiveViewer(
                        minScale: 1.0,
                        maxScale: 4.0,
                        child: ListView.builder(
                          controller: _scrollController,
                          cacheExtent: MediaQuery.of(context).size.height * 3,
                          itemCount: _imageUrls.length,
                          itemBuilder: (context, index) {
                            return SafeNetworkImage(
                              imageUrl: _imageUrls[index],
                              referrer: widget.scraper.baseUrl,
                              fit: BoxFit.fitWidth,
                              placeholder: (context) => const SizedBox(
                                height: 400,
                                child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
                              ),
                            );
                          },
                        ),
                      ),

            // ─── شريط علوي ───
            if (_showUI)
              Positioned(
                top: 0, left: 0, right: 0,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent],
                    ),
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back, color: Colors.white),
                            onPressed: () => Navigator.pop(context),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (widget.mangaTitle != null)
                                  Text(
                                    widget.mangaTitle!,
                                    style: const TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'Cairo'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                Text(
                                  _currentChapterTitle,
                                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          if (_imageUrls.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.8),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${_currentImageIndex + 1} / ${_imageUrls.length}',
                                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            // ─── شريط سفلي: تنقل بين الفصول ───
            if (_showUI && widget.chapters != null)
              Positioned(
                bottom: 0, left: 0, right: 0,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Colors.black.withValues(alpha: 0.9), Colors.transparent],
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // الفصل السابق (في RTL يكون على اليمين)
                          TextButton.icon(
                            onPressed: _hasPrevChapter ? _prevChapter : null,
                            icon: const Icon(Icons.arrow_back_ios, size: 16),
                            label: const Text('السابق', style: TextStyle(fontFamily: 'Cairo', fontSize: 13)),
                            style: TextButton.styleFrom(
                              foregroundColor: _hasPrevChapter ? Colors.white : Colors.white30,
                            ),
                          ),
                          // الفصل التالي
                          TextButton.icon(
                            onPressed: _hasNextChapter ? _nextChapter : null,
                            icon: const Icon(Icons.arrow_forward_ios, size: 16),
                            label: const Text('التالي', style: TextStyle(fontFamily: 'Cairo', fontSize: 13)),
                            style: TextButton.styleFrom(
                              foregroundColor: _hasNextChapter ? Colors.white : Colors.white30,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
