import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/foundation.dart';

class SourcesService {
  static const String _boxName = 'saved_sources';
  static Box? _box;

  static Future<void> init() async {
    _box = await Hive.openBox(_boxName);
    debugPrint('📦 Hive initialized: sources=${_box!.length}');
    await _autoMigrateSources();
  }

  static Future<void> _autoMigrateSources() async {
    if (_box == null) return;
    for (var key in _box!.keys) {
      final item = _box!.get(key) as Map;
      final url = item['url']?.toString().toLowerCase() ?? '';
      String expectedType = item['type']?.toString() ?? 'GenericHeuristicScraper';
      
      expectedType = 'JsExtensionScraper';
      
      if (item['type'] != expectedType) {
        final updated = Map<dynamic, dynamic>.from(item);
        updated['type'] = expectedType;
        await _box!.put(key, updated);
        debugPrint('🛠️ Auto-migrated $url to $expectedType');
      }
    }
  }

  /// Get all saved sources as a list of maps
  static List<Map<String, dynamic>> getAllSources() {
    if (_box == null || _box!.isEmpty) return [];
    
    return _box!.values.map((e) {
      final map = e as Map;
      return {
        'name': map['name']?.toString() ?? '',
        'url': map['url']?.toString() ?? '',
        'type': map['type']?.toString() ?? 'GenericHeuristicScraper',
        'isManual': map['isManual'] ?? false,
      };
    }).toList();
  }

  /// Add a new source
  static Future<void> addSource(String name, String url, String type, {bool isManual = false}) async {
    // Check if it already exists
    final exists = getAllSources().any((s) => s['url'] == url);
    if (!exists) {
      await _box?.add({'name': name, 'url': url, 'type': type, 'isManual': isManual});
    }
  }

  /// Remove a source
  static Future<void> removeSource(String url) async {
    if (_box == null) return;
    
    final keysToDelete = [];
    for (var key in _box!.keys) {
      final item = _box!.get(key) as Map;
      if (item['url'] == url) {
        keysToDelete.add(key);
      }
    }
    
    for (var key in keysToDelete) {
      await _box!.delete(key);
    }
  }

  /// Update the scraper type of a source
  static Future<void> updateSourceType(String url, String newType) async {
    if (_box == null) return;
    
    for (var key in _box!.keys) {
      final item = _box!.get(key) as Map;
      if (item['url'] == url) {
        final updated = Map<dynamic, dynamic>.from(item);
        updated['type'] = newType;
        await _box!.put(key, updated);
        break;
      }
    }
  }
}
