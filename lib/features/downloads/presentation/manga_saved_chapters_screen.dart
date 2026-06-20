import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/history_service.dart';

import '../models/saved_chapter.dart';
import '../data/downloads_service.dart';
import '../data/pdf_export_service.dart';
import 'saved_chapter_screen.dart';

class MangaSavedChaptersScreen extends ConsumerStatefulWidget {
  final String mangaTitle;

  const MangaSavedChaptersScreen({
    super.key,
    required this.mangaTitle,
  });

  @override
  ConsumerState<MangaSavedChaptersScreen> createState() => _MangaSavedChaptersScreenState();
}

class _MangaSavedChaptersScreenState extends ConsumerState<MangaSavedChaptersScreen> {
  List<SavedChapter> _chapters = [];
  bool _isLoading = true;
  late String _currentMangaTitle;
  String? _exportingChapterId;

  @override
  void initState() {
    super.initState();
    _currentMangaTitle = widget.mangaTitle;
    _loadChapters();
  }

  void _loadChapters() {
    final allChapters = ref.read(downloadsProvider).getSavedChapters();
    
    var mangaChapters = allChapters.where(
      (c) => c.mangaTitle.trim().toLowerCase() == _currentMangaTitle.trim().toLowerCase()
    ).toList();

    final savedOrder = ref.read(downloadsProvider).getChapterOrder(_currentMangaTitle);

    if (savedOrder != null && savedOrder.isNotEmpty) {
      final sortedList = <SavedChapter>[];
      final remainingList = <SavedChapter>[];

      for (final id in savedOrder) {
        final chapter = mangaChapters.where((c) => c.id == id).firstOrNull;
        if (chapter != null) {
          sortedList.add(chapter);
        }
      }

      for (final chapter in mangaChapters) {
        if (!savedOrder.contains(chapter.id)) {
          remainingList.add(chapter);
        }
      }

      _sortNatural(remainingList);
      _chapters = [...sortedList, ...remainingList];
    } else {
      _sortNatural(mangaChapters);
      _chapters = mangaChapters;
    }

    setState(() {
      _isLoading = false;
    });
  }

  void _sortNatural(List<SavedChapter> list) {
    list.sort((a, b) {
      final reg = RegExp(r'\d+(\.\d+)?');
      final matchA = reg.firstMatch(a.chapterTitle);
      final matchB = reg.firstMatch(b.chapterTitle);
      
      if (matchA != null && matchB != null) {
        final valA = double.tryParse(matchA.group(0)!) ?? 0.0;
        final valB = double.tryParse(matchB.group(0)!) ?? 0.0;
        return valA.compareTo(valB);
      }
      return a.chapterTitle.compareTo(b.chapterTitle);
    });
  }

  void _onReorder(int oldIndex, int newIndex) async {
    setState(() {
      if (oldIndex < newIndex) {
        newIndex -= 1;
      }
      final SavedChapter chapter = _chapters.removeAt(oldIndex);
      _chapters.insert(newIndex, chapter);
    });

    final orderedIds = _chapters.map((c) => c.id).toList();
    await ref.read(downloadsProvider).saveChapterOrder(_currentMangaTitle, orderedIds);
  }

