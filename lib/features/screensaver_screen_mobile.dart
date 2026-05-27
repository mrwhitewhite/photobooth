import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/photobooth_provider.dart';

class ScreensaverScreen extends StatelessWidget {
  const ScreensaverScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.read<PhotoboothProvider>().goToHomepage(),
      child: Container(
        color: Colors.black,
        child: const Center(
          child: Text(
            'TAP TO START',
            style: TextStyle(color: Colors.white),
          ),
        ),
      ),
    );
  }
}
