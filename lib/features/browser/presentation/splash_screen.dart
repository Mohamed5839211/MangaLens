import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import 'root_screen.dart';

/// الشاشة الترحيبية ذات الطابع الفاخر (Animated Premium Splash Screen)
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _progressController;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..forward();

    // انتقال تلقائي بعد 3.5 ثوانٍ لضمان انتهاء الحركات
    Timer(const Duration(milliseconds: 3500), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const RootScreen(),
            transitionsBuilder: (_, animation, __, child) {
              return FadeTransition(
                opacity: animation,
                child: child,
              );
            },
            transitionDuration: const Duration(milliseconds: 800),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // ─── توهج في المنتصف ────────
          Center(
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withOpacity(0.15),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.3),
                    blurRadius: 150,
                    spreadRadius: 80,
                  ),
                ],
              ),
            ).animate().scale(begin: const Offset(0.5, 0.5), duration: 1.seconds, curve: Curves.easeOutCirc).fadeIn(),
          ),

          // ─── المحتوى الرئيسي ────────
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ShaderMask(
                  shaderCallback: (bounds) => AppColors.primaryGradient.createShader(bounds),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'MangaLens',
                      maxLines: 1,
                      style: GoogleFonts.orbitron(
                        fontSize: 52,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 3,
                      ),
                    ),
                  ),
                )
                    .animate()
                    .fadeIn(duration: 800.ms)
                    .scale(begin: const Offset(0.8, 0.8), curve: Curves.easeOutBack, duration: 1.seconds)
                    .shimmer(duration: 2.seconds, blendMode: BlendMode.overlay, delay: 500.ms),
                
                const SizedBox(height: 12),
                
                Text(
                  'بوابتك لعالم المانغا بلا حدود',
                  style: GoogleFonts.cairo(
                    color: AppColors.textSecondary,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1.2,
                  ),
                ).animate().fadeIn(delay: 800.ms).slideY(begin: 0.5, duration: 600.ms, curve: Curves.easeOutQuad),
              ],
            ),
          ),

          // ─── شريط التحميل السفلي (Neon Loader) ────────
          Positioned(
            bottom: 60,
            left: 40,
            right: 40,
            child: Column(
              children: [
                AnimatedBuilder(
                  animation: _progressController,
                  builder: (context, child) {
                    return Container(
                      height: 4,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: AppColors.glassBorder,
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerRight, // لتبدأ من اليمين (RTL)
                        widthFactor: _progressController.value,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: AppColors.primaryGradient,
                            borderRadius: BorderRadius.circular(2),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withOpacity(0.5),
                                blurRadius: 10,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ).animate().fadeIn(delay: 1000.ms),
                
                const SizedBox(height: 12),
                
                Text(
                  'جاري التهيئة...',
                  style: GoogleFonts.cairo(
                    color: AppColors.textDisabled,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ).animate().fadeIn(delay: 1200.ms).shimmer(duration: 1.seconds, delay: 1500.ms),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
