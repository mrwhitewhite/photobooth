import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/photo_models.dart';
import '../services/photobooth_provider.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '✦ SnapBooth ✦',
              style: GoogleFonts.playfairDisplay(
                fontSize: 48,
                color: const Color(0xFFE8C4A0), // Gold
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'CHOOSE YOUR LAYOUT',
              style: GoogleFonts.lato(
                letterSpacing: 4,
                color: const Color(0xFF8C6E52), // Muted text
              ),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: 600,
              child: GridView.count(
                shrinkWrap: true,
                crossAxisCount: 2,
                mainAxisSpacing: 20,
                crossAxisSpacing: 20,
                children: PhotoLayout.values
                    .map((layout) => LayoutCard(layout: layout))
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LayoutCard extends StatelessWidget {
  final PhotoLayout layout;
  const LayoutCard({super.key, required this.layout});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.read<PhotoboothProvider>().startSession(layout),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1A1208), // Surface color[cite: 1]
          border: Border.all(color: const Color(0xFFE8C4A0), width: 2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Placeholder for the "tiny strip preview" requested[cite: 1]
            Container(
              width: 40,
              height: 100,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF3D2E1E)),
              ),
              child: Column(
                children: List.generate(
                    layout.photoCount,
                    (index) => Expanded(
                        child: Container(
                            margin: const EdgeInsets.all(2),
                            color: const Color(0xFF3D2E1E)))),
              ),
            ),
            const SizedBox(height: 12),
            Text(layout.label,
                style: GoogleFonts.playfairDisplay(
                    color: const Color(0xFFE8C4A0))),
          ],
        ),
      ),
    );
  }
}
