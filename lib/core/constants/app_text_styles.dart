import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// أنماط النصوص — عربي أولاً
/// Text styles — Arabic first
class AppTextStyles {
  AppTextStyles._();

  // ─── العناوين ───────────────────────────────────────

  /// عنوان كبير
  static TextStyle headlineLarge = GoogleFonts.cairo(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    height: 1.4,
  );

  /// عنوان متوسط
  static TextStyle headlineMedium = GoogleFonts.cairo(
    fontSize: 22,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    height: 1.4,
  );

  /// عنوان صغير
  static TextStyle headlineSmall = GoogleFonts.cairo(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    height: 1.4,
  );

  // ─── النص الأساسي ──────────────────────────────────

  /// نص كبير
  static TextStyle bodyLarge = GoogleFonts.cairo(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
    height: 1.5,
  );

  /// نص متوسط
  static TextStyle bodyMedium = GoogleFonts.cairo(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
    height: 1.5,
  );

  /// نص صغير
  static TextStyle bodySmall = GoogleFonts.cairo(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    height: 1.5,
  );

  // ─── التسميات ───────────────────────────────────────

  /// تسمية كبيرة
  static TextStyle labelLarge = GoogleFonts.cairo(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary,
    letterSpacing: 0.1,
  );

  /// تسمية متوسطة
  static TextStyle labelMedium = GoogleFonts.cairo(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
    letterSpacing: 0.5,
  );

  /// تسمية صغيرة
  static TextStyle labelSmall = GoogleFonts.cairo(
    fontSize: 10,
    fontWeight: FontWeight.w500,
    color: AppColors.textDisabled,
    letterSpacing: 0.5,
  );

  // ─── أنماط خاصة ─────────────────────────────────────

  /// نص شريط العنوان URL
  static TextStyle urlBar = GoogleFonts.inter(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    letterSpacing: 0.2,
  );

  /// نص الأزرار
  static TextStyle button = GoogleFonts.cairo(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppColors.textOnPrimary,
    letterSpacing: 0.5,
  );

  /// نص الخطأ
  static TextStyle error = GoogleFonts.cairo(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.error,
  );

  /// نص الترجمة داخل الفقاعات
  static TextStyle bubbleText = GoogleFonts.cairo(
    fontSize: 14,
    fontWeight: FontWeight.w700,
    color: Colors.black,
    height: 1.2,
  );
}
