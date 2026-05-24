/// سكريبت اختبار موديلات Groq المتاحة
/// Run: dart run scripts/check_groq_models.dart
import 'dart:convert';
import 'dart:io';

void main() async {
  final apiKey = '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';
  
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse('https://api.groq.com/openai/v1/models'));
    request.headers.set('Authorization', 'Bearer $apiKey');
    request.headers.set('Content-Type', 'application/json');
    
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    
    if (response.statusCode == 200) {
      final data = jsonDecode(body);
      final models = data['data'] as List;
      
      print('═══════════════════════════════════════════════');
      print('  🤖 Groq Available Models (${models.length} total)');
      print('═══════════════════════════════════════════════\n');
      
      // ترتيب أبجدي
      models.sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
      
      for (final model in models) {
        final id = model['id'];
        final ownedBy = model['owned_by'] ?? 'unknown';
        final active = model['active'] ?? true;
        final contextWindow = model['context_window'] ?? '?';
        
        print('  ${active ? "✅" : "❌"} $id');
        print('     Owner: $ownedBy | Context: $contextWindow tokens');
        print('');
      }
    } else {
      print('❌ Error ${response.statusCode}: $body');
    }
  } catch (e) {
    print('❌ Connection Error: $e');
  } finally {
    client.close();
  }
}
