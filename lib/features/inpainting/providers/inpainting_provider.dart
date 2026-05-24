import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/inpainting_service.dart';

/// مزود خدمة الـ Inpainting
/// Inpainting Service Provider
final inpaintingServiceProvider = Provider<InpaintingService>((ref) {
  return InpaintingService();
});
