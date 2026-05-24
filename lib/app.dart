import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'core/localization/app_localizations.dart';
import 'features/browser/presentation/browser_screen.dart';
import 'features/browser/presentation/splash_screen.dart';
import 'features/settings/providers/settings_provider.dart';
import 'widgets/loading_overlay.dart';
import 'features/pipeline/providers/pipeline_provider.dart';
import 'features/pipeline/models/pipeline_state.dart';
import 'features/rendering/presentation/translated_overlay.dart';

/// التطبيق الجذري
/// Root application widget
class MangaLensApp extends ConsumerWidget {
  const MangaLensApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsState = ref.watch(settingsProvider);

    // إذا لم يتم تحميل الإعدادات بعد، نعرض شاشة فارغة أو شعار
    if (!settingsState.isLoaded) {
      return MaterialApp(
        theme: AppTheme.darkTheme,
        home: const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return MaterialApp(
      title: 'MangaLens',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      
      // ─── إعدادات اللغة ─────────────────────────────
      locale: Locale(settingsState.language),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],

      // ─── الصفحة الرئيسية ───────────────────────────
      home: const SplashScreen(),
    );
  }
}

/// شاشة المتصفح الرئيسية التي تحتوي المتصفح وعدسة الترجمة
class MainBrowserScreen extends ConsumerWidget {
  final String initialUrl;
  const MainBrowserScreen({super.key, required this.initialUrl});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pipelineState = ref.watch(pipelineProvider);

    // الاستماع لحالة خطأ في خط الأنابيب لعرض رسالة
    ref.listen<PipelineState>(pipelineProvider, (previous, next) {
      if (next.status == PipelineStatus.error && next.errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.errorMessage!),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    });

    return Scaffold(
      body: Stack(
        children: [
          // المتصفح
          BrowserScreen(initialUrl: initialUrl),
          
          // الصورة المترجمة
          if (pipelineState.status == PipelineStatus.completed && pipelineState.finalImage != null)
            TranslatedOverlay(imageBytes: pipelineState.finalImage!),

          // غطاء التحميل (يظهر فقط أثناء الترجمة)
          const LoadingOverlay(),
        ],
      ),
    );
  }
}
