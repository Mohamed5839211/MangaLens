import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'dart:io';
import 'app.dart';
import 'core/services/history_service.dart';

import 'features/downloads/data/downloads_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // تحميل متغيرات البيئة
  await dotenv.load(fileName: ".env");

  // تهيئة قاعدة البيانات المحلية (Hive)
  await HistoryService.init();
  await DownloadsService.init();

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
