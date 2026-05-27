import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:provider/provider.dart';
import '../services/photobooth_provider.dart';

class ScreensaverScreen extends StatefulWidget {
  const ScreensaverScreen({super.key});

  @override
  State<ScreensaverScreen> createState() => _ScreensaverScreenState();
}

class _ScreensaverScreenState extends State<ScreensaverScreen> {
  VideoPlayerController? _controller;
  bool _isExiting = false;

  @override
  void initState() {
    super.initState();

    const path = "assets/video/start_video.mp4";
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
    if (_isExiting) return;
    _isExiting = true;

    final provider = context.read<PhotoboothProvider>();
    final controller = _controller;

    provider.goToHomepage();

    _releaseVideoInBackground(controller);
  }

  void _releaseVideoInBackground(VideoPlayerController? controller) {
    unawaited(
      Future(() async {
        try {
          await controller?.pause();
          await controller?.dispose();
        } catch (_) {}
      }),
    );
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
