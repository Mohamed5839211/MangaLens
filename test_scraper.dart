import 'dart:io';
import 'package:html/parser.dart' show parse;
import 'package:dio/dio.dart';

void main() async {
  final dio = Dio();
  
  Future<void> test(String url) async {
    try {
      print('Testing: \$url');
      final response = await dio.get(url, options: Options(validateStatus: (_) => true));
      print('Status: \${response.statusCode}');
      if (response.statusCode != 200) return;
      
      final document = parse(response.data);
      final elements = document.querySelectorAll('.page-item-detail');
      print('Found .page-item-detail elements: \${elements.length}');
      
      if (elements.isNotEmpty) {
        final first = elements.first;
        final aTag = first.querySelector('h3 a');
        final imgTag = first.querySelector('img');
        print('Title: \${aTag?.text.trim()}');
        print('Image src: \${imgTag?.attributes['data-src'] ?? imgTag?.attributes['src']}');
      }
    } catch (e) {
      print('Error: \$e');
    }
  }

  await test('https://manhwaweb.com/manga/page/1/?m_orderby=views');
  await test('https://www.kunmanga.co.uk/manga/page/1/?m_orderby=views');
  await test('https://evascans.org/manga/page/1/?m_orderby=views');
  await test('https://evascans.org/manga/?page=1&order=popular'); // MangaStream test
}
