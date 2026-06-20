import 'dart:io';
import 'dart:convert';

void main() async {
  final srcDir = Directory('extensions_source_tmp/src');
  if (!srcDir.existsSync()) {
    print('Run the clone script first.');
    return;
  }

  final mappings = <String, Map<String, dynamic>>{};

  await for (final entity in srcDir.list(recursive: true, followLinks: false)) {
    if (entity is File && entity.path.endsWith('build.gradle')) {
      final content = await entity.readAsString();
      
      // Extract baseUrl and name
      final baseUrlMatch = RegExp(r"baseUrl\s*=\s*['""]([^'""]+)['""]").firstMatch(content);
      final extClassMatch = RegExp(r"extClass\s*=\s*['""]\.([^'""]+)['""]").firstMatch(content);
      final themePkgMatch = RegExp(r"themePkg\s*=\s*['""]([^'""]+)['""]").firstMatch(content);
      
      if (baseUrlMatch != null && extClassMatch != null) {
        final baseUrl = baseUrlMatch.group(1)!;
        final name = extClassMatch.group(1)!;
        
        String theme = themePkgMatch != null ? themePkgMatch.group(1)! : 'Unknown';
        String popularPath = '';
        String scriptFile = '';

        // Determine default path based on themePkg
        if (theme == 'madara' || theme == 'Madara') {
            theme = 'Madara';
            scriptFile = 'universal_madara.js';
            popularPath = '/manga/page/{page}/?m_orderby=views';
        } else if (theme == 'mangathemesia' || theme == 'MangaThemesia') {
            theme = 'MangaThemesia';
            scriptFile = 'universal_mangathemesia.js';
            popularPath = '/manga/?page={page}&order=popular';
        } else if (theme == 'wordpress' || theme == 'WordPress') {
            theme = 'WordPress';
        }
        
        // Find the corresponding .kt file to check for overrides
        final ktDir = Directory(entity.parent.path);
        File? ktFile;
        await for (final file in ktDir.list(recursive: true)) {
          if (file is File && file.path.endsWith('$name.kt')) {
            ktFile = file;
            break;
          }
        }

        if (ktFile != null && (theme == 'Madara' || theme == 'MangaThemesia')) {
          final ktContent = await ktFile.readAsString();
          
          if (theme == 'Madara') {
            final subStringMatch = RegExp(r"mangaSubString\s*=\s*['""]([^'""]+)['""]").firstMatch(ktContent);
            if (subStringMatch != null) {
              popularPath = '/${subStringMatch.group(1)!}/page/{page}/?m_orderby=views';
            }
          } else if (theme == 'MangaThemesia') {
            final ctorMatch = RegExp(r'MangaThemesia\s*\([^,]+,\s*[^,]+,\s*[^,]+,\s*"([^"]+)"').firstMatch(ktContent);
            if (ctorMatch != null) {
               String subDir = ctorMatch.group(1)!;
               popularPath = '$subDir/?page={page}&order=popular';
            }
          }
        }

        if (theme == 'Madara' || theme == 'MangaThemesia' || theme == 'WordPress') {
          // Remove trailing slash from baseUrl if exists
          final cleanBaseUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
          mappings[cleanBaseUrl] = {
            'name': name,
            'theme': theme,
            'popularPath': popularPath,
            'scriptFile': scriptFile,
          };
        }
      }
    }
  }

  // Create extensions directory if not exists
  final extDir = Directory('extensions');
  if (!extDir.existsSync()) {
    extDir.createSync();
  }

  // Save to JSON
  final file = File('extensions/mappings.json');
  await file.writeAsString(JsonEncoder.withIndent('  ').convert(mappings));
  print('Extracted ${mappings.length} sources successfully!');
}
