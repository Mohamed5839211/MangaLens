import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/services/sources_service.dart';
import '../../../core/services/repository_service.dart';
import '../../../core/models/catalog_source.dart';
import '../../../core/network/network_module.dart';
import '../../scraper/theme_detector.dart';
import '../../scraper/base_scraper.dart';
import '../../scraper/js_extension_scraper.dart';
import 'source_explorer_screen.dart';

class SourcesListScreen extends ConsumerStatefulWidget {
  const SourcesListScreen({super.key});

  @override
  ConsumerState<SourcesListScreen> createState() => _SourcesListScreenState();
}

class _SourcesListScreenState extends ConsumerState<SourcesListScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late Dio _dio;
  late ThemeDetector _detector;
  
  // State for Installed
  List<Map<String, dynamic>> _savedSources = [];
  bool _isDetecting = false;

  // State for Catalog
  List<CatalogSource> _allCatalogSources = [];
  List<CatalogSource> _filteredCatalog = [];
  String _catalogSearch = '';
  String _selectedLang = 'all'; // 'all', 'ar', 'en', etc.
  String _selectedRepo = 'all'; // 'all', or specific repo URL
  bool _safeMode = true; // Safe mode hides NSFW content. On by default.
  Set<String> _selectedSources = {};
  
  // State for Installed Tab
  int _installedTabIndex = 0;

  // State for Repos
  List<String> _repos = [];
  bool _isFetchingRepo = false;

  // Health Status Map: url -> status (0: unknown, 1: checking, 2: online, 3: offline)
  final Map<String, int> _healthStatus = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() => setState(() {}));
    _dio = NetworkModule().dio;
    _detector = ThemeDetector(_dio);
    
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _loadData() {
    setState(() {
      _savedSources = SourcesService.getAllSources();
      _repos = RepositoryService.getRepositories();
      _allCatalogSources = RepositoryService.getCatalogSources();
      _applyCatalogFilters();
    });
  }

  Future<void> _loadInstalledSources() async {
    setState(() {
      _savedSources = SourcesService.getAllSources();
    });
  }

  void _applyCatalogFilters() {
    _filteredCatalog = _allCatalogSources.where((src) {
      if (_safeMode && src.isNsfw) return false;
      if (_selectedLang != 'all' && src.lang != _selectedLang) return false;
      if (_selectedRepo != 'all' && src.repoUrl != _selectedRepo) return false;
      if (_catalogSearch.isNotEmpty && !src.name.toLowerCase().contains(_catalogSearch.toLowerCase())) return false;
      return true;
    }).toList();
  }

  BaseScraper _createScraper(String type, String url) {
    final baseUrl = '${Uri.parse(url).scheme}://${Uri.parse(url).host}';
    
    // Look up mapping from Catalog
    CatalogSource? sourceInfo;
    try {
      sourceInfo = _allCatalogSources.firstWhere((s) => s.baseUrl == baseUrl);
    } catch (_) {}

    String scriptFile = sourceInfo?.scriptFile ?? '';
    String popularPath = sourceInfo?.popularPath ?? '';
    
    // Fallback to local static mapping if not found in catalog (e.g. manually added before repo system)
    if (scriptFile.isEmpty) {
      final localMapping = RepositoryService.getLocalMapping(baseUrl);
      if (localMapping != null) {
        scriptFile = localMapping['scriptFile']?.toString() ?? 'universal_madara.js';
        popularPath = localMapping['popularPath']?.toString() ?? '/manga/page/{page}/?m_orderby=views';
      }
    }

    if (scriptFile.isEmpty) scriptFile = 'universal_madara.js';
    if (popularPath.isEmpty) popularPath = '/manga/page/{page}/?m_orderby=views';

    return JsExtensionScraper(
      _dio, 
      baseUrl, 
      scriptFile: scriptFile,
      popularPath: baseUrl + popularPath,
      searchPath: '$baseUrl/page/{page}/?s={query}&post_type=wp-manga', // search usually standard
    );
  }

  String _formatDate(int timestampMs) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestampMs);
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _checkHealth(String url) async {
    if (!mounted) return;
    setState(() => _healthStatus[url] = 1); // checking
    try {
      await _dio.get(url, options: Options(
        receiveTimeout: const Duration(seconds: 10),
        sendTimeout: const Duration(seconds: 10),
        validateStatus: (status) => status != null && status < 500, // 403 Cloudflare is considered "online" for our ping
      ));
      if (mounted) setState(() => _healthStatus[url] = 2); // online
    } catch (e) {
      if (mounted) setState(() => _healthStatus[url] = 3); // offline
    }
  }

  Future<void> _installBulkSources() async {
    if (_selectedSources.isEmpty) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('جاري التثبيت...', style: TextStyle(fontFamily: 'Cairo')), backgroundColor: Colors.orange),
    );
    
    int installedCount = 0;
    for (var url in _selectedSources) {
       try {
           final src = _allCatalogSources.firstWhere((s) => s.baseUrl == url);
           final type = _determineScraperFromPkg(src.pkg);
           await SourcesService.addSource(src.name, src.baseUrl, type);
           installedCount++;
       } catch (e) {
         debugPrint('Bulk install error: $e');
       }
    }
    
    setState(() {
       _selectedSources.clear();
    });
    await _loadInstalledSources();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم التثبيت بنجاح ($installedCount)', style: const TextStyle(fontFamily: 'Cairo')), backgroundColor: Colors.green),
      );
    }
  }

  String _determineScraperFromPkg(String pkg) {
    return 'JsExtensionScraper';
  }

  Future<void> _handleInstallAttempt(CatalogSource src) async {
    final url = src.baseUrl;
    // If we haven't checked health yet, do it now before installing
    if ((_healthStatus[url] ?? 0) == 0) {
      await _checkHealth(url);
    }
    if (!mounted) return;
    
    if (_healthStatus[url] == 3) {
      showDialog(
        context: context,
        builder: (c) => AlertDialog(
          backgroundColor: AppColors.surfaceBright,
          title: const Text('الموقع يبدو معطلاً', style: TextStyle(color: Colors.redAccent, fontFamily: 'Cairo')),
          content: const Text(
            'لم نتمكن من الوصول للموقع. قد يكون محظوراً في بلدك أو متوقفاً حالياً. هل تريد محاولة تثبيته على أي حال؟',
            style: TextStyle(color: AppColors.textSecondary, fontFamily: 'Cairo', height: 1.5),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء', style: TextStyle(color: Colors.grey, fontFamily: 'Cairo'))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () {
                Navigator.pop(c);
                _installFromCatalog(src);
              },
              child: const Text('تثبيت إجباري', style: TextStyle(color: Colors.white, fontFamily: 'Cairo'))
            )
          ]
        )
      );
    } else {
      _installFromCatalog(src);
    }
  }

  Future<void> _installFromCatalog(CatalogSource src) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('جاري التثبيت...', style: TextStyle(fontFamily: 'Cairo')), duration: Duration(seconds: 1)),
    );
    final type = _determineScraperFromPkg(src.pkg);
    await SourcesService.addSource(src.name, src.baseUrl, type);
    await _loadInstalledSources();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم إضافة "${src.name}" بنجاح!', style: const TextStyle(fontFamily: 'Cairo')), backgroundColor: Colors.green),
      );
    }
  }

  // ===================== INSTALLED TAB =====================

  Widget _buildInstalledTab() {
    final manualSources = _savedSources.where((s) => 
      s['isManual'] == true || !_allCatalogSources.any((c) => c.baseUrl == s['url'])
    ).toList();
    
    final repoSources = _savedSources.where((s) => 
      s['isManual'] != true && _allCatalogSources.any((c) => c.baseUrl == s['url'])
    ).toList();

    final displaySources = _installedTabIndex == 0 ? manualSources : repoSources;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _installedTabIndex = 0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _installedTabIndex == 0 ? AppColors.primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('أُضيفت يدوياً (${manualSources.length})', textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: _installedTabIndex == 0 ? Colors.white : Colors.grey)),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _installedTabIndex = 1),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _installedTabIndex == 1 ? AppColors.primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('من المستودع (${repoSources.length})', textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: _installedTabIndex == 1 ? Colors.white : Colors.grey)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isDetecting
              ? _buildLoadingState('جاري تحليل الموقع لاستنتاج قالب الاستخراج...\nقد يستغرق بضع ثوانٍ')
              : displaySources.isEmpty
                ? _buildEmptyState(
                    Icons.extension_off, 
                    _installedTabIndex == 0 ? 'لا توجد مصادر يدوية' : 'لا توجد مصادر من المستودع', 
                    _installedTabIndex == 0 ? 'اضغط على زر الإضافة لإضافة رابط موقع' : 'قم بتثبيت مصادر من تبويبة الدليل'
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16).copyWith(bottom: 80),
                    itemCount: displaySources.length,
                    itemBuilder: (context, index) => _buildSourceCard(displaySources[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceCard(Map<String, dynamic> source) {
    return Card(
      color: AppColors.surfaceElevated,
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(
              imageUrl: 'https://www.google.com/s2/favicons?domain=${Uri.tryParse(source['url'])?.host}&sz=64',
              fit: BoxFit.contain,
              errorWidget: (ctx, url, err) => CircleAvatar(
                backgroundColor: AppColors.primary.withValues(alpha: 0.2),
                child: Text(source['name'][0].toString().toUpperCase(), style: const TextStyle(color: AppColors.primary)),
              ),
            ),
          ),
        ),
        title: Text(source['name'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        subtitle: Text(source['url'], style: const TextStyle(color: Colors.grey, fontSize: 12)),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
          onPressed: () async {
            await SourcesService.removeSource(source['url']);
            _loadData();
          },
        ),
        onTap: () {
          final scraper = _createScraper(source['type'], source['url']);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SourceExplorerScreen(scraper: scraper),
            ),
          );
        },
        onLongPress: () => _showChangeEngineDialog(source),
      ),
    );
  }

  void _showChangeEngineDialog(Map<String, dynamic> source) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceBright,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('إصلاح / تغيير محرك المصدر', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
            const SizedBox(height: 8),
            const Text('إذا كان المصدر لا يعمل (أو التحميل لانهائي)، قم بتغيير المحرك:', style: TextStyle(color: AppColors.textSecondary, fontFamily: 'Cairo')),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.flash_on, color: Colors.amber),
              title: const Text('محرك Madara (سريع)', style: TextStyle(color: Colors.white, fontFamily: 'Cairo')),
              trailing: source['type'] == 'MadaraScraper' ? const Icon(Icons.check, color: Colors.green) : null,
              onTap: () async {
                Navigator.pop(context);
                await SourcesService.updateSourceType(source['url'], 'MadaraScraper');
                _loadData();
              },
            ),
            ListTile(
              leading: const Icon(Icons.flash_on, color: Colors.amber),
              title: const Text('محرك MangaStream (سريع)', style: TextStyle(color: Colors.white, fontFamily: 'Cairo')),
              trailing: source['type'] == 'MangaStreamScraper' ? const Icon(Icons.check, color: Colors.green) : null,
              onTap: () async {
                Navigator.pop(context);
                await SourcesService.updateSourceType(source['url'], 'MangaStreamScraper');
                _loadData();
              },
            ),
            ListTile(
              leading: const Icon(Icons.psychology, color: Colors.blueAccent),
              title: const Text('المحرك الذكي العام (أبطأ)', style: TextStyle(color: Colors.white, fontFamily: 'Cairo')),
              trailing: source['type'] == 'GenericHeuristicScraper' ? const Icon(Icons.check, color: Colors.green) : null,
              onTap: () async {
                Navigator.pop(context);
                await SourcesService.updateSourceType(source['url'], 'GenericHeuristicScraper');
                _loadData();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showAddSourceDialog() {
    final urlController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceBright,
        title: const Text('إضافة مصدر جديد من رابط', style: TextStyle(color: AppColors.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'الصق الرابط الرئيسي لموقع المانجا. سيقوم التطبيق باستنتاج الهيكل وبناء قارئ له تلقائياً.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: urlController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'https://...',
                hintStyle: const TextStyle(color: Colors.grey),
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () async {
              Navigator.pop(context);
              await _detectAndAddSource(urlController.text.trim());
            },
            child: const Text('استخراج وإضافة', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _detectAndAddSource(String url, {String? defaultName}) async {
    if (url.isEmpty) return;
    if (!url.startsWith('http')) url = 'https://$url';

    setState(() => _isDetecting = true);
    final scraper = await _detector.detectAndGetScraper(url);
    
    if (scraper != null) {
      final name = defaultName ?? Uri.parse(url).host.replaceAll('www.', '');
      final type = scraper.runtimeType.toString();
      await SourcesService.addSource(name, url, type, isManual: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم إضافة "$name" بنجاح!', style: const TextStyle(fontFamily: 'Cairo')), backgroundColor: Colors.green),
        );
      }
    } else {
      if (mounted) _showFallbackGuidanceDialog();
    }
    setState(() {
      _isDetecting = false;
      _loadData();
    });
  }

  void _showFallbackGuidanceDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceBright,
        title: const Text('فشل التعرف', style: TextStyle(color: Colors.redAccent)),
        content: const Text(
          'لم يتمكن التطبيق من قراءة هذا الموقع تلقائياً. تأكد أنه يعمل ولا يملك حماية قوية جداً (مثل تحديات Cloudflare المعقدة).',
          style: TextStyle(color: AppColors.textSecondary, height: 1.5),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('حسناً', style: TextStyle(color: AppColors.primary)))],
      ),
    );
  }

  // ===================== CATALOG TAB =====================

  Widget _buildCatalogTab() {
    if (_allCatalogSources.isEmpty) {
      return _buildEmptyState(
        Icons.cloud_off, 
        'الدليل فارغ', 
        'قم بإضافة مستودع (Repo) من التبويب الأخير لجلب قائمة المصادر'
      );
    }

    final langs = _allCatalogSources
        .map((e) => e.lang)
        .where((l) => l != 'all')
        .toSet()
        .toList()
      ..sort();
      
    final repoUrls = _allCatalogSources.map((e) => e.repoUrl).toSet().toList();

    return Column(
      children: [
        // Filters
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: AppColors.surfaceElevated,
          child: Column(
            children: [
              TextField(
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'ابحث في الدليل...',
                  hintStyle: const TextStyle(color: Colors.grey),
                  prefixIcon: const Icon(Icons.search, color: Colors.grey),
                  filled: true,
                  fillColor: AppColors.background,
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
                onChanged: (val) {
                  setState(() {
                    _catalogSearch = val;
                    _applyCatalogFilters();
                  });
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('المستودع:', style: TextStyle(color: AppColors.textSecondary, fontFamily: 'Cairo')),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButton<String>(
                      dropdownColor: AppColors.surfaceElevated,
                      isExpanded: true,
                      value: repoUrls.contains(_selectedRepo) ? _selectedRepo : 'all',
                      items: [
                        const DropdownMenuItem(value: 'all', child: Text('جميع المستودعات', style: TextStyle(color: Colors.white, fontFamily: 'Cairo'))),
                        ...repoUrls.map((r) => DropdownMenuItem(value: r, child: Text(Uri.tryParse(r)?.host ?? 'مستودع', style: const TextStyle(color: Colors.white), overflow: TextOverflow.ellipsis))),
                      ],
                      onChanged: (val) {
                        setState(() {
                          _selectedRepo = val!;
                          _applyCatalogFilters();
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('اللغة:', style: TextStyle(color: AppColors.textSecondary, fontFamily: 'Cairo')),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    dropdownColor: AppColors.surfaceElevated,
                    value: _selectedLang,
                    items: [
                      const DropdownMenuItem(value: 'all', child: Text('الكل', style: TextStyle(color: Colors.white))),
                      ...langs.map((l) => DropdownMenuItem(value: l, child: Text(l.toUpperCase(), style: const TextStyle(color: Colors.white)))),
                    ],
                    onChanged: (val) {
                      setState(() {
                        _selectedLang = val!;
                        _applyCatalogFilters();
                      });
                    },
                  ),
                  const Spacer(),
                  const Text('وضع الأمان', style: TextStyle(color: AppColors.textSecondary, fontFamily: 'Cairo', fontSize: 12)),
                  Switch(
                    value: _safeMode,
                    activeThumbColor: Colors.green,
                    inactiveThumbColor: Colors.grey,
                    onChanged: (val) {
                      setState(() {
                        _safeMode = val;
                        _applyCatalogFilters();
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'يعرض ${_filteredCatalog.length} مصدر${_safeMode ? ' (تم إخفاء مصادر 18+)' : ''}', 
                      style: TextStyle(
                        color: _safeMode ? Colors.orangeAccent : AppColors.textSecondary, 
                        fontFamily: 'Cairo', 
                        fontSize: 11
                      ),
                    ),
                  ),
                  if (_filteredCatalog.isNotEmpty)
                    TextButton.icon(
                      onPressed: () {
                         setState(() {
                            if (_selectedSources.length == _filteredCatalog.length) {
                               _selectedSources.clear();
                            } else {
                               _selectedSources = _filteredCatalog.map((s) => s.baseUrl).toSet();
                            }
                         });
                      },
                      icon: Icon(
                        _selectedSources.length == _filteredCatalog.length ? Icons.deselect : Icons.checklist, 
                        size: 16,
                        color: AppColors.primary
                      ),
                      label: Text(
                        _selectedSources.length == _filteredCatalog.length ? 'إلغاء التحديد' : 'تحديد الكل',
                        style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, color: AppColors.primary),
                      ),
                    )
                ],
              ),
            ],
          ),
        ),
        
        // List
        Expanded(
          child: _filteredCatalog.isEmpty
            ? _buildEmptyState(Icons.search_off, 'لا توجد نتائج', 'جرب تغيير فلاتر البحث')
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _filteredCatalog.length,
                itemBuilder: (context, index) {
                  final src = _filteredCatalog[index];
                  final isInstalled = _savedSources.any((s) => s['url'] == src.baseUrl);
                  
                  final status = _healthStatus[src.baseUrl] ?? 0;
                  Widget statusIcon;
                  if (status == 1) {
                    statusIcon = const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary));
                  } else if (status == 2) {
                    statusIcon = const Icon(Icons.wifi, color: Colors.green, size: 18);
                  } else if (status == 3) {
                    statusIcon = const Icon(Icons.wifi_off, color: Colors.red, size: 18);
                  } else {
                    statusIcon = const Icon(Icons.network_ping, color: Colors.grey, size: 18);
                  }

                  return Card(
                    color: AppColors.surfaceElevated,
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      leading: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Checkbox(
                            value: _selectedSources.contains(src.baseUrl),
                            activeColor: AppColors.primary,
                            onChanged: (val) {
                              setState(() {
                                if (val == true) {
                                  _selectedSources.add(src.baseUrl);
                                } else {
                                  _selectedSources.remove(src.baseUrl);
                                }
                              });
                            },
                          ),
                          const SizedBox(width: 4),
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                'https://www.google.com/s2/favicons?domain=${Uri.tryParse(src.baseUrl)?.host}&sz=64',
                                fit: BoxFit.contain,
                                errorBuilder: (ctx, err, stack) => const Icon(Icons.explore, color: Colors.grey),
                              ),
                            ),
                          ),
                        ],
                      ),
                      title: Row(
                        children: [
                          Expanded(child: Text(src.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14))),
                          if (src.isNsfw && !_safeMode) 
                            const Padding(
                              padding: EdgeInsets.only(right: 4.0),
                              child: Icon(Icons.privacy_tip_outlined, color: Colors.redAccent, size: 14),
                            ),
                        ],
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 6.0),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                src.lang.toUpperCase(),
                                style: const TextStyle(color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                Uri.tryParse(src.baseUrl)?.host ?? '',
                                style: const TextStyle(color: Colors.grey, fontSize: 11),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: statusIcon,
                            onPressed: () => _checkHealth(src.baseUrl),
                            tooltip: 'فحص اتصال السيرفر',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                          const SizedBox(width: 16),
                          isInstalled
                            ? const Icon(Icons.check_circle, color: Colors.green)
                            : TextButton(
                                style: TextButton.styleFrom(
                                  backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                                  minimumSize: const Size(60, 32),
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                ),
                                onPressed: () => _handleInstallAttempt(src),
                                child: const Text('تثبيت', style: TextStyle(color: AppColors.primary, fontFamily: 'Cairo', fontSize: 12)),
                              ),
                        ],
                      ),
                      onTap: () {
                         setState(() {
                            if (_selectedSources.contains(src.baseUrl)) {
                              _selectedSources.remove(src.baseUrl);
                            } else {
                              _selectedSources.add(src.baseUrl);
                            }
                         });
                      },
                    ),
                  );
                },
              ),
        ),
      ],
    );
  }

  // ===================== REPOSITORIES TAB =====================

  Widget _buildReposTab() {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: _isFetchingRepo
        ? _buildLoadingState('جاري تحميل وقراءة بيانات المستودع...\nقد يحتوي على آلاف المصادر')
        : _repos.isEmpty
          ? _buildEmptyState(Icons.storage, 'لا توجد مستودعات', 'أضف مستودعاً لجلب مصادر القصص المصورة')
          : ListView.builder(
              padding: const EdgeInsets.all(16).copyWith(bottom: 80),
              itemCount: _repos.length,
              itemBuilder: (context, index) {
                final repo = _repos[index];
                final meta = RepositoryService.getRepoMetadata(repo);
                final uniqueCount = _allCatalogSources.where((s) => s.repoUrl == repo).length;
                final totalCount = meta?['total'] ?? uniqueCount;
                final lastUpdatedMs = meta?['lastUpdated'];
                final dateStr = lastUpdatedMs != null ? _formatDate(lastUpdatedMs) : 'غير معروف';
                
                final bool showUnique = index > 0;
                
                return Card(
                  color: AppColors.surfaceElevated,
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Colors.white12,
                      child: Icon(Icons.storage, color: Colors.white),
                    ),
                    title: const Text('مستودع إضافات', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Directionality(
                          textDirection: TextDirection.ltr,
                          child: Container(
                            width: double.infinity,
                            alignment: Alignment.centerLeft,
                            child: Text(repo, style: const TextStyle(color: Colors.grey, fontSize: 11)),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            Text(
                              showUnique 
                                  ? '$totalCount مصدر كلي | $uniqueCount حصري غير مكرر'
                                  : '$totalCount مصدر كلي',
                              style: TextStyle(
                                color: showUnique ? Colors.greenAccent : AppColors.primary, 
                                fontSize: 12, 
                                fontWeight: FontWeight.bold, 
                                fontFamily: 'Cairo'
                              )
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.access_time, size: 12, color: Colors.grey),
                                const SizedBox(width: 4),
                                Text(dateStr, style: const TextStyle(color: Colors.grey, fontSize: 10, fontFamily: 'Cairo')),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                    isThreeLine: true,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.sync, color: Colors.blueAccent),
                          onPressed: () => _fetchRepo(repo),
                          tooltip: 'تحديث',
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                          onPressed: () async {
                            await RepositoryService.removeRepository(repo);
                            _loadData();
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  void _showAddRepoDialog() {
    final urlController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceBright,
        title: const Text('إضافة مستودع', style: TextStyle(color: AppColors.textPrimary, fontFamily: 'Cairo')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'أدخل رابط index.min.json الخاص بمستودع Tachiyomi/Mihon.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontFamily: 'Cairo'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: urlController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'https://...',
                hintStyle: const TextStyle(color: Colors.grey),
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(height: 12),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OutlinedButton(
                  onPressed: () => urlController.text = RepositoryService.defaultRepoUrl,
                  child: const Text('Keiyoushi (الأساسي والشامل)', style: TextStyle(fontFamily: 'Cairo', fontSize: 12)),
                ),
                const SizedBox(height: 6),
                OutlinedButton(
                  onPressed: () => urlController.text = 'https://raw.githubusercontent.com/yuzono/manga-repo/repo/index.min.json',
                  child: const Text('Yūzōnō (مصادر إضافية)', style: TextStyle(fontFamily: 'Cairo', fontSize: 12)),
                ),
              ],
            )
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () async {
              Navigator.pop(context);
              final url = urlController.text.trim();
              if (url.isNotEmpty) {
                await RepositoryService.addRepository(url);
                await _fetchRepo(url);
              }
            },
            child: const Text('إضافة', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _fetchRepo(String url) async {
    setState(() => _isFetchingRepo = true);
    try {
      final stats = await RepositoryService.fetchRepository(url, _dio);
      if (mounted) {
        final added = stats['added'] ?? 0;
        final skipped = stats['skipped'] ?? 0;
        final total = stats['total'] ?? 0;
        final String message;
        if (added == 0) {
          String msg = 'المستودع محدّث بالفعل (يحتوي على $total مصدر إجمالاً).';
          if (skipped > 0) msg += '\n(تم تخطي $skipped مصدر موجود في مستودع آخر)';
          message = msg;
        } else {
          String msg = 'اكتمل التحديث!\nتم العثور على $total مصدر إجمالاً.\nتمت إضافة $added حصري جديد.';
          if (skipped > 0) msg += '\n(تم تخطي $skipped مصدر مكرر)';
          message = msg;
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message, style: const TextStyle(fontFamily: 'Cairo', height: 1.5)), 
            backgroundColor: added == 0 ? Colors.blueAccent : Colors.green
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل تحديث المستودع: $e', style: const TextStyle(fontFamily: 'Cairo')), backgroundColor: Colors.red),
        );
      }
    }
    setState(() {
      _isFetchingRepo = false;
      _loadData();
    });
  }

  // ===================== SHARED UI =====================

  Widget _buildLoadingState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: AppColors.primary),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary, fontFamily: 'Cairo', height: 1.5),
          ).animate().fadeIn(duration: 500.ms),
        ],
      ),
    );
  }

  Widget _buildEmptyState(IconData icon, String title, String subtitle) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: AppColors.textSecondary.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text(title, style: const TextStyle(color: AppColors.textSecondary, fontSize: 18, fontFamily: 'Cairo')),
          const SizedBox(height: 8),
          Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 14, fontFamily: 'Cairo')),
        ],
      ),
    );
  }

  Widget _buildFab() {
    if (_tabController.index == 0) {
      return FloatingActionButton(
        onPressed: _showAddSourceDialog,
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add, color: Colors.white),
      );
    } else if (_tabController.index == 1) {
      if (_selectedSources.isNotEmpty) {
        return FloatingActionButton.extended(
          onPressed: _installBulkSources,
          backgroundColor: Colors.green,
          icon: const Icon(Icons.download, color: Colors.white),
          label: Text('تثبيت ${_selectedSources.length} مصدر', style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
        );
      }
      return const SizedBox.shrink();
    } else {
      return FloatingActionButton(
        onPressed: _showAddRepoDialog,
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add, color: Colors.white),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('إدارة المصادر', style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
        backgroundColor: AppColors.surfaceElevated,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          labelStyle: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
          tabs: const [
            Tab(text: 'مثبتة', icon: Icon(Icons.check_circle_outline)),
            Tab(text: 'الدليل', icon: Icon(Icons.explore_outlined)),
            Tab(text: 'المستودعات', icon: Icon(Icons.storage_outlined)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildInstalledTab(),
          _buildCatalogTab(),
          _buildReposTab(),
        ],
      ),
      floatingActionButton: _buildFab(),
    );
  }
}
