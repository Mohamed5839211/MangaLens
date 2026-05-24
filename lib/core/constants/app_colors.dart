import 'package:flutter/material.dart';

/// لوحة ألوان التطبيق — الوضع الداكن فقط
/// MangaLens Dark Theme Color Palette
class AppColors {
  AppColors._();

  // ─── الخلفيات ───────────────────────────────────────
  /// الخلفية الرئيسية (فضاء مظلم)
  static const Color background = Color(0xFF05050B);

  /// سطح البطاقات والعناصر
  static const Color surface = Color(0xFF0F101A);

  /// سطح مرتفع (للبطاقات والقوائم)
  static const Color surfaceElevated = Color(0xFF161826);

  /// سطح لامع (عناصر تفاعلية)
  static const Color surfaceBright = Color(0xFF23263A);

  // ─── الألوان الرئيسية النيون ───────────────────────
  /// اللون الرئيسي — وردي نيون
  static const Color primary = Color(0xFFFF2A6D);

  /// اللون الرئيسي الفاتح
  static const Color primaryLight = Color(0xFFFF5E8F);

  /// اللون الرئيسي الداكن
  static const Color primaryDark = Color(0xFFC41045);

  /// اللون الثانوي — سماوي نيون
  static const Color secondary = Color(0xFF01FFFF);

  /// اللون الثانوي الفاتح
  static const Color secondaryLight = Color(0xFF6AFFFF);

  // ─── ألوان مميزة ────────────────────────────────────
  /// لون التمييز — بنفسجي نيون
  static const Color accent = Color(0xFFB026FF);

  /// نجاح — أخضر
  static const Color success = Color(0xFF00C853);

  /// تحذير — برتقالي
  static const Color warning = Color(0xFFFF9800);

  /// خطأ — أحمر
  static const Color error = Color(0xFFFF1744);

  /// معلومات — أزرق فاتح
  static const Color info = Color(0xFF29B6F6);

  // ─── النصوص ─────────────────────────────────────────
  /// نص أساسي (أبيض مائل)
  static const Color textPrimary = Color(0xFFEAEAEA);

  /// نص ثانوي (رمادي فاتح)
  static const Color textSecondary = Color(0xFF9E9E9E);

  /// نص معطل
  static const Color textDisabled = Color(0xFF616161);

  /// نص على الخلفية الملونة
  static const Color textOnPrimary = Color(0xFFFFFFFF);

  // ─── الحدود والفواصل ────────────────────────────────
  /// لون الحدود
  static const Color border = Color(0xFF2A2A3E);

  /// لون الفاصل
  static const Color divider = Color(0xFF1E1E32);

  // ─── شريط التنقل ────────────────────────────────────
  /// خلفية شريط التنقل
  static const Color navBarBackground = Color(0xFF111122);

  /// أيقونة نشطة
  static const Color navBarActive = primary;

  /// أيقونة غير نشطة
  static const Color navBarInactive = Color(0xFF6B6B7B);

  // ─── ألوان زجاجية (Glassmorphism) ───────────────────
  /// خلفية زجاجية داكنة
  static const Color glassDark = Color(0x7705050B);

  /// سطح زجاجي مرتفع
  static const Color glassSurface = Color(0x66161826);

  /// حدود زجاجية (لمعان خفيف)
  static const Color glassBorder = Color(0x33FFFFFF);

  /// لمعان وردي زجاجي
  static const Color glassPink = Color(0x22FF2A6D);

  /// لمعان بنفسجي زجاجي
  static const Color glassPurple = Color(0x22B026FF);

  // ─── تدرجات ─────────────────────────────────────────
  /// تدرج رئيسي للبطاقات الفاخرة
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFFFF2A6D), Color(0xFFB026FF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// تدرج الخلفية
  static const LinearGradient backgroundGradient = LinearGradient(
    colors: [background, surface],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  /// تدرج زر الترجمة FAB
  static const LinearGradient fabGradient = LinearGradient(
    colors: [Color(0xFFFF2A6D), Color(0xFFFF5E8F)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
