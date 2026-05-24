import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../models/chapter_data.dart';
import '../providers/reader_provider.dart';
import '../../downloads/data/downloads_service.dart';
import '../../../core/services/history_service.dart';

/// شاشة القراءة النهائية — تجربة نظيفة خالية من الإعلانات
/// Translated Reader Screen — Clean, ad-free reading experience
class TranslatedReaderScreen extends ConsumerStatefulWidget {
  final bool translateMode;
  const TranslatedReaderScreen({super.key, required this.translateMode});

  @override
  ConsumerState<TranslatedReaderScreen> createState() => _TranslatedReaderScreenState();
}

class _TranslatedReaderScreenState extends ConsumerState<TranslatedReaderScreen> {
  bool _translationStarted = false;

  @override
  void initState() {
    super.initState();
    if (widget.translateMode) {
      // بدء الترجمة بعد بناء الشاشة
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_translationStarted) {
          _translationStarted = true;
          ref.read(readerProvider.notifier).translateAll();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final readerState = ref.watch(readerProvider);
    final chapter = readerState.chapter;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.8),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          children: [
            Text(
              chapter?.title ?? 'القارئ',
              style: GoogleFonts.cairo(
                fontWeight: FontWeight.w800,
                color: Colors.white,
                fontSize: 14,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (widget.translateMode)
              _buildProgressText(readerState),
          ],
        ),
        centerTitle: true,
        actions: [
          if (chapter != null && readerState.status == ReaderStatus.completed)
            IconButton(
              icon: const Icon(Icons.save_rounded, color: Colors.white),
              onPressed: () => _showSaveDialog(context, chapter),
            ),
        ],
      ),
      body: chapter == null
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _buildReaderBody(chapter, readerState),
    );
  }

  Widget _buildProgressText(ReaderState state) {
    if (state.status == ReaderStatus.completed) {
      return Text(
        'الترجمة مكتملة ✅',
        style: GoogleFonts.cairo(color: AppColors.success, fontSize: 11),
      );
    }
    if (state.status == ReaderStatus.translating) {
      return Text(
        'جاري الترجمة: ${state.currentTranslatingIndex} / ${state.totalImages}',
        style: GoogleFonts.cairo(color: AppColors.primary, fontSize: 11),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildReaderBody(ChapterData chapter, ReaderState state) {
    return Column(
      children: [
        // شريط تقدم الترجمة
        if (widget.translateMode && state.status == ReaderStatus.translating)
          LinearProgressIndicator(
            value: state.progress,
            backgroundColor: Colors.transparent,
            color: AppColors.primary,
            minHeight: 3,
          ),

        // قائمة الصور العمودية
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.zero,
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            itemCount: chapter.images.length,
            itemBuilder: (context, index) {
              return KeepAliveWrapper(
                child: _buildReaderImage(chapter.images[index], index),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildReaderImage(ChapterImage img, int index) {
    // اختيار الصورة المناسبة: المترجمة إذا وُجدت، وإلا الأصلية
    final bytes = widget.translateMode
        ? (img.translatedBytes ?? img.originalBytes)
        : img.originalBytes;

    if (bytes == null) {
      return Container(
        height: 300,
        color: AppColors.surfaceElevated,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (img.status == ImageTranslationStatus.processing)
                Column(
                  children: [
                    const SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                        strokeWidth: 3,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'جاري ترجمة الصورة ${index + 1}...',
                      style: GoogleFonts.cairo(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                )
              else if (img.status == ImageTranslationStatus.downloading)
                const CircularProgressIndicator(color: AppColors.primary)
              else
                const Icon(Icons.image_not_supported_rounded,
                    color: AppColors.textDisabled, size: 48),
            ],
          ),
        ),
      );
    }

    return Image.memory(
      bytes,
      fit: BoxFit.fitWidth,
      width: double.infinity,
      gaplessPlayback: true,
    );
  }

  void _showSaveDialog(BuildContext context, ChapterData chapter) {
    // محاولة جلب عنوان المانغا المنظف والأصلي من سجل القراءة أولاً
    final mangaId = HistoryService.generateId(chapter.sourceUrl);
    final historyItem = HistoryService.getHistoryById(mangaId);
    
    // تنظيف الاسم والبحث عن اسم المانغا الفعلي
    String cleanMangaTitle = (historyItem?.title != null && historyItem!.title.isNotEmpty)
        ? historyItem.title
        : chapter.title;
        
    // إزالة أرقام الفصول (مثال: Solo Leveling Chapter 123 -> Solo Leveling)
    cleanMangaTitle = cleanMangaTitle.replaceAll(RegExp(r'(chapter|ch\.|ch|episode|ep\.|ep)\s*\d+.*$', caseSensitive: false), '');
    cleanMangaTitle = cleanMangaTitle.split('|').first;
    cleanMangaTitle = cleanMangaTitle.split(' - ').first;
    cleanMangaTitle = cleanMangaTitle.split(' – ').first;
    cleanMangaTitle = cleanMangaTitle.trim();
    if (cleanMangaTitle.isEmpty) cleanMangaTitle = 'Manga';

    // استخراج رقم/اسم الفصل
    String cleanChapterTitle = '';
    final patterns = [
      RegExp(r'(chapter|ch|episode|ep)[/-]?\s*(\d+(\.\d+)?)', caseSensitive: false),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(chapter.title);
      if (match != null) {
        cleanChapterTitle = 'Ch. ${match.group(2)}';
        break;
      }
    }
    if (cleanChapterTitle.isEmpty) {
      cleanChapterTitle = chapter.title;
    }

    final mangaController = TextEditingController(text: cleanMangaTitle);
    final chapterController = TextEditingController(text: cleanChapterTitle);
    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            backgroundColor: AppColors.surface,
            title: Text('حفظ الفصل', style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w700)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: mangaController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'اسم المانغا',
                    labelStyle: GoogleFonts.cairo(color: AppColors.textSecondary),
                    enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.border)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: chapterController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'رقم/اسم الفصل',
                    labelStyle: GoogleFonts.cairo(color: AppColors.textSecondary),
                    enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.border)),
                  ),
                ),
                if (isSaving) ...[
                  const SizedBox(height: 24),
                  const CircularProgressIndicator(color: AppColors.primary),
                  const SizedBox(height: 12),
                  Text('جاري الحفظ...', style: GoogleFonts.cairo(color: AppColors.primary)),
                ]
              ],
            ),
            actions: isSaving ? [] : [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('إلغاء', style: GoogleFonts.cairo(color: AppColors.textSecondary)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                onPressed: () async {
                  setState(() => isSaving = true);
                  
                  // Extract the actual translated bytes
                  final imagesToSave = chapter.images.map((e) => widget.translateMode ? (e.translatedBytes ?? e.originalBytes) : e.originalBytes).where((b) => b != null).map((b) => b!).toList();
                  
                  // الحصول على رابط صورة غلاف المانغا الرئيسي من السجل
                  final mangaId = HistoryService.generateId(chapter.sourceUrl);
                  final historyItem = HistoryService.getHistoryById(mangaId);
                  final coverUrl = historyItem?.imageUrl;

                  await ref.read(downloadsProvider).saveChapter(
                    mangaTitle: mangaController.text,
                    chapterTitle: chapterController.text,
                    images: imagesToSave,
                    coverUrl: coverUrl,
                  );
                  
                  if (context.mounted) {
                    Navigator.pop(context); // إغلاق صندوق الحوار
                    Navigator.of(context).popUntil((route) => route.isFirst); // العودة للصفحة الرئيسية للتطبيق
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('تم حفظ الفصل بنجاح! يمكن الوصول إليه من الصفحة الرئيسية.', style: GoogleFonts.cairo()), backgroundColor: AppColors.success),
                    );
                  }
                },
                child: Text('حفظ', style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        }
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
