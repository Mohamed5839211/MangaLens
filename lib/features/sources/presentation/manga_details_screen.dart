import 'package:flutter/material.dart';
import '../../scraper/models/manga_metadata.dart';
import '../../scraper/base_scraper.dart';
import '../../../widgets/safe_network_image.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/reading_progress_service.dart';
import '../../../core/models/reading_progress.dart';
import 'native_reader_screen.dart';

class MangaDetailsScreen extends StatefulWidget {
  final BaseScraper scraper;
  final String mangaUrl;
  final String? initialCoverUrl;
  final String? initialTitle;

  const MangaDetailsScreen({
    super.key,
    required this.scraper,
    required this.mangaUrl,
    this.initialCoverUrl,
    this.initialTitle,
  });

  @override
  State<MangaDetailsScreen> createState() => _MangaDetailsScreenState();
}

class _MangaDetailsScreenState extends State<MangaDetailsScreen> {
  MangaMetadata? _manga;
  bool _isLoading = true;
  ReadingProgress? _progress;

  @override
  void initState() {
    super.initState();
    _loadDetails();
    _loadProgress();
  }

  Future<void> _loadDetails() async {
    try {
      var data = await widget.scraper.getMangaDetails(widget.mangaUrl);
      
      // إذا كان الغلاف فارغاً أو خطأ، نستخدم الغلاف القادم من شاشة الاستكشاف
      if (data.coverUrl.isEmpty && widget.initialCoverUrl != null) {
        data = data.copyWith(coverUrl: widget.initialCoverUrl!);
      }
      // إذا كان العنوان غير معروف، نستخدم العنوان القادم من شاشة الاستكشاف
      if ((data.title == 'Unknown' || data.title.isEmpty) && widget.initialTitle != null) {
        data = data.copyWith(title: widget.initialTitle!);
      }

      if (mounted) {
        setState(() {
          _manga = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ [Details] Error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _loadProgress() {
    final p = ReadingProgressService.getProgress(widget.mangaUrl);
    if (mounted) setState(() => _progress = p);
  }

  String get _coverUrl => _manga?.coverUrl ?? widget.initialCoverUrl ?? '';
  String get _title => _manga?.title ?? widget.initialTitle ?? '...';



  void _navigateToReader(int chapterIndex) {
    if (_manga == null || chapterIndex < 0 || chapterIndex >= _manga!.chapters.length) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NativeReaderScreen(
          scraper: widget.scraper,
          chapterUrl: _manga!.chapters[chapterIndex].url,
          mangaUrl: widget.mangaUrl,
          mangaTitle: _manga!.title,
          coverUrl: _manga!.coverUrl,
          chapters: _manga!.chapters,
          currentChapterIndex: chapterIndex,
        ),
      ),
    ).then((_) => _loadProgress());
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // ─── خلفية الغلاف ───
          Positioned(
            top: 0, left: 0, right: 0,
            height: screenHeight * 0.45,
            child: Stack(
              fit: StackFit.expand,
              children: [
                SafeNetworkImage(
                  imageUrl: _coverUrl,
                  referrer: widget.scraper.baseUrl,
                  fit: BoxFit.cover,
                  placeholder: (_) => Container(color: AppColors.surfaceElevated),
                ),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0.0, 0.5, 1.0],
                      colors: [
                        AppColors.background.withValues(alpha: 0.2),
                        AppColors.background.withValues(alpha: 0.7),
                        AppColors.background,
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ─── المحتوى ───
          CustomScrollView(
            slivers: [
              SliverAppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                expandedHeight: screenHeight * 0.35,
                pinned: true,
                flexibleSpace: FlexibleSpaceBar(
                  titlePadding: const EdgeInsets.only(left: 16, bottom: 16, right: 50),
                  title: Text(
                    _title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo',
                      shadows: [Shadow(color: Colors.black, blurRadius: 6)],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: _isLoading
                    ? const Padding(
                        padding: EdgeInsets.all(40),
                        child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
                      )
                    : _manga == null
                        ? const Padding(
                            padding: EdgeInsets.all(40),
                            child: Center(child: Text('خطأ في تحميل البيانات', style: TextStyle(color: Colors.white, fontFamily: 'Cairo'))),
                          )
                        : _buildDetailsContent(),
              ),
            ],
          ),

          // ─── قائمة الفصول القابلة للسحب (DraggableScrollableSheet) ───
          if (_manga != null && _manga!.chapters.isNotEmpty)
            _buildChaptersSheet(),
        ],
      ),
    );
  }

  Widget _buildDetailsContent() {
    final chapterCount = _manga!.chapters.length;
    final authorText = (_manga!.author != null && _manga!.author!.isNotEmpty) ? _manga!.author! : 'غير معروف';
    final descText = (_manga!.description != null && _manga!.description!.isNotEmpty) ? _manga!.description! : 'لا يوجد وصف متاح.';

    final hasProgress = _progress != null && _progress!.lastChapterUrl.isNotEmpty;
    final buttonText = hasProgress ? 'أكمل القراءة' : 'ابدأ القراءة';
    final buttonIcon = hasProgress ? Icons.play_circle_outline : Icons.play_arrow_rounded;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                _buildMetaRow('المصدر', Uri.parse(widget.scraper.baseUrl).host, Icons.language),
                const Divider(color: AppColors.divider, height: 24),
                _buildMetaRow('المؤلف', authorText, Icons.person),
                const Divider(color: AppColors.divider, height: 24),
                _buildMetaRow('الفصول', '$chapterCount فصل', Icons.menu_book),
              ],
            ),
          ),

          const SizedBox(height: 16),

          if (_manga!.chapters.isNotEmpty)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  if (hasProgress) {
                    final lastIdx = _progress!.lastChapterIndex.clamp(0, _manga!.chapters.length - 1);
                    _navigateToReader(lastIdx);
                  } else {
                    _navigateToReader(_manga!.chapters.length - 1);
                  }
                },
                icon: Icon(buttonIcon, size: 22),
                label: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(buttonText, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                    if (hasProgress)
                      Text(
                        _progress!.lastChapterTitle,
                        style: const TextStyle(fontSize: 11, fontFamily: 'Cairo'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: hasProgress ? AppColors.primary : AppColors.primary.withValues(alpha: 0.9),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),

          const SizedBox(height: 20),

          const Text('الوصف', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
          const SizedBox(height: 8),
          Text(descText, style: const TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.6, fontFamily: 'Cairo')),

          const SizedBox(height: 120), // مساحة للـ bottomSheet
        ],
      ),
    );
  }

  Widget _buildChaptersSheet() {
    return DraggableScrollableSheet(
      initialChildSize: 0.15,
      minChildSize: 0.15,
      maxChildSize: 0.85,
      snap: true,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 12, spreadRadius: 1)],
          ),
          child: Column(
            children: [
              // Header that acts as a drag handle
              GestureDetector(
                onVerticalDragUpdate: (details) {
                  // Allow dragging the handle to open the sheet
                  scrollController.position.jumpTo(scrollController.offset - details.delta.dy);
                },
                child: Container(
                  width: double.infinity,
                  color: Colors.transparent, // Important for hit testing
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    children: [
                      Container(
                        width: 40, height: 4,
                        decoration: BoxDecoration(color: Colors.grey[600], borderRadius: BorderRadius.circular(10)),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'الفصول (${_manga!.chapters.length})',
                        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(color: AppColors.divider, height: 1),
              
              // Scrollable list of chapters
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  physics: const ClampingScrollPhysics(), // Ensures it drags smoothly
                  padding: EdgeInsets.zero,
                  itemCount: _manga!.chapters.length,
                  separatorBuilder: (context, index) => const Divider(color: AppColors.divider, height: 1, indent: 16),
                  itemBuilder: (context, index) {
                    final chapterIdx = _manga!.chapters.length - 1 - index;
                    final chapter = _manga!.chapters[chapterIdx];
                    final isLastRead = _progress?.lastChapterUrl == chapter.url;
                    final isRead = _progress != null && chapterIdx <= _progress!.lastChapterIndex && !isLastRead;

                    return ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                      leading: isRead
                          ? const Icon(Icons.check_circle, color: AppColors.primary, size: 18)
                          : isLastRead
                              ? const Icon(Icons.pause_circle_outline, color: Colors.amber, size: 18)
                              : null,
                      title: Text(
                        chapter.title,
                        style: TextStyle(
                          color: isRead ? AppColors.textSecondary : Colors.white,
                          fontSize: 14,
                          fontFamily: 'Cairo',
                          fontWeight: isLastRead ? FontWeight.bold : FontWeight.normal,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Icon(Icons.chevron_right, color: AppColors.textSecondary, size: 20),
                      onTap: () => _navigateToReader(chapterIdx),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMetaRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: AppColors.textSecondary, size: 20),
        const SizedBox(width: 12),
        Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 14, fontFamily: 'Cairo')),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600, fontFamily: 'Cairo'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.start,
          ),
        ),
      ],
    );
  }
}
