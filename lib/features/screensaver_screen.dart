import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import '../services/photobooth_provider.dart';

const _kVideos = [
  'assets/screen_saver/screen_saver_1.mov',
  'assets/screen_saver/screen_saver_2.mov',
];

class ScreensaverScreen extends StatefulWidget {
  const ScreensaverScreen({super.key});

  @override
  State<ScreensaverScreen> createState() => _ScreensaverScreenState();
}

class _ScreensaverScreenState extends State<ScreensaverScreen>
    with SingleTickerProviderStateMixin {
  late VideoPlayerController _controller;
  bool _videoPlaying = false;
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

    _controller = VideoPlayerController.asset(path);
    _controller.initialize().then((_) {
      _controller.setLooping(true);
      _controller.setVolume(0);
      _controller.play();
      if (mounted) setState(() => _videoPlaying = true);
    }).catchError((_) {
      if (mounted) setState(() => _videoPlaying = false);
    });
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onTap() {
    final provider = context.read<PhotoboothProvider>();
    if (!_videoPlaying) {
      _controller.play().then((_) {
        if (mounted) setState(() => _videoPlaying = true);
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
          if (_videoPlaying)
            ClipRect(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _controller.value.size.width,
                  height: _controller.value.size.height,
                  child: VideoPlayer(_controller),
                ),
              ),
            )
          else
            const ColoredBox(color: Colors.black),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.4,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.55),
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
                        color: Colors.white.withValues(alpha: 0.6),
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
                            color: Colors.white.withValues(alpha: 0.9),
                            width: 2,
                          ),
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                        child: const Icon(
                          Icons.touch_app_rounded,
                          color: Colors.white,
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
                    color: Colors.white.withValues(alpha: 0.85),
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
