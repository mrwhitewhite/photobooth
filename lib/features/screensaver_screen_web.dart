// Original web implementation moved here.
import 'dart:js_interop';
import 'dart:math';
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';

import 'package:provider/provider.dart';
import 'package:web/web.dart' as web;
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
  late web.HTMLVideoElement _video;
  late String _viewId;
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
    _viewId = 'screensaver-video-${DateTime.now().millisecondsSinceEpoch}';

    _video = web.document.createElement('video') as web.HTMLVideoElement
      ..autoplay = true
      ..muted = true
      ..loop = true
      ..playsInline = true
      ..style.objectFit = 'cover'
      ..style.width = '100%'
      ..style.height = '100%'
      ..src = path;

    ui_web.platformViewRegistry.registerViewFactory(
      _viewId,
      (int _) => _video,
    );

    _video.play().toDart.then((_) {
      if (mounted) setState(() => _videoPlaying = true);
    }).catchError((_) {
      if (mounted) setState(() => _videoPlaying = false);
    });
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _video.pause();
    _video.src = '';
    super.dispose();
  }

  void _onTap() {
    final provider = context.read<PhotoboothProvider>();
    if (!_videoPlaying) {
      _video.play().toDart.then((_) {
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
          HtmlElementView(key: ValueKey(_viewId), viewType: _viewId),
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
