import 'dart:io';
import 'dart:convert';

void main() async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse('https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.min.json'));
    final response = await request.close();
    final stringData = await response.transform(utf8.decoder).join();
    
    final List<dynamic> liveSources = jsonDecode(stringData);
    
    final mappingsFile = File('extensions/mappings.json');
    Map<String, dynamic> parsedMappings = {};
    if (mappingsFile.existsSync()) {
      parsedMappings = jsonDecode(await mappingsFile.readAsString());
    }

    final fullDatabase = <String, Map<String, dynamic>>{};

    for (final ext in liveSources) {
      if (!ext.containsKey('sources')) continue;
      
      final sourcesList = ext['sources'] as List<dynamic>;
      for (final source in sourcesList) {
        String baseUrl = source['baseUrl'];
        String name = source['name'];
        String lang = source['lang'];
        
        String cleanBaseUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
        
        Map<String, dynamic>? mapping;
        if (parsedMappings.containsKey(cleanBaseUrl)) {
          mapping = parsedMappings[cleanBaseUrl];
        } else {
          for (var entry in parsedMappings.entries) {
            if (entry.value['name'].toString().toLowerCase() == name.toLowerCase()) {
              mapping = entry.value;
              break;
            }
          }
        }

        String theme = mapping != null ? mapping['theme'] : 'Madara';
        String popularPath = mapping != null ? mapping['popularPath'] : '/manga/page/{page}/?m_orderby=views';
        String scriptFile = mapping != null ? mapping['scriptFile'] : 'universal_madara.js';

        fullDatabase[cleanBaseUrl] = {
          'name': name,
          'lang': lang,
          'theme': theme,
          'popularPath': popularPath,
          'scriptFile': scriptFile,
        };
      }
    }

    final dbFile = File('extensions/mangalens_database.json');
    await dbFile.writeAsString(JsonEncoder.withIndent('  ').convert(fullDatabase));
    print('SUCCESS: Built Ultimate Database with ${fullDatabase.length} sources!');
    
  } catch (e, stack) {
    print('Error: $e\n$stack');
  } finally {
    client.close();
  }
}
