import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/foundation.dart';
import '../models/manga_history.dart';
import '../models/site_bookmark.dart';

/// خدمة إدارة سجل القراءة والمفضلة
/// History & Bookmarks management service (Hive-backed)
class HistoryService {
  static const String _historyBoxName = 'manga_history';
  static const String _bookmarkBoxName = 'site_bookmarks';

  static Box? _historyBox;
  static Box? _bookmarkBox;

  /// تهيئة Hive وفتح الصناديق
  static Future<void> init() async {
    await Hive.initFlutter();
    _historyBox = await Hive.openBox(_historyBoxName);
    _bookmarkBox = await Hive.openBox(_bookmarkBoxName);
    debugPrint('📦 Hive initialized: history=${_historyBox!.length}, bookmarks=${_bookmarkBox!.length}');
  }

  // ══════════════════════════════════════════════════
  // ─── سجل القراءة (Manga History) ──────────────────
  // ══════════════════════════════════════════════════

  /// حفظ أو تحديث سجل مانغا
  static Future<void> saveMangaHistory(MangaHistory manga) async {
    await _historyBox?.put(manga.id, manga.toMap());
    debugPrint('📖 Saved manga history: ${manga.title}');
  }

  /// جلب كل سجلات القراءة (مرتبة بالأحدث أولاً)
  static List<MangaHistory> getAllHistory() {
    if (_historyBox == null || _historyBox!.isEmpty) return [];
    
    final list = _historyBox!.values
        .map((e) => MangaHistory.fromMap(e as Map))
        .toList();

    // ترتيب بالأحدث أولاً
    list.sort((a, b) => b.lastRead.compareTo(a.lastRead));
    return list;
  }

  /// جلب سجل مانغا محدد بالمعرف
  static MangaHistory? getHistoryById(String id) {
    final data = _historyBox?.get(id);
    if (data == null) return null;
    return MangaHistory.fromMap(data as Map);
  }

  /// حذف سجل مانغا
  static Future<void> deleteHistory(String id) async {
    await _historyBox?.delete(id);
  }

  /// مسح كل السجل
  static Future<void> clearHistory() async {
    await _historyBox?.clear();
  }

  // ══════════════════════════════════════════════════
  // ─── المواقع المفضلة (Bookmarks) ──────────────────
  // ══════════════════════════════════════════════════

  /// حفظ موقع مفضل
  static Future<void> addBookmark(SiteBookmark bookmark) async {
    await _bookmarkBox?.put(bookmark.id, bookmark.toMap());
    debugPrint('⭐ Bookmark saved: ${bookmark.name}');
  }

  /// جلب كل المفضلة (مرتبة بالأحدث نشاطاً أولاً)
  static List<SiteBookmark> getAllBookmarks() {
    if (_bookmarkBox == null || _bookmarkBox!.isEmpty) return [];
    
    final list = _bookmarkBox!.values
        .map((e) => SiteBookmark.fromMap(e as Map))
        .toList();

    // ترتيب بالأحدث نشاطاً أولاً
    list.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return list;
  }

  /// هل الموقع محفوظ؟
  static bool isBookmarked(String id) {
    return _bookmarkBox?.containsKey(id) ?? false;
  }

  /// حذف موقع من المفضلة
  static Future<void> removeBookmark(String id) async {
    await _bookmarkBox?.delete(id);
  }

  /// مسح كل المفضلة
  static Future<void> clearBookmarks() async {
    await _bookmarkBox?.clear();
  }

  // ══════════════════════════════════════════════════
  // ─── أدوات مساعدة ─────────────────────────────────
  // ══════════════════════════════════════════════════

