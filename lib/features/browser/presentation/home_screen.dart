
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/models/manga_history.dart';
import '../../../core/models/site_bookmark.dart';
import '../../../core/services/history_service.dart';
import '../providers/browser_provider.dart';
import '../../../core/providers/navigation_provider.dart';

import '../../downloads/models/saved_chapter.dart';
import '../../downloads/data/downloads_service.dart';

import '../../downloads/presentation/manga_saved_chapters_screen.dart';
import '../../../widgets/safe_network_image.dart';
import 'home_drawer.dart';
import '../../../core/services/update_service.dart';


class GroupedManga {
  final String mangaTitle;
  final List<SavedChapter> chapters;
  GroupedManga({required this.mangaTitle, required this.chapters});
}

/// الشاشة الرئيسية للمتصفح — مفضلة المستخدم + سجل القراءة
/// Browser Home: User Bookmarks + Smart Reading History
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with SingleTickerProviderStateMixin {
  List<SiteBookmark> _bookmarks = [];
  List<MangaHistory> _history = [];

  List<GroupedManga> _groupedMangas = [];
  
  late AnimationController _bgAnimController;

  @override
  void initState() {
    super.initState();
    _bgAnimController = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat(reverse: true);
    _refresh();
    
    // التحقق من وجود تحديثات تلقائياً عند بدء التشغيل
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdatesSilently();
    });
  }

  Future<void> _checkForUpdatesSilently() async {
    final updateInfo = await UpdateService.checkForUpdates();
    if (updateInfo != null && mounted) {
      UpdateService.showUpdateDialog(context, ref, updateInfo);
    }
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    // مسح كاش الصور لضمان تحميل الأغلفة المحدثة من القرص مباشرة
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    
    final bookmarks = HistoryService.getAllBookmarks();
    final history = HistoryService.getAllHistory();
    if (!mounted) return;
    final savedChapters = ref.read(downloadsProvider).getSavedChapters();
    
    // تجميع الفصول بحسب اسم المانغا
    final groupedMap = <String, List<SavedChapter>>{};
    for (final chapter in savedChapters) {
      final key = chapter.mangaTitle.trim();
      final match = groupedMap.keys.firstWhere(
        (k) => k.toLowerCase() == key.toLowerCase(),
        orElse: () => '',
      );
      if (match.isNotEmpty) {
        groupedMap[match]!.add(chapter);
      } else {
        groupedMap[key] = [chapter];
      }
    }

    final groupedMangas = groupedMap.entries.map((e) => GroupedManga(
      mangaTitle: e.key,
      chapters: e.value..sort((a, b) => b.savedAt.compareTo(a.savedAt)),
    )).toList();

    // فرز المانغات تنازلياً حسب توقيت أحدث فصل محفوظ فيها
    groupedMangas.sort((a, b) {
      if (a.chapters.isEmpty) return 1;
      if (b.chapters.isEmpty) return -1;
      return b.chapters.first.savedAt.compareTo(a.chapters.first.savedAt);
    });
    
    if (mounted) {
      setState(() {
        _bookmarks = bookmarks;
        _history = history;

        _groupedMangas = groupedMangas;
      });
    }
  }

  void _openUrl(String input) {
    if (input.isEmpty) return;
    String url = input.trim();
    
    // التحقق هل هذا رابط حقيقي باستخدام Uri.tryParse (يدعم كل أنواع الروابط)
    bool isValidUrl = false;
    
    // إذا كان يبدأ بـ http/https فهو رابط مباشر
    if (url.startsWith('http://') || url.startsWith('https://')) {
      isValidUrl = true;
    } else {
      // تحقق هل يبدو كرابط (يحتوي نقطة ولا مسافات)
      if (url.contains('.') && !url.contains(' ')) {
        url = 'https://$url';
        // تحقق إضافي من صلاحية الرابط
        final parsed = Uri.tryParse(url);
        isValidUrl = parsed != null && parsed.host.contains('.');
      }
    }
    
    if (!isValidUrl) {
      url = 'https://www.google.com/search?q=${Uri.encodeComponent(input.trim())}';
    }

    // التنقل للمتصفح (طبقة 1) وتحديث الرابط
    ref.read(browserProvider.notifier).openInNewTab(url);
    ref.read(navigationProvider.notifier).state = 1;
  }

  Future<void> _openBookmark(SiteBookmark bookmark) async {
    final updated = SiteBookmark(
      id: bookmark.id,
      name: bookmark.name,
      url: bookmark.url,
      favicon: bookmark.favicon,
      addedAt: DateTime.now(),
    );
    await HistoryService.addBookmark(updated);
    if (!mounted) return;
    _openUrl(bookmark.url);
  }

  @override
  void dispose() {
    _bgAnimController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // التحديث التلقائي عند العودة للصفحة الرئيسية من المتصفح
    ref.listen<int>(navigationProvider, (previous, next) {
      if (next == 0) {
        _refresh();
      }
    });

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: AppColors.background,
        extendBodyBehindAppBar: true,
        drawer: HomeDrawer(onRefresh: _refresh),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Stack(
        children: [
          // ─── تأثير التوهج الخلفي (Neon Glow) ────────
          AnimatedBuilder(
            animation: _bgAnimController,
            builder: (context, child) {
              final scale = 1.0 + (_bgAnimController.value * 0.2);
              return Positioned(
                top: -100 + (_bgAnimController.value * 20),
                left: -100 - (_bgAnimController.value * 10),
                child: Transform.scale(
                  scale: scale,
                  child: Container(
                    width: 300,
                    height: 300,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primary.withOpacity(0.15),
                      boxShadow: [
                        BoxShadow(color: AppColors.primary.withOpacity(0.2), blurRadius: 100, spreadRadius: 50),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          AnimatedBuilder(
            animation: _bgAnimController,
            builder: (context, child) {
              final scale = 1.0 + ((1.0 - _bgAnimController.value) * 0.15);
              return Positioned(
                top: 100 - (_bgAnimController.value * 30),
                right: -100 + (_bgAnimController.value * 20),
                child: Transform.scale(
                  scale: scale,
                  child: Container(
                    width: 250,
                    height: 250,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.accent.withOpacity(0.15),
                      boxShadow: [
                        BoxShadow(color: AppColors.accent.withOpacity(0.2), blurRadius: 100, spreadRadius: 50),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),

          RefreshIndicator(
            onRefresh: _refresh,
            color: AppColors.primary,
            backgroundColor: AppColors.surfaceElevated,
            child: CustomScrollView(
              slivers: [
                // ─── الشعار ────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 32, bottom: 24),
                  child: Column(
                    children: [
                      ShaderMask(
                        shaderCallback: (bounds) => AppColors.primaryGradient.createShader(bounds),
                        child: Text(
                          'MangaLens',
                          style: GoogleFonts.orbitron(
                            fontSize: 42,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: 2,
                          ),
                        ),
                      )
                      .animate(onPlay: (c) => c.repeat(reverse: true))
                      .moveY(begin: -4, end: 4, duration: 3.seconds, curve: Curves.easeInOutSine)
                      .shimmer(duration: 4.seconds, blendMode: BlendMode.overlay),
                      const SizedBox(height: 8),
                      Text(
                        _getGreeting(),
                        style: GoogleFonts.cairo(
                          color: AppColors.textSecondary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ).animate().fadeIn(delay: 200.ms),
                    ],
                  ),
                ),
              ),

          // ─── زر فتح المتصفح ────────
          SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: ElevatedButton.icon(
                  onPressed: () {
                    // إذا كان هناك رابط سابق، هو محفوظ في المتصفح نفسه
                    ref.read(navigationProvider.notifier).state = 1;
                  },
                  icon: const Icon(Icons.explore_rounded, color: Colors.white, size: 28),
                  label: Text(
                    'فتح المتصفح',
                    style: GoogleFonts.cairo(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    elevation: 12,
                    shadowColor: AppColors.primary.withOpacity(0.6),
                  ),
                ),
              ).animate().fadeIn(delay: 250.ms).slideY(begin: 0.1),
            ),
          ),

          // ─── قسم المفضلة ────────
          SliverToBoxAdapter(
            child: _buildSectionTitle(
              context.tr('bookmarks'),
              Icons.star_rounded,
            ),
          ),

          if (_bookmarks.isEmpty)
            SliverToBoxAdapter(child: _buildEmptyState(
              icon: Icons.bookmark_add_outlined,
              title: context.tr('no_bookmarks_title'),
              subtitle: context.tr('no_bookmarks_subtitle'),
            ))
          else
            SliverToBoxAdapter(
              child: SizedBox(
                height: 100,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _bookmarks.length > 3 ? 3 : _bookmarks.length,
                  itemBuilder: (context, index) {
                    final bookmark = _bookmarks[index];
                    return _BookmarkChip(
                      bookmark: bookmark,
                      onTap: () => _openBookmark(bookmark),
                      onLongPress: () => _confirmDeleteBookmark(bookmark),
                    );
                  },
                ),
              ).animate().fadeIn(delay: 300.ms),
            ),

          // ─── قسم متابعة القراءة ────────
          SliverToBoxAdapter(
            child: _buildSectionTitle(
              context.tr('continue_reading'),
              Icons.auto_stories_rounded,
              trailing: _history.isNotEmpty ? IconButton(
                icon: const Icon(Icons.delete_outline_rounded, color: AppColors.textSecondary, size: 20),
                onPressed: _confirmClearHistory,
              ) : null,
            ),
          ),

          if (_history.isEmpty)
            SliverToBoxAdapter(child: _buildEmptyState(
              icon: Icons.menu_book_outlined,
              title: context.tr('no_history_title'),
              subtitle: context.tr('no_history_subtitle'),
            ))
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  childAspectRatio: 0.55,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final displayHistory = _history.take(3).toList();
                    final manga = displayHistory[index];
                    return _MangaCard(
                      manga: manga,
                      onTap: () => _openUrl(manga.lastChapterUrl),
                      onDelete: () => _confirmDeleteHistory(manga),
                    ).animate(delay: (50 * index).ms).fadeIn().scale(
                      begin: const Offset(0.9, 0.9),
                      curve: Curves.easeOutBack,
                      duration: 400.ms,
                    );
                  },
                  childCount: _history.length > 3 ? 3 : _history.length,
                ),
              ),
            ),

          // ─── قسم الفصول المحفوظة ────────
          SliverToBoxAdapter(
            child: _buildSectionTitle(
              'الفصول المحفوظة',
              Icons.save_alt_rounded,
            ),
          ),

          if (_groupedMangas.isEmpty)
            SliverToBoxAdapter(child: _buildEmptyState(
              icon: Icons.folder_open_rounded,
              title: 'لا توجد فصول محفوظة',
              subtitle: 'قم بحفظ الفصول بعد ترجمتها لتتمكن من قراءتها وتصديرها كـ PDF',
            ))
          else
            SliverToBoxAdapter(
              child: SizedBox(
                height: 140,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _groupedMangas.length > 3 ? 3 : _groupedMangas.length,
                  itemBuilder: (context, index) {
                    final group = _groupedMangas[index];
                    final sampleChapter = group.chapters.first;
                    return GestureDetector(
                      onTap: () async {
                        // تحديث توقيت أحدث فصل ليقفز المجلد للمرتبة الأولى
                        if (group.chapters.isNotEmpty) {
                          await ref.read(downloadsProvider).updateChapterSavedAt(
                            group.chapters.first.id,
                            DateTime.now(),
                          );
                        }
                        if (context.mounted) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => MangaSavedChaptersScreen(mangaTitle: group.mangaTitle),
                            ),
                          ).then((_) => _refresh());
                        }
                      },
                      child: Container(
                        width: 100,
                        margin: const EdgeInsets.only(left: 12),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceElevated,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              // صورة الغلاف المحلية أو الشكل الافتراضي
                              _buildSavedChapterCover(sampleChapter),

                              // تأثير التظليل المتدرج الداكن لقراءة النصوص بوضوح
                              Positioned.fill(
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.bottomCenter,
                                      end: Alignment.topCenter,
                                      colors: [
                                        Colors.black.withOpacity(0.9),
                                        Colors.black.withOpacity(0.3),
                                        Colors.transparent,
                                      ],
                                      stops: const [0.0, 0.6, 1.0],
                                    ),
                                  ),
                                ),
                              ),

                              // النصوص فوق الغلاف
                              Positioned(
                                bottom: 8,
                                left: 6,
                                right: 6,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      group.mangaTitle,
                                      style: GoogleFonts.cairo(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 10,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      '${group.chapters.length} فصول محفوظة',
                                      style: GoogleFonts.cairo(
                                        color: AppColors.textSecondary,
                                        fontSize: 9,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.library_books_rounded,
                                          color: AppColors.primary,
                                          size: 9,
                                        ),
                                        const SizedBox(width: 2),
                                        Text(
                                          'مجلد محفوظ',
                                          style: GoogleFonts.cairo(
                                            color: AppColors.primary,
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ).animate(delay: (50 * index).ms).fadeIn().slideX();
                  },
                ),
              ),
            ),

          // مسافة أسفل
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 16, 12),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 20),
          const SizedBox(width: 8),
          Text(title, style: GoogleFonts.cairo(
            color: AppColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          )),
          const Spacer(),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _buildEmptyState({required IconData icon, required String title, required String subtitle}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      child: Column(
        children: [
          Icon(icon, size: 48, color: AppColors.textSecondary.withOpacity(0.4)),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          )),
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(
            color: AppColors.textSecondary.withOpacity(0.7),
            fontSize: 12,
          ), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return '☀️ صباح الخير، ماذا ستقرأ اليوم؟';
    if (hour < 18) return '🌤️ مساء الخير، استمتع بالقراءة!';
    return '🌙 مساء الخير، وقت مثالي للمانغا!';
  }

  void _confirmDeleteBookmark(SiteBookmark bookmark) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceBright,
        title: const Text('حذف المفضلة؟', style: TextStyle(color: AppColors.textPrimary)),
        content: Text('هل تريد إزالة "${bookmark.name}" من المفضلة؟',
            style: const TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.tr('cancel')),
          ),
          TextButton(
            onPressed: () async {
              await HistoryService.removeBookmark(bookmark.id);
              Navigator.pop(ctx);
              _refresh();
            },
            child: const Text('حذف', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteHistory(MangaHistory manga) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceBright,
        title: const Text('حذف من سجل القراءة؟', style: TextStyle(color: AppColors.textPrimary)),
        content: Text('هل تريد إزالة "${manga.title}" من سجل متابعة القراءة؟',
            style: const TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.tr('cancel')),
          ),
          TextButton(
            onPressed: () async {
              await HistoryService.deleteHistory(manga.id);
              Navigator.pop(ctx);
              _refresh();
            },
            child: const Text('حذف', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  void _confirmClearHistory() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceBright,
        title: Text(context.tr('clear_history'), style: const TextStyle(color: AppColors.textPrimary)),
        content: Text(context.tr('clear_history_confirm'),
            style: const TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.tr('cancel')),
          ),
          TextButton(
            onPressed: () async {
              await HistoryService.clearHistory();
              Navigator.pop(ctx);
              _refresh();
            },
            child: const Text('مسح', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  Widget _buildSavedChapterCover(SavedChapter chapter) {
    final coverFile = File('${chapter.folderPath}/cover.png');
    debugPrint('📂 [SavedCover] Checking cover: ${coverFile.path} (exists: ${coverFile.existsSync()})');
    if (coverFile.existsSync()) {
      return Image.file(
        coverFile,
        key: ValueKey('${coverFile.path}_${coverFile.lastModifiedSync().millisecondsSinceEpoch}'),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          debugPrint('⚠️ [SavedCover] Error loading cover.png: $error');
          return _buildDefaultChapterCover();
        },
      );
    }

    // محاولة جلب الغلاف الأصلي من سجل القراءة كـ fallback ذكي
    try {
      final history = HistoryService.getAllHistory();
      MangaHistory? mangaHistory;
      
      // 1. محاولة المطابقة المباشرة والكاملة أولاً
      try {
        mangaHistory = history.firstWhere(
          (h) => h.title.trim().toLowerCase() == chapter.mangaTitle.trim().toLowerCase()
        );
      } catch (_) {}
      
      // 2. إذا فشلت، نجرب المطابقة الذكية المرنة (إذا كان اسم المانجا الحقيقي موجوداً في مسار المجلد أو عنوان الفصل)
      if (mangaHistory == null) {
        for (final h in history) {
          final cleanHistoryTitle = h.title.trim().toLowerCase();
          final cleanFolderPath = chapter.folderPath.toLowerCase();
          final cleanChapterTitle = chapter.chapterTitle.toLowerCase();
          final cleanMangaTitle = chapter.mangaTitle.toLowerCase();
          
          // نتجنب مطابقة النصوص القصيرة جداً لمنع التداخلات الخاطئة
          if (cleanHistoryTitle.length > 3) {
            final safeHistoryTitle = cleanHistoryTitle.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
            if (cleanFolderPath.contains(cleanHistoryTitle) || 
                cleanFolderPath.contains(safeHistoryTitle) ||
                cleanChapterTitle.contains(cleanHistoryTitle) ||
                (cleanMangaTitle.length > 3 && cleanHistoryTitle.contains(cleanMangaTitle))) {
              mangaHistory = h;
              break;
            }
          }
        }
      }

      if (mangaHistory != null && mangaHistory.imageUrl.isNotEmpty) {
        final localFile = File(mangaHistory.imageUrl);
        if (localFile.existsSync()) {
          debugPrint('✅ [SavedCover] Using smart history cover fallback for ${chapter.mangaTitle} -> matched with ${mangaHistory.title}');
          return Image.file(
            localFile,
            key: ValueKey('${localFile.path}_${localFile.lastModifiedSync().millisecondsSinceEpoch}'),
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              debugPrint('⚠️ [SavedCover] Error loading history cover: $error');
              return _buildDefaultChapterCover();
            },
          );
        }
      }
    } catch (_) {}

    final firstPageFile = File('${chapter.folderPath}/image_0.png');
    debugPrint('📂 [SavedCover] Checking fallback first page: ${firstPageFile.path} (exists: ${firstPageFile.existsSync()})');
    if (firstPageFile.existsSync()) {
      return Image.file(
        firstPageFile,
        key: ValueKey('${firstPageFile.path}_${firstPageFile.lastModifiedSync().millisecondsSinceEpoch}'),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          debugPrint('⚠️ [SavedCover] Error loading image_0.png: $error');
          return _buildDefaultChapterCover();
        },
      );
    }
    return _buildDefaultChapterCover();
  }

  Widget _buildDefaultChapterCover() {
    return Container(
      color: AppColors.surfaceBright,
      child: const Center(
        child: Icon(
          Icons.menu_book_rounded,
          color: AppColors.textSecondary,
          size: 32,
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════
// ─── بطاقة موقع مفضل (Bookmark Chip) ────────────
// ══════════════════════════════════════════════════
class _BookmarkChip extends StatelessWidget {
  final SiteBookmark bookmark;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _BookmarkChip({
    required this.bookmark,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        width: 80,
        margin: const EdgeInsets.only(left: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 56,
              width: 56,
              decoration: BoxDecoration(
                color: AppColors.surfaceBright,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.glassBorder, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.2),
                    blurRadius: 15,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipOval(
                child: bookmark.favicon != null && bookmark.favicon!.isNotEmpty
                    ? Image.network(
                        bookmark.favicon!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _buildFallbackIcon(),
                      )
                    : _buildFallbackIcon(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              bookmark.name,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.white,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFallbackIcon() {
    return Center(
      child: Text(
        bookmark.name.isNotEmpty ? bookmark.name[0].toUpperCase() : '?',
        style: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════
// ─── بطاقة المانغا (History Card) ────────────────
// ══════════════════════════════════════════════════
class _MangaCard extends StatelessWidget {
  final MangaHistory manga;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const _MangaCard({
    required this.manga,
    required this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // صورة الغلاف
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // الصورة أو البديل
                    if (manga.imageUrl.isNotEmpty)
                      SafeNetworkImage(
                        key: ValueKey('${manga.imageUrl}_${manga.lastRead.millisecondsSinceEpoch}'),
                        imageUrl: manga.imageUrl,
                        referrer: manga.siteUrl,
                        fit: BoxFit.cover,
                        placeholder: (_) => _buildPlaceholder(),
                      )
                    else
                      _buildPlaceholder(),

                    // زر حذف فردي في الزاوية العلوية
                    if (onDelete != null)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: GestureDetector(
                          onTap: onDelete,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.6),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close_rounded,
                              color: Colors.redAccent,
                              size: 16,
                            ),
                          ),
                        ),
                      ),

                    // شارة الفصل
                    if (manga.lastChapter.isNotEmpty)
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                AppColors.primaryDark.withOpacity(0.9),
                                Colors.transparent,
                              ],
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.bookmark_rounded, color: Colors.white, size: 12),
                              const SizedBox(width: 4),
                              Text(
                                manga.lastChapter,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // اسم المانغا
          const SizedBox(height: 6),
          Text(
            manga.title,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: AppColors.surfaceBright,
      child: const Center(
        child: Icon(Icons.menu_book_rounded, color: AppColors.textSecondary, size: 32),
      ),
    );
  }
}
