import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../models/chapter_data.dart';
import '../providers/reader_provider.dart';
import '../../../core/constants/supported_languages.dart';
import 'translated_reader_screen.dart';

/// شاشة معاينة الفصل — يتأكد المستخدم من الصور قبل الترجمة
/// Chapter Preview Screen — User confirms extracted images before translating
class ChapterPreviewScreen extends ConsumerStatefulWidget {
  const ChapterPreviewScreen({super.key});

  @override
  ConsumerState<ChapterPreviewScreen> createState() => _ChapterPreviewScreenState();
}

class _ChapterPreviewScreenState extends ConsumerState<ChapterPreviewScreen> {
  final ScrollController _scrollController = ScrollController();
  bool _isAtBottom = false;
  bool _langDetected = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // تشغيل الكشف التلقائي عن اللغة بعد بناء الإطار الأول
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryDetectLanguage();
    });
  }

  /// محاولة الكشف التلقائي عن لغة الفصل (تعمل مرة واحدة فقط)
  void _tryDetectLanguage() {
    if (_langDetected) return;
    final state = ref.read(readerProvider);
    // ننتظر حتى تتوفر صورة واحدة على الأقل محملة
    if (state.chapter != null &&
        state.chapter!.images.any((img) => img.originalBytes != null)) {
      _langDetected = true;
      ref.read(readerProvider.notifier).detectChapterLanguage();
    } else {
      // إعادة المحاولة بعد ثانية (الصور ربما لا تزال تحمل)
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) _tryDetectLanguage();
      });
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    
    // التحقق مما إذا كنا بالقرب من الأسفل
    final isAtBottom = currentScroll >= (maxScroll - 200);
    
    if (isAtBottom != _isAtBottom) {
      setState(() {
        _isAtBottom = isAtBottom;
      });
    }
  }

  void _scrollToBottomOrTop() {
    if (!_scrollController.hasClients) return;
    
    if (_isAtBottom) {
      // التمرير للأعلى
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutCubic,
      );
    } else {
      // التمرير للأسفل
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final readerState = ref.watch(readerProvider);
    final readerNotifier = ref.read(readerProvider.notifier);
    final chapter = readerState.chapter;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () {
            readerNotifier.reset();
            Navigator.of(context).pop();
          },
        ),
        title: Column(
          children: [
            Text(
              chapter?.title ?? 'معاينة الفصل',
              style: GoogleFonts.cairo(
                fontWeight: FontWeight.w800,
                color: Colors.white,
                fontSize: 16,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (chapter != null)
              Text(
                '${chapter.images.length} صورة',
                style: GoogleFonts.cairo(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
          ],
        ),
        centerTitle: true,
      ),
      body: _buildBody(context, ref, readerState),
      floatingActionButton: readerState.status == ReaderStatus.ready && (readerState.chapter?.images.isNotEmpty ?? false)
          ? FloatingActionButton(
              onPressed: _scrollToBottomOrTop,
              backgroundColor: AppColors.primary.withOpacity(0.9),
              elevation: 4,
              mini: true,
              child: Icon(
                _isAtBottom ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                color: Colors.white,
              ),
            )
          : null,
      bottomNavigationBar: _buildBottomBar(context, ref, readerState),
    );
  }

  Widget _buildBody(BuildContext context, WidgetRef ref, ReaderState state) {
    if (state.status == ReaderStatus.error) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 64),
            const SizedBox(height: 16),
            Text(
              state.errorMessage ?? 'حدث خطأ غير معروف',
              style: GoogleFonts.cairo(color: AppColors.textSecondary, fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final chapter = state.chapter;
    if (chapter == null || chapter.images.isEmpty) {
      if (state.status == ReaderStatus.downloading) {
        return const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        );
      }
      return Center(
        child: Text(
          'لا توجد صور',
          style: GoogleFonts.cairo(color: AppColors.textSecondary, fontSize: 18),
        ),
      );
    }

    // عرض شريط تقدم التحميل في الأعلى + شريط اللغات + الصور
    return Column(
      children: [
        if (state.status == ReaderStatus.downloading)
          LinearProgressIndicator(
            value: state.totalImages > 0
                ? state.currentTranslatingIndex / state.totalImages
                : null,
            color: AppColors.primary,
            backgroundColor: AppColors.surfaceElevated,
            minHeight: 4,
          ),
        _buildLanguagePicker(context, ref, state),
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            itemCount: chapter.images.length,
            itemBuilder: (context, index) {
              final img = chapter.images[index];
              return KeepAliveWrapper(
                child: _buildImageCard(context, ref, img, index),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLanguagePicker(BuildContext context, WidgetRef ref, ReaderState state) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: Row(
        children: [
          // Source Language
          Expanded(
            child: _buildDropdown(
              value: state.sourceLang,
              items: SupportedLanguages.sources,
              onChanged: (val) {
                if (val != null) ref.read(readerProvider.notifier).setSourceLang(val);
              },
            ),
          ),
          
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Icon(Icons.arrow_forward_rounded, color: AppColors.textSecondary, size: 20),
          ),

          // Target Language
          Expanded(
            child: _buildDropdown(
              value: state.targetLang,
              items: SupportedLanguages.targets,
              onChanged: (val) {
                if (val != null) ref.read(readerProvider.notifier).setTargetLang(val);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown({
    required String value,
    required Map<String, String> items,
    required ValueChanged<String?> onChanged,
  }) {
    // Ensure the value exists in the map to prevent errors
    final safeValue = items.containsKey(value) ? value : items.keys.first;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: safeValue,
          isExpanded: true,
          dropdownColor: AppColors.surfaceElevated,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.primary),
          style: GoogleFonts.cairo(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          onChanged: onChanged,
          items: items.entries.map((e) {
            return DropdownMenuItem<String>(
              value: e.key,
              child: Text(
                e.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildImageCard(BuildContext context, WidgetRef ref, ChapterImage img, int index) {
    return Stack(
      children: [
        // الصورة
        Container(
          margin: const EdgeInsets.symmetric(vertical: 2),
          width: double.infinity,
          child: img.originalBytes != null
              ? Image.memory(
                  img.originalBytes!,
                  fit: BoxFit.fitWidth,
                  gaplessPlayback: true,
                )
              : Container(
                  height: 200,
                  color: AppColors.surfaceElevated,
                  child: Center(
                    child: img.status == ImageTranslationStatus.downloading
                        ? const CircularProgressIndicator(color: AppColors.primary)
                        : const Icon(Icons.broken_image_rounded,
                            color: AppColors.textDisabled, size: 48),
                  ),
                ),
        ),

        // رقم الصورة
        Positioned(
          top: 8,
          right: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${index + 1}',
              style: GoogleFonts.cairo(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),

        // زر حذف الصورة
        Positioned(
          top: 8,
          left: 8,
          child: GestureDetector(
            onTap: () {
              // تأكيد الحذف
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: AppColors.surfaceElevated,
                  title: Text('حذف الصورة؟',
                      style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w700)),
                  content: Text('سيتم إزالة هذه الصورة من الفصل (ربما إعلان)',
                      style: GoogleFonts.cairo(color: AppColors.textSecondary)),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text('إلغاء', style: GoogleFonts.cairo(color: AppColors.textSecondary)),
                    ),
                    TextButton(
                      onPressed: () {
                        ref.read(readerProvider.notifier).removeImage(index);
                        Navigator.pop(ctx);
                      },
                      child: Text('حذف', style: GoogleFonts.cairo(color: AppColors.error)),
                    ),
                  ],
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close_rounded, color: Colors.white, size: 18),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomBar(BuildContext context, WidgetRef ref, ReaderState state) {
    if (state.status != ReaderStatus.ready) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: SafeArea(
        child: Row(
          children: [
            // زر القراءة بدون ترجمة
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const TranslatedReaderScreen(translateMode: false),
                    ),
                  );
                },
                icon: const Icon(Icons.menu_book_rounded),
                label: Text('اقرأ بدون ترجمة', style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  side: const BorderSide(color: AppColors.border),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // زر الترجمة
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const TranslatedReaderScreen(translateMode: true),
                    ),
                  );
                },
                icon: const Icon(Icons.translate_rounded, color: Colors.white),
                label: Text('ترجم الفصل كاملاً',
                    style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 4,
                  shadowColor: AppColors.primary.withOpacity(0.4),
                ),
              ),
            ),
          ],
        ),
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
