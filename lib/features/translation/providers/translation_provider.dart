import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/ai_service.dart';

/// مزود خدمة الترجمة
final translationProvider = Provider<AiService>((ref) {
  return AiService();
});
