import 'dart:io';
import 'dart:convert';

void main() async {
  final request = await HttpClient().getUrl(Uri.parse('https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.min.json'));
  final response = await request.close();
  final data = jsonDecode(await response.transform(utf8.decoder).join());
  print(data[0]);
}
