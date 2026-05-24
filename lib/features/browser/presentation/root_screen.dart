import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/navigation_provider.dart';
import '../../../app.dart';
import 'home_screen.dart';

/// الشاشة الجذرية التي تحافظ على حالة المتصفح عبر IndexedStack
/// Root screen that preserves browser state using IndexedStack
class RootScreen extends ConsumerWidget {
  const RootScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIndex = ref.watch(navigationProvider);

    return Scaffold(
      body: IndexedStack(
        index: currentIndex,
        children: const [
          // Index 0: الرئيسية
          HomeScreen(),
          // Index 1: المتصفح
          MainBrowserScreen(initialUrl: 'https://www.google.com'),
        ],
      ),
    );
  }
}
