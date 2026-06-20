import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:dio/dio.dart';
import '../models/catalog_source.dart';

class RepositoryService {
  static const String _reposBoxName = 'repositories';
  static const String _catalogBoxName = 'catalog_sources';
  static const String _repoMetadataBoxName = 'repo_metadata';
  
  static Box? _reposBox;
  static Box? _catalogBox;
  static Box? _repoMetadataBox;

  // Keiyoushi default repo
  static const String defaultRepoUrl = 'https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.min.json';

  static Map<String, dynamic> _localDbMappings = {};

  static Future<void> init() async {
    _reposBox = await Hive.openBox(_reposBoxName);
    _catalogBox = await Hive.openBox(_catalogBoxName);
    _repoMetadataBox = await Hive.openBox(_repoMetadataBoxName);
    
    // Add default repo if list is totally empty (first run)
    if (_reposBox!.isEmpty) {
      await addRepository(defaultRepoUrl);
    }
    
    try {
      final localDbStr = await rootBundle.loadString('assets/extensions/mangalens_database.json');
      _localDbMappings = jsonDecode(localDbStr) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('⚠️ Failed to load local mapping DB in init: $e');
    }
    
    debugPrint('📦 Hive initialized: repos=${_reposBox!.length}, catalog=${_catalogBox!.length}, meta=${_repoMetadataBox!.length}');
  }

  static Map<String, dynamic>? getLocalMapping(String baseUrl) {
    return _localDbMappings[baseUrl];
  }

  /// Get list of added repository URLs
  static List<String> getRepositories() {
    if (_reposBox == null) return [];
    return _reposBox!.values.map((e) => e.toString()).toList();
  }

  /// Add a new repository URL
  static Future<void> addRepository(String url) async {
    final repos = getRepositories();
    if (!repos.contains(url)) {
      await _reposBox?.add(url);
    }
  }

  /// Remove a repository and clean its catalog sources
  static Future<void> removeRepository(String url) async {
    if (_reposBox == null || _catalogBox == null) return;
    
    // 1. Remove from repos box
    final keysToDelete = [];
    for (var key in _reposBox!.keys) {
      if (_reposBox!.get(key) == url) keysToDelete.add(key);
    }
    for (var key in keysToDelete) {
      await _reposBox!.delete(key);
    }

    // 2. Remove all catalog sources that came from this repo
    final catalogKeysToDelete = [];
    for (var key in _catalogBox!.keys) {
      final item = _catalogBox!.get(key) as Map;
      if (item['repoUrl'] == url) catalogKeysToDelete.add(key);
    }
    for (var key in catalogKeysToDelete) {
      await _catalogBox!.delete(key);
    }
    
    // 3. Remove metadata
    await _repoMetadataBox?.delete(url);
  }

  /// Get all catalog sources
  static List<CatalogSource> getCatalogSources() {
    if (_catalogBox == null || _catalogBox!.isEmpty) return [];
    
    return _catalogBox!.values.map((e) {
      final map = Map<String, dynamic>.from(e as Map);
      return CatalogSource(
        name: map['name'] ?? '',
        baseUrl: map['baseUrl'] ?? '',
        lang: map['lang'] ?? 'unknown',
        isNsfw: map['isNsfw'] ?? false,
        repoUrl: map['repoUrl'] ?? '',
        theme: map['theme'] ?? 'Unknown',
        popularPath: map['popularPath'] ?? '',
        scriptFile: map['scriptFile'] ?? '',
      );
    }).toList();
  }

  /// Get metadata for a specific repository
  static Map<String, dynamic>? getRepoMetadata(String url) {
    if (_repoMetadataBox == null) return null;
    final data = _repoMetadataBox!.get(url);
    if (data == null) return null;
    return Map<String, dynamic>.from(data as Map);
  }

