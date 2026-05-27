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

class _ScreensaverScreenState extends State<ScreensaverScreen> {
  VideoPlayerController? _controller;

  @override
  void initState() {
    super.initState();

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
        ],
      ),
    );
  }
}
