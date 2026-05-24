/// نموذج بيانات المواقع المحفوظة (المفضلة)
/// Bookmarked site data model
class SiteBookmark {
  final String id;        // معرف فريد
  final String name;      // اسم الموقع
  final String url;       // رابط الموقع
  final String? favicon;  // أيقونة الموقع (رابط)
  final DateTime addedAt;

  SiteBookmark({
    required this.id,
    required this.name,
    required this.url,
    this.favicon,
    DateTime? addedAt,
  }) : addedAt = addedAt ?? DateTime.now();

  factory SiteBookmark.fromMap(Map<dynamic, dynamic> map) {
    return SiteBookmark(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      url: map['url'] as String? ?? '',
      favicon: map['favicon'] as String?,
      addedAt: map['addedAt'] != null 
          ? DateTime.fromMillisecondsSinceEpoch(map['addedAt'] as int)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'url': url,
      'favicon': favicon,
      'addedAt': addedAt.millisecondsSinceEpoch,
    };
  }
}