  Future<void> _deleteChapter(SavedChapter chapter) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('حذف الفصل؟', style: GoogleFonts.cairo(color: Colors.white)),
        content: Text(
          'هل أنت متأكد أنك تريد حذف "${chapter.chapterTitle}"؟ لا يمكن التراجع عن هذا الإجراء.',
          style: GoogleFonts.cairo(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('إلغاء', style: GoogleFonts.cairo(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('حذف', style: GoogleFonts.cairo(color: AppColors.error)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ref.read(downloadsProvider).deleteChapter(chapter);
      _loadChapters();
      
      if (_chapters.isEmpty) {
        if (mounted) Navigator.pop(context);
      }
    }
  }

  Future<void> _exportPdf(SavedChapter chapter) async {
    setState(() {
      _exportingChapterId = chapter.id;
    });

    try {
      final savedPath = await ref.read(pdfExportProvider).exportAndSharePdf(chapter);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم حفظ الـ PDF بنجاح ✓\nتجد الملف في مجلد MangaLens في التخزين الأساسي للجهاز',
              style: GoogleFonts.cairo(fontWeight: FontWeight.w600, fontSize: 12),
            ),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ أثناء التصدير: $e', style: GoogleFonts.cairo()),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _exportingChapterId = null;
        });
      }
    }
  }

  Future<void> _showRenameChapterDialog(SavedChapter chapter) async {
    final textController = TextEditingController(text: chapter.chapterTitle);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('تعديل اسم الفصل', style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: textController,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: 'اسم الفصل الجديد',
            labelStyle: GoogleFonts.cairo(color: AppColors.textSecondary),
            enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.border)),
            focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.primary)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('إلغاء', style: GoogleFonts.cairo(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () => Navigator.pop(context, true),
            child: Text('حفظ', style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true && textController.text.trim().isNotEmpty) {
      final newTitle = textController.text.trim();
      if (newTitle != chapter.chapterTitle) {
        await ref.read(downloadsProvider).renameChapter(chapter, newTitle);
        _loadChapters();
      }
    }
  }

  Future<void> _showRenameMangaDialog() async {
    final textController = TextEditingController(text: _currentMangaTitle);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('تعديل اسم المانغا', style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'أدخل الاسم الجديد للمانغا. إذا أدخلت اسم مانغا موجودة مسبقاً، فسيتم دمج الفصول معها تلقائياً!',
              style: GoogleFonts.cairo(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: textController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'اسم المانغا الجديد',
                labelStyle: GoogleFonts.cairo(color: AppColors.textSecondary),
                enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.border)),
                focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.primary)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('إلغاء', style: GoogleFonts.cairo(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () => Navigator.pop(context, true),
            child: Text('حفظ', style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true && textController.text.trim().isNotEmpty) {
      final newTitle = textController.text.trim();
      if (newTitle.toLowerCase() != _currentMangaTitle.toLowerCase()) {
        setState(() {
          _isLoading = true;
        });
        
        await ref.read(downloadsProvider).renameManga(_currentMangaTitle, newTitle);
        
        setState(() {
          _currentMangaTitle = newTitle;
        });
        
        _loadChapters();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _currentMangaTitle,
          style: GoogleFonts.cairo(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined, color: Colors.white),
            tooltip: 'تعديل الاسم أو الدمج',
            onPressed: _showRenameMangaDialog,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _chapters.isEmpty
              ? _buildEmptyState()
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline_rounded, color: AppColors.primary, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'يمكنك سحب وإفلات الفصول لترتيبها حسب رغبتك. اضغط على أي فصل لبدء القراءة المتتالية المستمرة.',
                              style: GoogleFonts.cairo(
                                color: AppColors.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(color: AppColors.glassBorder, height: 1),

                    Expanded(
                      child: ReorderableListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        itemCount: _chapters.length,
                        onReorder: _onReorder,
                        itemBuilder: (context, index) {
                          final chapter = _chapters[index];
                          final isExporting = _exportingChapterId == chapter.id;
                          return Container(
                            key: ValueKey(chapter.id),
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceElevated,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppColors.glassBorder, width: 1),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.2),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => SavedChapterScreen(
                                      orderedChapters: _chapters,
                                      initialIndex: index,
                                    ),
                                  ),
                                );
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(12.0),
                                child: Row(
                                  children: [
                                    // 1. غلاف الفصل
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: SizedBox(
                                        width: 50,
                                        height: 70,
                                        child: _buildChapterCover(chapter),
                                      ),
                                    ),
                                    const SizedBox(width: 12),

                                    // 2. معلومات الفصل
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            chapter.chapterTitle,
                                            style: GoogleFonts.cairo(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              const Icon(Icons.image_outlined, color: AppColors.primary, size: 12),
                                              const SizedBox(width: 4),
                                              Flexible(
                                                child: Text(
                                                  '${chapter.imageCount} صفحة  ·  ${_formatDate(chapter.savedAt)}',
                                                  style: GoogleFonts.cairo(
                                                    color: AppColors.textSecondary,
                                                    fontSize: 11,
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
                                                  maxLines: 1,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),

                                    // 3. أزرار الإجراءات
                                    // تعديل اسم الفصل
                                    IconButton(
                                      icon: const Icon(Icons.edit_outlined, size: 19),
                                      color: AppColors.textSecondary,
                                      tooltip: 'تعديل اسم الفصل',
                                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                      padding: EdgeInsets.zero,
                                      onPressed: () => _showRenameChapterDialog(chapter),
                                    ),
                                    // تصدير PDF
                                    isExporting
                                        ? const SizedBox(
                                            width: 32,
                                            height: 32,
                                            child: Padding(
                                              padding: EdgeInsets.all(6.0),
                                              child: CircularProgressIndicator(
                                                color: AppColors.primary,
                                                strokeWidth: 2,
                                              ),
                                            ),
                                          )
                                        : IconButton(
                                            icon: const Icon(Icons.picture_as_pdf_rounded, size: 19),
                                            color: AppColors.primary,
                                            tooltip: 'تصدير كـ PDF',
                                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                            padding: EdgeInsets.zero,
                                            onPressed: () => _exportPdf(chapter),
                                          ),
                                    // حذف
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline_rounded, size: 19),
                                      color: AppColors.error,
                                      tooltip: 'حذف الفصل',
                                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                      padding: EdgeInsets.zero,
                                      onPressed: () => _deleteChapter(chapter),
                                    ),
                                    // مقبض السحب
                                    ReorderableDragStartListener(
                                      index: index,
                                      child: const Padding(
                                        padding: EdgeInsets.only(right: 2),
                                        child: Icon(
                                          Icons.drag_indicator_rounded,
                                          color: AppColors.textSecondary,
                                          size: 22,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.folder_open_rounded, size: 64, color: AppColors.textSecondary.withOpacity(0.4)),
          const SizedBox(height: 16),
          Text(
            'لا توجد فصول محفوظة لهذه القصة',
            style: GoogleFonts.cairo(color: AppColors.textSecondary, fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildChapterCover(SavedChapter chapter) {
    final coverFile = File('${chapter.folderPath}/cover.png');
    if (coverFile.existsSync()) {
      return Image.file(
        coverFile,
        key: ValueKey('${coverFile.path}_${coverFile.lastModifiedSync().millisecondsSinceEpoch}'),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildDefaultCover(),
      );
    }

    // محاولة المطابقة مع سجل القراءة
    try {
      final history = HistoryService.getAllHistory();
      final mangaHistory = history.where(
        (h) => h.title.trim().toLowerCase() == chapter.mangaTitle.trim().toLowerCase()
      ).firstOrNull;

      if (mangaHistory != null && mangaHistory.imageUrl.isNotEmpty) {
        final localFile = File(mangaHistory.imageUrl);
        if (localFile.existsSync()) {
          return Image.file(
            localFile,
            key: ValueKey('${localFile.path}_${localFile.lastModifiedSync().millisecondsSinceEpoch}'),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _buildDefaultCover(),
          );
        }
      }
    } catch (_) {}

    // أول صفحة كغلاف بديل
    final firstPageFile = File('${chapter.folderPath}/image_0.png');
    if (firstPageFile.existsSync()) {
      return Image.file(
        firstPageFile,
        key: ValueKey('${firstPageFile.path}_${firstPageFile.lastModifiedSync().millisecondsSinceEpoch}'),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildDefaultCover(),
      );
    }

    return _buildDefaultCover();
  }

  Widget _buildDefaultCover() {
    return Container(
      color: AppColors.surfaceBright,
      child: const Center(
        child: Icon(
          Icons.menu_book_rounded,
          color: AppColors.textSecondary,
          size: 20,
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}/${dt.month}/${dt.day}';
  }
}
