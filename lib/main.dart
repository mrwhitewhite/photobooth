import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';

import 'services/photobooth_provider.dart';
import 'features/camera_view.dart';
import 'features/home_screen.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => PhotoboothProvider(),
      child: const SnapBoothApp(),
    ),
  );
}

class SnapBoothApp extends StatelessWidget {
  const SnapBoothApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: true,
      title: 'SnapBooth',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0D0A05),
        primaryColor: const Color(0xFFE8C4A0),
        textTheme: GoogleFonts.latoTextTheme(ThemeData.dark().textTheme),
      ),
      home: const MainScaffold(),
    );
  }
}

class MainScaffold extends StatelessWidget {
  const MainScaffold({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PhotoboothProvider>();
    final cameraKey = GlobalKey<CameraViewState>();

    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 500),
        child: _buildBody(provider, cameraKey),
      ),
    );
  }

  Widget _buildBody(
      PhotoboothProvider provider, GlobalKey<CameraViewState> cameraKey) {
    return switch (provider.state) {
      AppState.layoutSelect => const HomeScreen(),
      AppState.camera => Stack(
          key: const ValueKey('camera_screen'),
          children: [
            CameraView(
              key: cameraKey,
              onCapture: (bytes) => provider.addPhoto(bytes),
            ),
            Positioned(
              top: 40,
              right: 40,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE8C4A0)),
                ),
                child: Text(
                  'SHOT ${provider.photos.length + 1} / ${provider.selectedLayout.photoCount}',
                  style: GoogleFonts.lato(
                    color: const Color(0xFFE8C4A0),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 50,
              left: 0,
              right: 0,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: () => cameraKey.currentState?.startCountdown(),
                      child: Container(
                        height: 80,
                        width: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFE8C4A0)
                                  .withValues(alpha: 0.5),
                              blurRadius: 20,
                              spreadRadius: 5,
                            )
                          ],
                        ),
                        child: const Center(
                          child: Icon(Icons.camera_alt,
                              color: Colors.black, size: 32),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'TAP TO START COUNTDOWN',
                      style: GoogleFonts.lato(
                        color: const Color(0xFFE8C4A0),
                        letterSpacing: 2,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      AppState.review => Center(
          key: const ValueKey('review_screen'),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '✦ Review Your Shots ✦',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 32,
                  color: const Color(0xFFE8C4A0),
                ),
              ),
              const SizedBox(height: 20),
              if (provider.photos.isNotEmpty)
                Container(
                  decoration: BoxDecoration(
                    border:
                        Border.all(color: const Color(0xFFE8C4A0), width: 4),
                    boxShadow: const [
                      BoxShadow(color: Colors.black54, blurRadius: 20),
                    ],
                  ),
                  child: Image.memory(provider.photos.last, height: 400),
                ),
              const SizedBox(height: 30),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton(
                    onPressed: () => provider.reset(),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: const Color(0xFFE8C4A0).withValues(alpha: 0.5),
                      ),
                    ),
                    child: const Text('RETAKE ALL'),
                  ),
                  const SizedBox(width: 20),
                  ElevatedButton(
                    onPressed: () {
                      // Logic for finalizing the strip will follow
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE8C4A0),
                      foregroundColor: Colors.black,
                    ),
                    child: const Text('PROCEED TO PRINT'),
                  ),
                ],
              ),
            ],
          ),
        ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}
