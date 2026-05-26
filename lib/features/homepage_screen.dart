import 'package:flutter/material.dart';

import 'package:provider/provider.dart';
import '../services/photobooth_provider.dart';

class HomepageScreen extends StatefulWidget {
  const HomepageScreen({super.key});

  @override
  State<HomepageScreen> createState() => _HomepageScreenState();
}

class _HomepageScreenState extends State<HomepageScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fadeIn;
  late Animation<double> _slideUp;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _fadeIn = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slideUp = Tween<double>(begin: 40, end: 0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // ── Full-bleed background ────────────────────────────────────────────
        Positioned.fill(
          child: Image.asset(
            'assets/homepage.png',
            fit: BoxFit.cover,
          ),
        ),

        // ── Subtle dark gradient at bottom for button legibility ──────────────
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          height: 280,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.70),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),

        // ── Content ──────────────────────────────────────────────────────────
        Positioned(
          bottom: 60,
          left: 0,
          right: 0,
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (context, child) => Opacity(
              opacity: _fadeIn.value,
              child: Transform.translate(
                offset: Offset(0, _slideUp.value),
                child: child,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/logo.png',
                  height: 80,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 8),
                // Text(
                //   'YOUR PERFECT MOMENT AWAITS',
                //   style: TextStyle(
                //     fontFamily: 'CHAOS16',
                //     fontSize: 11,
                //     letterSpacing: 5,
                //     color: Colors.white.withValues(alpha: 0.75),
                //     fontWeight: FontWeight.w300,
                //   ),
                // ),
                const SizedBox(height: 40),
                _StartButton(
                  onTap: () =>
                      context.read<PhotoboothProvider>().goToLayoutSelect(),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Animated START button ─────────────────────────────────────────────────────
class _StartButton extends StatefulWidget {
  final VoidCallback onTap;
  const _StartButton({required this.onTap});

  @override
  State<_StartButton> createState() => _StartButtonState();
}

class _StartButtonState extends State<_StartButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 150));
    _scale = Tween<double>(begin: 1.0, end: 0.93)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        widget.onTap();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          width: 220,
          height: 64,
          decoration: BoxDecoration(
            color: const Color(0xFFC0C0C0),
            border: Border.all(color: Colors.black, width: 4),
          ),
          child: Container(
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: Colors.white, width: 4),
                left: BorderSide(color: Colors.white, width: 4),
                bottom: BorderSide(color: Color(0xFF808080), width: 4),
                right: BorderSide(color: Color(0xFF808080), width: 4),
              ),
            ),
            child: const Center(
              child: Text(
                'Start',
                style: TextStyle(
                  fontFamily: 'CHAOS16',
                  fontSize: 24,
                  color: Colors.black,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
