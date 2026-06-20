import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'dart:io';
import 'app.dart';
import 'core/services/history_service.dart';

import 'features/downloads/data/downloads_service.dart';
import 'core/services/sources_service.dart';
import 'core/services/reading_progress_service.dart';
import 'core/services/repository_service.dart';
import 'core/network/cookie_store.dart';
import 'core/network/network_module.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // تحميل متغيرات البيئة
  await dotenv.load(fileName: ".env");

  // تهيئة قاعدة البيانات المحلية (Hive)
  await HistoryService.init();
  await DownloadsService.init();
  await SourcesService.init();
  await ReadingProgressService.init();
  await RepositoryService.init();

  // تهيئة نظام الشبكة (Cookies + Dio المركزي)
  await CookieStore.init();
  await NetworkModule().init();

  // إعداد WebView لمنصة Android
  if (Platform.isAndroid) {
    await InAppWebViewController.setWebContentsDebuggingEnabled(true);
  }

  runApp(
    const ProviderScope(
      child: MangaLensApp(),
    ),
  );
}