  /// جلب معرف مانغا موجود بنفس العنوان على نفس النطاق لمنع تكرار السجلات
  static String? findExistingMangaIdByTitle(String title, String siteUrl) {
    try {
      final host = Uri.parse(siteUrl).host.replaceFirst('www.', '').toLowerCase();
      final targetCanonical = _canonicalizeTitle(title);
      if (targetCanonical.isEmpty) return null;
      
      final historyList = getAllHistory();
      for (final item in historyList) {
        final itemHost = Uri.parse(item.siteUrl).host.replaceFirst('www.', '').toLowerCase();
        if (itemHost == host) {
          final itemCanonical = _canonicalizeTitle(item.title);
          if (itemCanonical == targetCanonical) {
            return item.id;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  /// توحيد العنوان للمقارنة
  static String _canonicalizeTitle(String title) {
    return title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\u0600-\u06FF]'), '') // الاحتفاظ بالحروف الإنجليزية والعربية والأرقام فقط
        .trim();
  }

  /// توليد معرف فريد من الرابط (يمثل المانغا وليس الفصل)
  static String generateId(String url) {
    try {
      final uri = Uri.parse(url);
      final host = uri.host.replaceFirst('www.', '');
      
      // لمعالجة Webtoon
      if (host.contains('webtoons.com')) {
        final titleNo = uri.queryParameters['title_no'];
        if (titleNo != null) return '$host/title_no=$titleNo'.hashCode.abs().toString();
      }

      final segments = List<String>.from(uri.pathSegments.where((s) => s.isNotEmpty));
      
      // إزالة مقاطع الفصل من نهاية المسار بشكل متكرر
      bool removed = true;
      while (removed && segments.length > 0) {
        final lastSeg = segments.last.toLowerCase();
        removed = false;

        // 1. رقم صريح كامل (مثل /slug/1 أو /slug/1.5)
        if (RegExp(r'^\d+(\.\d+)?$').hasMatch(lastSeg)) {
          if (segments.length > 1) {
            segments.removeLast();
            removed = true;
            continue;
          }
        }

        // 2. مقطع يبدأ بكلمة فصل + رقم (مثل chapter-1, ch1, ep-5, episode10, chap3)
        if (RegExp(r'^(chapter|ch|chap|episode|ep|c)[-_]?\d+', caseSensitive: false).hasMatch(lastSeg)) {
          if (segments.length > 1) {
            segments.removeLast();
            removed = true;
            continue;
          }
        }

        // 3. مقطع هو كلمة فصل بمفردها بدون رقم (مثل /slug/chapter/)
        if (RegExp(r'^(chapter|episode)$', caseSensitive: false).hasMatch(lastSeg)) {
          if (segments.length > 1) {
            segments.removeLast();
            removed = true;
            continue;
          }
        }

        // 4. UUID أو ObjectID أو معرف حلقة طويل (مثل Manta أو غيره)
        if (RegExp(r'^[0-9a-f]{24}$', caseSensitive: false).hasMatch(lastSeg) ||
            RegExp(r'^[0-9a-f]{32}$', caseSensitive: false).hasMatch(lastSeg) ||
            RegExp(r'^[0-9a-f]{8,}(-[0-9a-f]{4,}){2,}', caseSensitive: false).hasMatch(lastSeg)) {
          if (segments.length > 1) {
            segments.removeLast();
            removed = true;
            continue;
          }
        }

        // 7. مقاطع الحاويات الشائعة (مثل episodes, chapters, read, reader, viewer)
        final containerSegments = {'episodes', 'chapters', 'read', 'reader', 'viewer'};
        if (containerSegments.contains(lastSeg)) {
          if (segments.length > 1) {
            segments.removeLast();
            removed = true;
            continue;
          }
        }
      }
      
      // ─── ترقية للتعامل مع الروابط المسطحة (Flat URLs) ───
      if (segments.isNotEmpty) {
        final lastSeg = segments.last;
        
        // 5. slug يحتوي chapter/ch/ep/episode ملحق بالاسم (مثل solo-leveling-chapter-10)
        final chapterInSlugRegex = RegExp(r'[-_](chapter|ch|ep|episode|chap|c)[-_]?\d+.*$', caseSensitive: false);
        if (chapterInSlugRegex.hasMatch(lastSeg)) {
          final cleaned = lastSeg.replaceFirst(chapterInSlugRegex, '');
          if (cleaned.isNotEmpty && cleaned.length > 2) {
            segments[segments.length - 1] = cleaned;
          }
        }

        // 6. رقم ملحق بالاسم (مثل solo-leveling-10)
        final trailingNumberRegex = RegExp(r'[-_]\d+(\.\d+)?$');
        if (trailingNumberRegex.hasMatch(lastSeg)) {
          final cleaned = lastSeg.replaceFirst(trailingNumberRegex, '');
          if (cleaned.isNotEmpty && cleaned.length > 2) {
            segments[segments.length - 1] = cleaned;
          }
        }
      }
      
      String key;
      // إضافة معاملات الاستعلام المحددة للمانغا لمنع تصادم الهويات
      final mangaQueryKeys = ['title_no', 'series_id', 'manga_id', 'comic_id', 'id', 'manga'];
      String? foundParam;
      String? foundVal;
      for (final param in mangaQueryKeys) {
        final val = uri.queryParameters[param];
        if (val != null) {
          foundParam = param;
          foundVal = val;
          break;
        }
      }
      
      if (foundParam != null && foundVal != null) {
        key = '$host?$foundParam=$foundVal';
      } else {
        key = '$host/${segments.join("/")}';
      }
      
      return key.hashCode.abs().toString();
    } catch (_) {
      return url.hashCode.abs().toString();
    }
  }
}
