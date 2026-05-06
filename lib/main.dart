import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'services/photobooth_provider.dart';
import 'features/camera_view.dart';

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
      body: switch (provider.state) {
        AppState.layoutSelect => Center(
            child: ElevatedButton(
              onPressed: () => provider.startSession(),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE8C4A0),
              ),
              child: Text(
                "START BOOTH",
                style: GoogleFonts.playfairDisplay(color: Colors.black),
              ),
            ),
          ),
        AppState.camera => Stack(
            children: [
              CameraView(
                key: cameraKey,
                onCapture: (bytes) => provider.addPhoto(bytes),
              ),
              Positioned(
                bottom: 40,
                left: 0,
                right: 0,
                child: FloatingActionButton(
                  onPressed: () => cameraKey.currentState?.takePhoto(),
                  child: const Icon(Icons.camera),
                ),
              ),
            ],
          ),
        AppState.review => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (provider.lastPhoto != null)
                  Image.memory(provider.lastPhoto!, height: 300),
                TextButton(
                  onPressed: () => provider.reset(),
                  child: const Text("RETAKE"),
                ),
              ],
            ),
          ),
        _ => const SizedBox.shrink(),
      },
    );
  }
}
