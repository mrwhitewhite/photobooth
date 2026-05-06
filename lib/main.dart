import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';

import 'services/photobooth_provider.dart';
import 'features/camera_view.dart';
import 'features/home_screen.dart'; // Ensure this exists based on previous step

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
      debugShowCheckedModeBanner: false,
      title: 'SnapBooth',
      theme: ThemeData(
        brightness: Brightness.dark,
        // Art-deco background and surface colors
        scaffoldBackgroundColor: const Color(0xFF0D0A05),
        primaryColor: const Color(0xFFE8C4A0),
        // Applying Lato for body text as per requirements
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
    // GlobalKey allows us to call the takePhoto() method inside CameraViewState
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
      // 1. Layout Selection Screen[cite: 1]
      AppState.layoutSelect => const HomeScreen(),

      // 2. Camera Capture Screen[cite: 1]
      AppState.camera => Stack(
          key: const ValueKey('camera_screen'),
          children: [
            CameraView(
              key: cameraKey,
              onCapture: (bytes) => provider.addPhoto(bytes),
            ),
            // Shot counter overlay[cite: 1]
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
                      fontWeight: FontWeight.bold),
                ),
              ),
            ),
            // Shutter Button[cite: 1]
            Positioned(
              bottom: 50,
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: () => cameraKey.currentState?.takePhoto(),
                  child: Container(
                    height: 80,
                    width: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFE8C4A0).withOpacity(0.5),
                          blurRadius: 20,
                          spreadRadius: 5,
                        )
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),

      // 3. Review Screen[cite: 1]
      AppState.review => Center(
          key: const ValueKey('review_screen'),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '✦ Review Your Shots ✦',
                style: GoogleFonts.playfairDisplay(
                    fontSize: 32, color: const Color(0xFFE8C4A0)),
              ),
              const SizedBox(height: 20),
              // Simple preview of the last taken shot
              if (provider.photos.isNotEmpty)
                Container(
                  decoration: BoxDecoration(
                    border:
                        Border.all(color: const Color(0xFFE8C4A0), width: 4),
                  ),
                  child: Image.memory(provider.photos.last, height: 400),
                ),
              const SizedBox(height: 30),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton(
                    onPressed: () => provider.reset(),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3D2E1E)),
                    child: const Text('RETAKE ALL'),
                  ),
                  const SizedBox(width: 20),
                  ElevatedButton(
                    onPressed: () {
                      // Logic for finalizing and printing will go here[cite: 1]
                    },
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE8C4A0)),
                    child: const Text('PROCEED',
                        style: TextStyle(color: Colors.black)),
                  ),
                ],
              ),
            ],
          ),
        ),

      // Default / Loading fallback
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}
