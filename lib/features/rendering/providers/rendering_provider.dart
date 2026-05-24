import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/text_renderer.dart';

/// مزود عارض النصوص
/// Text Renderer Provider
final textRendererProvider = Provider<TextRenderer>((ref) {
  return TextRenderer();
});
