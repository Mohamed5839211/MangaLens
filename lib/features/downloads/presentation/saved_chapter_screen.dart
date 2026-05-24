import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../data/downloads_service.dart';

import '../models/saved_chapter.dart';

abstract class ReaderItem {}

class PageItem extends ReaderItem {
  final SavedChapter chapter;
  final File imageFile;
  final int pageIndex;
  PageItem({required this.chapter, required this.imageFile, required this.pageIndex});
}

class TransitionItem extends ReaderItem {
  final SavedChapter currentChapter;
  final SavedChapter nextChapter;
  TransitionItem({required this.currentChapter, required this.nextChapter});
}

class SavedChapterScreen extends ConsumerStatefulWidget {
  final List<SavedChapter> orderedChapters;
  final int initialIndex;

  const SavedChapterScreen({
    super.key,
    required this.orderedChapters,
    required this.initialIndex,
  });

  @override
  ConsumerState<SavedChapterScreen> createState() => _SavedChapterScreenState();
}

class _SavedChapterScreenState extends ConsumerState<SavedChapterScreen> {
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<SavedChapter?> _currentChapter = ValueNotifier<SavedChapter?>(null);
  
  List<ReaderItem> _items = [];
  final Map<int, GlobalKey> _keys = {};
  bool _isLoading = true;


  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadAllPages();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _currentChapter.dispose();
    super.dispose();
  }

  Future<void> _loadAllPages() async {
    setState(() {
      _isLoading = true;
    });

    final List<ReaderItem> tempItems = [];
    
    for (int i = widget.initialIndex; i < widget.orderedChapters.length; i++) {
      final chapter = widget.orderedChapters[i];
      final images = await ref.read(downloadsProvider).getChapterImages(chapter);
      
      for (int p = 0; p < images.length; p++) {
        tempItems.add(PageItem(
          chapter: chapter,
          imageFile: images[p],
          pageIndex: p,
        ));
      }
      
      if (i < widget.orderedChapters.length - 1) {
        tempItems.add(TransitionItem(
          currentChapter: chapter,
          nextChapter: widget.orderedChapters[i + 1],
        ));
      }
    }

    if (mounted) {
      setState(() {
        _items = tempItems;
        _keys.clear();
        for (int idx = 0; idx < _items.length; idx++) {
          _keys[idx] = GlobalKey();
        }
        if (widget.orderedChapters.isNotEmpty) {
          final initialChapter = widget.orderedChapters[widget.initialIndex];
          _currentChapter.value = initialChapter;
          ref.read(downloadsProvider).updateChapterSavedAt(initialChapter.id, DateTime.now());
        }
        _isLoading = false;
      });
    }
  }

  void _onScroll() {
    if (!mounted || _keys.isEmpty || _isLoading) return;
    
    double? closestDistance;
    int closestIndex = 0;
    
    for (var entry in _keys.entries) {
      final key = entry.value;
      final context = key.currentContext;
      if (context != null) {
        final box = context.findRenderObject() as RenderBox?;
        if (box != null && box.hasSize) {
          final position = box.localToGlobal(Offset.zero);
          final distance = position.dy.abs();
          if (closestDistance == null || distance < closestDistance) {
            closestDistance = distance;
            closestIndex = entry.key;
          }
        }
      }
    }
    
    if (closestIndex >= 0 && closestIndex < _items.length) {
      final currentItem = _items[closestIndex];
      SavedChapter? chapter;
      if (currentItem is PageItem) {
        chapter = currentItem.chapter;
      } else if (currentItem is TransitionItem) {
        chapter = currentItem.nextChapter;
      }
      if (chapter != null && _currentChapter.value?.id != chapter.id) {
        _currentChapter.value = chapter;
        ref.read(downloadsProvider).updateChapterSavedAt(chapter.id, DateTime.now());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.85),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: ValueListenableBuilder<SavedChapter?>(
          valueListenable: _currentChapter,
          builder: (context, currentChapter, child) {
            if (currentChapter == null) return const SizedBox();
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  currentChapter.mangaTitle,
                  style: GoogleFonts.cairo(
                    fontSize: 10,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  currentChapter.chapterTitle,
                  style: GoogleFonts.cairo(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            );
          },
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _items.isEmpty
              ? Center(child: Text('لا توجد صور أو فصول للقراءة', style: GoogleFonts.cairo(color: Colors.white)))
              : ListView.builder(
                  controller: _scrollController,
                  physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                  padding: EdgeInsets.zero,
                  itemCount: _items.length,
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    final key = _keys[index];

                    Widget childWidget = const SizedBox();
                    if (item is PageItem) {
                      childWidget = Image.file(
                        item.imageFile,
                        key: key,
                        fit: BoxFit.fitWidth,
                        width: double.infinity,
                        gaplessPlayback: true,
                      );
                    } else if (item is TransitionItem) {
                      childWidget = _TransitionDivider(
                        key: key,
                        currentChapter: item.currentChapter,
                        nextChapter: item.nextChapter,
                      );
                    }

                    return KeepAliveWrapper(
                      child: childWidget,
                    );
                  },
                ),
    );
  }
}

class _TransitionDivider extends StatelessWidget {
  final SavedChapter currentChapter;
  final SavedChapter nextChapter;

  const _TransitionDivider({
    super.key,
    required this.currentChapter,
    required this.nextChapter,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      margin: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated.withOpacity(0.4),
        border: const Border.symmetric(
          horizontal: BorderSide(color: AppColors.glassBorder, width: 1),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 4,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              gradient: AppColors.primaryGradient,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.5),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '— انتهى الفصل —',
            style: GoogleFonts.cairo(
              color: AppColors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.glassBorder, width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.4),
                  blurRadius: 15,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.auto_stories_rounded,
                  color: AppColors.secondary,
                  size: 28,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'الفصل التالي',
                        style: GoogleFonts.cairo(
                          color: AppColors.secondary,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        nextChapter.chapterTitle,
                        style: GoogleFonts.cairo(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_downward_rounded,
                  color: AppColors.textSecondary,
                  size: 20,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// ودجت للحفاظ على بقاء عناصر القائمة نشطة في الذاكرة دون إعادة بنائها وتشفيرها عند السحب
class KeepAliveWrapper extends StatefulWidget {
  final Widget child;
  const KeepAliveWrapper({super.key, required this.child});

  @override
  State<KeepAliveWrapper> createState() => _KeepAliveWrapperState();
}

class _KeepAliveWrapperState extends State<KeepAliveWrapper> with AutomaticKeepAliveClientMixin {
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }

  @override
  bool get wantKeepAlive => true;
}
