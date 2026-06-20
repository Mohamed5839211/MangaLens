import 'package:dio/dio.dart';
void main() async {
  final dio = Dio();
  try {
    final res = await dio.get('https://evascans.org', options: Options(validateStatus: (_) => true));
    print(res.statusCode);
    print(res.data.toString().substring(0, 300));
  } catch(e) {
    print(e);
  }
}
