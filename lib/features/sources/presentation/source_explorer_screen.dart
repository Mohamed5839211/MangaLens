import 'package:flutter/material.dart';
import '../../scraper/models/manga_metadata.dart';
import '../../scraper/base_scraper.dart';
import '../../../widgets/safe_network_image.dart';
import '../../../core/constants/app_colors.dart';
import 'manga_details_screen.dart';

class SourceExplorerScreen extends StatefulWidget {
  final BaseScraper scraper;

  const SourceExplorerScreen({super.key, required this.scraper});

  @override
  State<SourceExplorerScreen> createState() => _SourceExplorerScreenState();
}

class _SourceExplorerScreenState extends State<SourceExplorerScreen> {
  // ── ذاكرة تخزين مؤقت للقصص المحملة لتجنب إعادة التحميل عند الخروج والعودة ──
  static final Map<String, List<MangaMetadata>> _cacheList = {};
  static final Map<String, int> _cachePage = {};
  static final Map<String, bool> _cacheHasMore = {};

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  
  List<MangaMetadata> _mangaList = [];
  bool _isLoading = true;
  bool _isFetchingMore = false;
  int _currentPage = 1;
  bool _hasMorePages = true;
  String _currentQuery = '';
  int _emptyPageCount = 0; // لعدم التوقف فوراً عند صفحة فارغة

  @override
  void initState() {
    super.initState();
    final baseUrl = widget.scraper.baseUrl;
    
    // استرجاع من الذاكرة المؤقتة إذا لم يكن هناك بحث
    if (_cacheList.containsKey(baseUrl) && _cacheList[baseUrl]!.isNotEmpty) {
      _mangaList = List.from(_cacheList[baseUrl]!);
      _currentPage = _cachePage[baseUrl] ?? 1;
      _hasMorePages = _cacheHasMore[baseUrl] ?? true;
      _isLoading = false;
    } else {
      _loadData();
    }
    
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (!_isFetchingMore && _hasMorePages && !_isLoading) {
        _fetchMore();
      }
    }
  }

  void _updateCache() {
    if (_currentQuery.isEmpty) {
      final baseUrl = widget.scraper.baseUrl;
      _cacheList[baseUrl] = List.from(_mangaList);
      _cachePage[baseUrl] = _currentPage;
      _cacheHasMore[baseUrl] = _hasMorePages;
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _currentPage = 1;
      _mangaList.clear();
      _hasMorePages = true;
      _emptyPageCount = 0;
    });

    try {
      final list = _currentQuery.isEmpty
          ? await widget.scraper.getPopularManga(page: _currentPage)
          : await widget.scraper.searchManga(_currentQuery, page: _currentPage);
      
      if (mounted) {
        setState(() {
          _mangaList = list;
          _isLoading = false;
          if (list.isEmpty) _hasMorePages = false;
          _updateCache();
        });
      }
    } catch (e) {
      if (mounted) setState(() {
        _isLoading = false;
        _hasMorePages = false;
      });
    }
  }

  Future<void> _fetchMore() async {
    setState(() => _isFetchingMore = true);
    _currentPage++;

    try {
      final list = _currentQuery.isEmpty
          ? await widget.scraper.getPopularManga(page: _currentPage)
          : await widget.scraper.searchManga(_currentQuery, page: _currentPage);
      
      if (mounted) {
        setState(() {
          if (list.isEmpty) {
            _emptyPageCount++;
            if (_emptyPageCount >= 2) {
              _hasMorePages = false;
            }
          } else {
            // تصفية العناصر المكررة (بعض المواقع تعيد الصفحة الأولى إذا لم توجد صفحة ثانية)
            final newItems = list.where((m) => !_mangaList.any((e) => e.url == m.url)).toList();
            
            if (newItems.isEmpty) {
              _hasMorePages = false; // إذا كان كل ما عاد مكرراً، فهذا يعني نهاية النتائج
            } else {
              _emptyPageCount = 0;
              _mangaList.addAll(newItems);
            }
          }
          _isFetchingMore = false;
          _updateCache();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isFetchingMore = false;
          _hasMorePages = false; // إيقاف التحميل إذا حدث خطأ مستمر لتجنب التعليق
        });
      }
    }
  }

  void _onSearch(String query) {
    _currentQuery = query.trim();
    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: _buildSearchField(),
        backgroundColor: AppColors.surfaceElevated,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _mangaList.isEmpty
              ? const Center(child: Text('لا توجد نتائج', style: TextStyle(color: Colors.white, fontFamily: 'Cairo')))
              : RefreshIndicator(
                  onRefresh: _loadData,
                  color: AppColors.primary,
                  child: GridView.builder(
                    controller: _scrollController,
                    cacheExtent: 2500, // مساحة تخزين مؤقت ضخمة (حوالي 4 شاشات)
                    addAutomaticKeepAlives: true, // الحفاظ على حالة العناصر
                    padding: const EdgeInsets.all(12),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      childAspectRatio: 0.65,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    itemCount: _mangaList.length + (_hasMorePages ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _mangaList.length) {
                        // بمجرد بناء ويدجت التحميل، نقوم بطلب الصفحة التالية
                        // هذا يعالج مشكلة عدم امتلاء الشاشة بالنتائج وبالتالي عدم عمل التمرير
                        if (!_isFetchingMore && _hasMorePages) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) _fetchMore();
                          });
                        }
                        return const Center(
                          child: CircularProgressIndicator(color: AppColors.primary),
                        );
                      }
                      
                      return _MangaGridCard(
                        manga: _mangaList[index],
                        scraper: widget.scraper,
                      );
                    },
                  ),
                ),
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      style: const TextStyle(color: Colors.white),
      textInputAction: TextInputAction.search,
      onSubmitted: _onSearch,
      decoration: InputDecoration(
        hintText: 'بحث في المصدر...',
        hintStyle: const TextStyle(color: Colors.grey),
        border: InputBorder.none,
        suffixIcon: IconButton(
          icon: const Icon(Icons.search, color: Colors.grey),
          onPressed: () => _onSearch(_searchController.text),
        ),
      ),
    );
  }
}

/// فصلنا الـ Card في ويدجت منفصل مع AutomaticKeepAlive لمنع إعادة تحميل الصور نهائياً
class _MangaGridCard extends StatefulWidget {
  final MangaMetadata manga;
  final BaseScraper scraper;

  const _MangaGridCard({required this.manga, required this.scraper});

  @override
  State<_MangaGridCard> createState() => _MangaGridCardState();
}

class _MangaGridCardState extends State<_MangaGridCard> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true; // يحافظ على العنصر في الذاكرة حتى لو خرج من الشاشة

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final manga = widget.manga;
    
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MangaDetailsScreen(
              scraper: widget.scraper,
              mangaUrl: manga.url,
              initialCoverUrl: manga.coverUrl,
              initialTitle: manga.title,
            ),
          ),
        );
      },
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        clipBehavior: Clip.antiAlias,
        elevation: 4,
        child: Stack(
          fit: StackFit.expand,
          children: [
            SafeNetworkImage(
              imageUrl: manga.coverUrl,
              referrer: widget.scraper.baseUrl,
              fit: BoxFit.cover,
              placeholder: (_) => Container(color: AppColors.surfaceElevated),
            ),
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.9),
                      Colors.transparent,
                    ],
                  ),
                ),
                padding: const EdgeInsets.all(8),
                child: Text(
                  manga.title,
                  style: const TextStyle(
                    color: Colors.white, 
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo'
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}
