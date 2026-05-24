import 'package:flutter_riverpod/flutter_riverpod.dart';

/// مزود لإدارة مؤشر التنقل بين الشاشات الرئيسية
/// 0 = HomeScreen (الرئيسية)
/// 1 = BrowserScreen (المتصفح)
final navigationProvider = StateProvider<int>((ref) => 0);
