import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'services/photobooth_provider.dart';
import 'features/screensaver_screen.dart';
import 'features/homepage_screen.dart';
import 'features/home_screen.dart';
import 'features/camera_view.dart';
import 'features/preview_screen.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => PhotoboothProvider(),
      child: const MyReceiptApp(),
    ),
  );
}

class MyReceiptApp extends StatelessWidget {
  const MyReceiptApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'MyReceipt',
      theme: _buildTheme(),
      home: const _AppShell(),
    );
  }

  ThemeData _buildTheme() {
    const bg = Color(0xFFFFFFEA);
    const surface = Color(0xFFF7F3D6);
    const accent = Color(0xFFD9B87C);
    const text = Color(0xFF4A4638);

    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: bg,
      primaryColor: accent,
      colorScheme: const ColorScheme.light(
        primary: accent,
        surface: surface,
        onSurface: text,
      ),
      textTheme: ThemeData.light().textTheme.apply(
            fontFamily: 'PoppinsMedium',
            bodyColor: text,
            displayColor: text,
          ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: surface,
        contentTextStyle: TextStyle(color: text),
      ),
    );
  }
}

class _AppShell extends StatelessWidget {
  const _AppShell();

  @override
  Widget build(BuildContext context) {
    final state =
        context.select<PhotoboothProvider, AppState>((p) => p.state);

    // ── Screensaver + Homepage ───────────────────────────────────────
    // 两个页面同时保持在后台渲染（IndexedStack），切换瞬间完成，无黑屏
    if (state == AppState.screensaver || state == AppState.homepage) {
      return IndexedStack(
        index: state == AppState.screensaver ? 0 : 1,
        children: const [
          ScreensaverScreen(key: ValueKey('screensaver')),
          HomepageScreen(key: ValueKey('homepage')),
        ],
      );
    }

    // ── Layout / Camera / Preview ────────────────────────────────────
    // 使用 AnimatedSwitcher：旧页面元素保持存活（避免 CameraView 重复初始化），
    // 新页面从下方滑入覆盖，旧页面保持全不透明（无黑屏）
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 450),
      switchInCurve: Curves.easeOut,
      transitionBuilder: (child, animation) {
        final isIncoming = child.key == _keyForState(state);
        if (isIncoming) {
          // 新页面：淡入 + 向上滑入
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.06),
                end: Offset.zero,
              ).animate(
                  CurvedAnimation(parent: animation, curve: Curves.easeOut)),
              child: child,
            ),
          );
        }
        // 旧页面：保持全不透明，不做任何动画，新页面在上方滑入
        return child;
      },
      child: _screenForState(state),
    );
  }

  /// 用于判断 transitionBuilder 中哪个 child 是"新进入"的
  ValueKey<String> _keyForState(AppState state) {
    return switch (state) {
      AppState.screensaver => const ValueKey('screensaver'),
      AppState.homepage => const ValueKey('homepage'),
      AppState.layoutSelect => const ValueKey('layout'),
      AppState.camera => const ValueKey('camera'),
      AppState.preview => const ValueKey('preview'),
    };
  }

  Widget _screenForState(AppState state) {
    return switch (state) {
      AppState.screensaver =>
        const ScreensaverScreen(key: ValueKey('screensaver')),
      AppState.homepage =>
        const HomepageScreen(key: ValueKey('homepage')),
      AppState.layoutSelect =>
        const HomeScreen(key: ValueKey('layout')),
      AppState.camera => const CameraView(key: ValueKey('camera')),
      AppState.preview =>
        const PreviewScreen(key: ValueKey('preview')),
    };
  }
}
