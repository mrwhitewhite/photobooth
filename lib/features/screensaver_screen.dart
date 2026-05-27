import 'dart:math';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:provider/provider.dart';
import '../services/photobooth_provider.dart';

const _kVideos = [
  'assets/screen_saver/screen_saver_1.mp4',
  'assets/screen_saver/screen_saver_2.mp4',
];

class ScreensaverScreen extends StatefulWidget {
  const ScreensaverScreen({super.key});

  @override
  State<ScreensaverScreen> createState() => _ScreensaverScreenState();
}

class _ScreensaverScreenState extends State<ScreensaverScreen>
    with SingleTickerProviderStateMixin {
  VideoPlayerController? _controller;
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.6, end: 1.0)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    final path = _kVideos[Random().nextInt(_kVideos.length)];
    _controller = VideoPlayerController.asset(path)
      ..setLooping(true)
      ..setVolume(0)
      ..initialize().then((_) {
        if (!mounted) return;
        _controller!.play();
        setState(() {});
      }).catchError((_) {
        if (mounted) setState(() {});
      });
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _controller?.dispose();
    super.dispose();
  }

  void _onTap() {
    final provider = context.read<PhotoboothProvider>();
    final controller = _controller;
    if (controller != null && !controller.value.isPlaying) {
      controller.play().then((_) {
        if (mounted) setState(() {});
      }).catchError((_) {});
    }

    Future.delayed(const Duration(milliseconds: 120), () {
      if (mounted) provider.goToHomepage();
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_controller != null && _controller!.value.isInitialized)
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _controller!.value.size.width,
                height: _controller!.value.size.height,
                child: VideoPlayer(_controller!),
              ),
            )
          else
            const ColoredBox(color: Color(0xFFFFFFEA)),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.4,
                colors: [
                  Colors.transparent,
                  const Color(0xFFFFFFEA).withValues(alpha: 0.75),
                ],
              ),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FadeTransition(
                  opacity: _pulseAnim,
                  child: Container(
                    width: 160,
                    height: 160,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFFD9B87C).withValues(alpha: 0.55),
                        width: 1.5,
                      ),
                    ),
                    child: Center(
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color:
                                const Color(0xFFD9B87C).withValues(alpha: 0.85),
                            width: 2,
                          ),
                          color: const Color(0xFFFFFFEA).withValues(alpha: 0.6),
                        ),
                        child: const Icon(
                          Icons.touch_app_rounded,
                          color: Color(0xFF4A4638),
                          size: 42,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  'TAP TO START',
                  style: TextStyle(
                    fontFamily: 'PoppinsMedium',
                    fontSize: 13,
                    letterSpacing: 6,
                    color: const Color(0xFF4A4638).withValues(alpha: 0.85),
                    fontWeight: FontWeight.w300,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
