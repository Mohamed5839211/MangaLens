class CatalogSource {
  final String name;
  final String baseUrl;
  final String lang;
  final bool isNsfw;
  final String repoUrl; // URL of the repository it came from
  final String pkg;
  
  // Extension Fields
  final String theme;
  final String popularPath;
  final String scriptFile;

  CatalogSource({
    required this.name,
    required this.baseUrl,
    required this.lang,
    required this.isNsfw,
    required this.repoUrl,
    this.pkg = '',
    this.theme = 'Unknown',
    this.popularPath = '',
    this.scriptFile = '',
  });

  factory CatalogSource.fromJson(Map<String, dynamic> json, String repoUrl, int extensionNsfwStatus, String extensionLang, {String pkg = ''}) {
    // Some sources might have their own lang/nsfw, otherwise inherit from extension
    return CatalogSource(
      name: json['name']?.toString() ?? 'Unknown',
      baseUrl: json['baseUrl']?.toString() ?? '',
      lang: json['lang']?.toString() ?? extensionLang,
      isNsfw: (json['nsfw'] != null) ? (json['nsfw'] == 1 || json['nsfw'] == true) : (extensionNsfwStatus == 1),
      repoUrl: repoUrl,
      pkg: pkg,
      theme: json['theme']?.toString() ?? 'Unknown',
      popularPath: json['popularPath']?.toString() ?? '',
      scriptFile: json['scriptFile']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'baseUrl': baseUrl,
      'lang': lang,
      'isNsfw': isNsfw,
      'repoUrl': repoUrl,
      'pkg': pkg,
    };
  }
}
