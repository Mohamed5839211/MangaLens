import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/models/manga_history.dart';
import '../../../core/models/site_bookmark.dart';
import '../../../core/services/history_service.dart';
import '../../downloads/models/saved_chapter.dart';
import '../../downloads/data/downloads_service.dart';
import '../../downloads/presentation/manga_saved_chapters_screen.dart';
import '../../settings/presentation/settings_screen.dart';
import '../providers/browser_provider.dart';
import '../../../core/providers/navigation_provider.dart';
import '../../../widgets/safe_network_image.dart';

class GroupedManga {
  final String mangaTitle;
  final List<SavedChapter> chapters;
  GroupedManga({required this.mangaTitle, required this.chapters});
}

class HomeDrawer extends ConsumerStatefulWidget {
  final VoidCallback onRefresh;
  const HomeDrawer({super.key, required this.onRefresh});

  @override
  ConsumerState<HomeDrawer> createState() => _HomeDrawerState();
}

class _HomeDrawerState extends ConsumerState<HomeDrawer> {
  List<SiteBookmark> _bookmarks = [];
  List<MangaHistory> _history = [];
  List<GroupedManga> _groupedMangas = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    if (!mounted) return;
    final bookmarks = HistoryService.getAllBookmarks();
    final history = HistoryService.getAllHistory();
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
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      if (url.contains('.') && !url.contains(' ')) {
        url = 'https://$url';
      } else {
        url = 'https://www.google.com/search?q=${Uri.encodeComponent(input.trim())}';
      }
    }
    final browserNotifier = ref.read(browserProvider.notifier);
    final navigationNotifier = ref.read(navigationProvider.notifier);
    Navigator.pop(context); // إغلاق القائمة الجانبية
    browserNotifier.openInNewTab(url);
    navigationNotifier.state = 1; // الانتقال لتبويب المتصفح
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
              if (!mounted) return;
              Navigator.pop(ctx);
              _loadData();
              widget.onRefresh();
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
              if (!mounted) return;
              Navigator.pop(ctx);
              _loadData();
              widget.onRefresh();
            },
            child: const Text('حذف', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  Widget _buildSavedChapterCover(SavedChapter chapter) {
    final coverFile = File('${chapter.folderPath}/cover.png');
    if (coverFile.existsSync()) {
      return Image.file(
        coverFile,
        key: ValueKey('${coverFile.path}_${coverFile.lastModifiedSync().millisecondsSinceEpoch}'),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildDefaultChapterCover(),
      );
    }

    try {
      final history = HistoryService.getAllHistory();
      MangaHistory? mangaHistory;
      try {
        mangaHistory = history.firstWhere(
          (h) => h.title.trim().toLowerCase() == chapter.mangaTitle.trim().toLowerCase()
        );
      } catch (_) {}
      
      if (mangaHistory == null) {
        for (final h in history) {
          final cleanHistoryTitle = h.title.trim().toLowerCase();
          final cleanFolderPath = chapter.folderPath.toLowerCase();
          final cleanChapterTitle = chapter.chapterTitle.toLowerCase();
          final cleanMangaTitle = chapter.mangaTitle.toLowerCase();
          
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
          return Image.file(
            localFile,
            key: ValueKey('${localFile.path}_${localFile.lastModifiedSync().millisecondsSinceEpoch}'),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _buildDefaultChapterCover(),
          );
        }
      }
    } catch (_) {}

    final firstPageFile = File('${chapter.folderPath}/image_0.png');
    if (firstPageFile.existsSync()) {
      return Image.file(
        firstPageFile,
        key: ValueKey('${firstPageFile.path}_${firstPageFile.lastModifiedSync().millisecondsSinceEpoch}'),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildDefaultChapterCover(),
      );
    }
    return _buildDefaultChapterCover();
  }

  Widget _buildDefaultChapterCover() {
    return Container(
      color: AppColors.surfaceBright,
      child: const Center(
        child: Icon(Icons.menu_book_rounded, color: AppColors.textSecondary, size: 24),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.background,
      child: DefaultTabController(
        length: 3,
        child: Column(
          children: [
            // رأس القائمة الجانبية مع شعار التطبيق
            Container(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 24,
                bottom: 16,
                left: 16,
                right: 16,
              ),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: AppColors.glassBorder, width: 1),
                ),
              ),
              child: Row(
                children: [
                  Flexible(
                    child: ShaderMask(
                      shaderCallback: (bounds) => AppColors.primaryGradient.createShader(bounds),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          'MangaLens',
                          maxLines: 1,
                          style: GoogleFonts.orbitron(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  const Icon(Icons.history_toggle_off_rounded, color: AppColors.primary),
                ],
              ),
            ),
            
            // شريط التبويبات للتنقل بين الأقسام
            TabBar(
              indicatorColor: AppColors.primary,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textSecondary,
              labelStyle: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13),
              unselectedLabelStyle: GoogleFonts.cairo(fontSize: 12),
              tabs: const [
                Tab(text: 'المفضلة'),
                Tab(text: 'سجل القراءة'),
                Tab(text: 'الفصول'),
              ],
            ),
            
            // محتوى التبويبات
            Expanded(
              child: TabBarView(
                children: [
                  _buildBookmarksTab(),
                  _buildHistoryTab(),
                  _buildSavedChaptersTab(),
                ],
              ),
            ),
            
            // الإعدادات والتذييل
            Container(
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: AppColors.glassBorder, width: 1),
                ),
                color: AppColors.surface,
              ),
              child: ListTile(
                leading: const Icon(Icons.settings_rounded, color: AppColors.textSecondary),
                title: Text(
                  'الإعدادات',
                  style: GoogleFonts.cairo(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                onTap: () async {
                  final navigator = Navigator.of(context);
                  final onRefresh = widget.onRefresh;
                  navigator.pop(); // إغلاق القائمة الجانبية
                  await navigator.push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  );
                  onRefresh();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBookmarksTab() {
    if (_bookmarks.isEmpty) {
      return _buildEmptyState(
        icon: Icons.bookmark_add_outlined,
        title: 'لا توجد مواقع مفضلة',
        subtitle: 'احفظ مواقع المانغا لتظهر هنا للوصول السريع',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _bookmarks.length,
      itemBuilder: (context, index) {
        final bookmark = _bookmarks[index];
        return ListTile(
          leading: Container(
            height: 36,
            width: 36,
            decoration: BoxDecoration(
              color: AppColors.surfaceBright,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.glassBorder, width: 1),
            ),
            child: ClipOval(
              child: bookmark.favicon != null && bookmark.favicon!.isNotEmpty
                  ? Image.network(
                      bookmark.favicon!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _buildBookmarkFallback(bookmark.name),
                    )
                  : _buildBookmarkFallback(bookmark.name),
            ),
          ),
          title: Text(
            bookmark.name,
            style: GoogleFonts.cairo(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            bookmark.url,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 20),
            onPressed: () => _confirmDeleteBookmark(bookmark),
          ),
          onTap: () => _openBookmark(bookmark),
        );
      },
    );
  }

  Widget _buildBookmarkFallback(String name) {
    return Center(
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: AppColors.primary,
        ),
      ),
    );
  }

  Widget _buildHistoryTab() {
    if (_history.isEmpty) {
      return _buildEmptyState(
        icon: Icons.menu_book_outlined,
        title: 'لا يوجد سجل قراءة',
        subtitle: 'ابدأ بقراءة فصول المانغا لحفظ تقدمك هنا',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _history.length,
      itemBuilder: (context, index) {
        final manga = _history[index];
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: Container(
            width: 42,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(8),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: manga.imageUrl.isNotEmpty
                  ? SafeNetworkImage(
                      imageUrl: manga.imageUrl,
                      referrer: manga.siteUrl,
                      fit: BoxFit.cover,
                      placeholder: (_) => const Center(child: Icon(Icons.image, size: 16)),
                    )
                  : const Center(child: Icon(Icons.book, size: 16)),
            ),
          ),
          title: Text(
            manga.title,
            style: GoogleFonts.cairo(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (manga.lastChapter.isNotEmpty)
                Text(
                  'آخر فصل: ${manga.lastChapter}',
                  style: GoogleFonts.cairo(
                    color: AppColors.primaryLight,
                    fontSize: 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              Text(
                _formatDateTime(manga.lastRead),
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 10,
                ),
              ),
            ],
          ),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 20),
            onPressed: () => _confirmDeleteHistory(manga),
          ),
          onTap: () => _openUrl(manga.lastChapterUrl),
        );
      },
    );
  }

  Widget _buildSavedChaptersTab() {
    if (_groupedMangas.isEmpty) {
      return _buildEmptyState(
        icon: Icons.folder_open_rounded,
        title: 'لا توجد فصول محفوظة',
        subtitle: 'احفظ الفصول لقراءتها بدون إنترنت',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _groupedMangas.length,
      itemBuilder: (context, index) {
        final group = _groupedMangas[index];
        final sampleChapter = group.chapters.first;
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: Container(
            width: 42,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(8),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _buildSavedChapterCover(sampleChapter),
            ),
          ),
          title: Text(
            group.mangaTitle,
            style: GoogleFonts.cairo(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${group.chapters.length} فصول محفوظة',
            style: GoogleFonts.cairo(
              color: AppColors.textSecondary,
              fontSize: 11,
            ),
          ),
          trailing: const Icon(Icons.arrow_forward_ios_rounded, color: AppColors.textSecondary, size: 14),
          onTap: () async {
            final navigator = Navigator.of(context);
            final onRefresh = widget.onRefresh;

            // تحديث توقيت أحدث فصل ليقفز المجلد للمرتبة الأولى
            if (group.chapters.isNotEmpty) {
              await ref.read(downloadsProvider).updateChapterSavedAt(
                group.chapters.first.id,
                DateTime.now(),
              );
            }
            if (!mounted) return;

            navigator.pop(); // إغلاق القائمة الجانبية
            await navigator.push(
              MaterialPageRoute(
                builder: (_) => MangaSavedChaptersScreen(mangaTitle: group.mangaTitle),
              ),
            );
            onRefresh();
          },
        );
      },
    );
  }

  Widget _buildEmptyState({required IconData icon, required String title, required String subtitle}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 36, color: AppColors.textSecondary.withOpacity(0.3)),
            const SizedBox(height: 12),
            Text(
              title,
              style: GoogleFonts.cairo(
                color: AppColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: GoogleFonts.cairo(
                color: AppColors.textSecondary.withOpacity(0.6),
                fontSize: 11,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.year}/${dt.month}/${dt.day}';
  }
}
