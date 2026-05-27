import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/photobooth_provider.dart';

class CameraView extends StatelessWidget {
  const CameraView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080808),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Camera not available on this platform',
                style: TextStyle(color: Colors.white)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => context.read<PhotoboothProvider>().goToHomepage(),
              child: const Text('Back'),
            ),
          ],
        ),
      ),
    );
  }
}