  /// Fetch and parse a repository URL, updating the catalog
  static Future<Map<String, int>> fetchRepository(String repoUrl, Dio dio) async {
    if (_catalogBox == null) return {'added': 0, 'skipped': 0};

    try {
      final response = await dio.get(repoUrl);
      List<dynamic> data = [];
      
      if (response.data is String) {
        data = jsonDecode(response.data) as List<dynamic>;
      } else if (response.data is List) {
        data = response.data;
      } else {
        throw Exception('Invalid repository format');
      }

      Map<String, dynamic> localDb = {};
      try {
        final localDbStr = await rootBundle.loadString('assets/extensions/mangalens_database.json');
        localDb = jsonDecode(localDbStr) as Map<String, dynamic>;
      } catch (e) {
        debugPrint('⚠️ Failed to load local mapping DB: $e');
      }

      int newSourcesCount = 0;
      int crossRepoSkipped = 0;
      int existingInThisRepo = 0;
      int totalInRepo = 0;
      
      final allSources = getCatalogSources();
      final urlToRepoMap = { for (var s in allSources) s.baseUrl: s.repoUrl };

      for (var extension in data) {
        if (extension is! Map) continue;
        
        final extLang = extension['lang']?.toString() ?? 'all';
        final extNsfw = extension['nsfw'] is int ? extension['nsfw'] as int : 0;
        final extPkg = extension['pkg']?.toString() ?? '';
        final sources = extension['sources'];

        if (sources is List) {
          for (var src in sources) {
            if (src is! Map) continue;
            
            final baseUrl = src['baseUrl']?.toString() ?? '';
            final cleanUrl = baseUrl.split(',').first.trim().replaceAll('#', '');
            
            if (cleanUrl.isEmpty || !cleanUrl.startsWith('http')) continue;
            
            totalInRepo++;

            final catalogSrc = CatalogSource.fromJson(
              src as Map<String, dynamic>, 
              repoUrl, 
              extNsfw, 
              extLang,
              pkg: extPkg,
            );
            String cleanBaseUrl = cleanUrl.endsWith('/') ? cleanUrl.substring(0, cleanUrl.length - 1) : cleanUrl;
            Map<String, dynamic>? mapping = localDb[cleanBaseUrl];
            
            final finalSrc = CatalogSource(
              name: catalogSrc.name,
              baseUrl: cleanUrl,
              lang: catalogSrc.lang,
              isNsfw: catalogSrc.isNsfw,
              repoUrl: catalogSrc.repoUrl,
              pkg: catalogSrc.pkg,
              theme: mapping != null ? mapping['theme']?.toString() ?? 'Madara' : 'Madara',
              popularPath: mapping != null ? mapping['popularPath']?.toString() ?? '/manga/page/{page}/?m_orderby=views' : '/manga/page/{page}/?m_orderby=views',
              scriptFile: mapping != null ? mapping['scriptFile']?.toString() ?? 'universal_madara.js' : 'universal_madara.js',
            );

            if (urlToRepoMap.containsKey(cleanUrl)) {
              if (urlToRepoMap[cleanUrl] == repoUrl) {
                // Already exists from THIS repo. 
                existingInThisRepo++;
              } else {
                // Exists but from a DIFFERENT repo! (Duplicate)
                crossRepoSkipped++;
              }
            } else {
              // Brand new source
              await _catalogBox!.add(finalSrc.toJson());
              urlToRepoMap[cleanUrl] = repoUrl;
              newSourcesCount++;
            }
          }
        }
      }
      
      // Save metadata
      await _repoMetadataBox?.put(repoUrl, {
        'total': totalInRepo,
        'lastUpdated': DateTime.now().millisecondsSinceEpoch,
      });
      
      return {'added': newSourcesCount, 'skipped': crossRepoSkipped, 'total': totalInRepo};
    } catch (e) {
      debugPrint('❌ Error fetching repository $repoUrl: $e');
      rethrow;
    }
  }

  /// Auto-healing: update a source's base URL if domain changed
  static Future<void> updateSourceBaseUrl(String oldUrl, String newUrl) async {
    if (_catalogBox == null) return;
    
    String? targetKey;
    Map? targetItem;
    
    for (var key in _catalogBox!.keys) {
      final item = _catalogBox!.get(key) as Map;
      if (item['baseUrl'] == oldUrl) {
        targetKey = key?.toString() ?? key.toString();
        targetItem = item;
        break;
      }
    }

    if (targetKey != null && targetItem != null) {
      targetItem['baseUrl'] = newUrl;
      await _catalogBox!.put(targetKey, targetItem);
      debugPrint('🔧 Self-Healing: Updated domain from $oldUrl to $newUrl');
    }
  }
}
