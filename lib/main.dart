import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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

// ─────────────────────────────────────────────────────────────────────────────
// App root
// ─────────────────────────────────────────────────────────────────────────────
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
    const bg = Color(0xFF0D0D0D);
    const surface = Color(0xFF1A1A1A);
    const accent = Color(0xFFE8C8A0);
    const text = Color(0xFFF0EDE8);

    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      primaryColor: accent,
      colorScheme: const ColorScheme.dark(
        primary: accent,
        surface: surface,
        onSurface: text,
      ),
      textTheme: GoogleFonts.latoTextTheme(ThemeData.dark().textTheme).apply(
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

// ─────────────────────────────────────────────────────────────────────────────
// Shell — routes between all 5 app states
// ─────────────────────────────────────────────────────────────────────────────
class _AppShell extends StatelessWidget {
  const _AppShell();

  @override
  Widget build(BuildContext context) {
    final state = context.select<PhotoboothProvider, AppState>(
      (p) => p.state,
    );

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 600),
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: CurvedAnimation(parent: anim, curve: Curves.easeInOut),
        child: child,
      ),
      child: _screenForState(state),
    );
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
  