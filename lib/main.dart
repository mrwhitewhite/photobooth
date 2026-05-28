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
      title: 'i snap you',
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
    final state = context.select<PhotoboothProvider, AppState>((p) => p.state);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 450),
      switchInCurve: Curves.easeOut,
      transitionBuilder: (child, animation) {
        final isIncoming = child.key == _keyForState(state);
        if (isIncoming) {
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

        return child;
      },
      child: _screenForState(state),
    );
  }

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
      AppState.homepage => const HomepageScreen(key: ValueKey('homepage')),
      AppState.layoutSelect => const HomeScreen(key: ValueKey('layout')),
      AppState.camera => const CameraView(key: ValueKey('camera')),
      AppState.preview => const PreviewScreen(key: ValueKey('preview')),
    };
  }
}
