import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:web/web.dart' as web;
import '../services/photobooth_provider.dart';

class CameraView extends StatefulWidget {
  const CameraView({super.key});

  @override
  CameraViewState createState() => CameraViewState();
}

class CameraViewState extends State<CameraView>
    with SingleTickerProviderStateMixin {
  late web.HTMLVideoElement _videoElement;
  late String _viewID;

  int _countdown = 0;
  bool _showFlash = false;
  bool _isCapturing = false;
  bool _cameraReady = false;
  Uint8List? _lastCapture;
  bool _showLastCapture = false;

  late AnimationController _countdownAnim;
  late Animation<double> _countdownScale;
  late Animation<double> _countdownOpacity;

  @override
  void initState() {
    super.initState();
    _viewID = 'camera-view-${DateTime.now().millisecondsSinceEpoch}';

    _countdownAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _countdownScale = Tween<double>(begin: 1.6, end: 0.85)
        .animate(CurvedAnimation(parent: _countdownAnim, curve: Curves.easeOut));
    _countdownOpacity = Tween<double>(begin: 1.0, end: 0.0)
        .animate(CurvedAnimation(parent: _countdownAnim, curve: Curves.easeIn));

    _videoElement = web.document.createElement('video') as web.HTMLVideoElement
      ..autoplay = true
      ..muted = true
      ..playsInline = true
      ..style.transform = 'scaleX(-1)' // mirror effect
      ..style.objectFit = 'cover'
      ..style.width = '100%'
      ..style.height = '100%';

    ui_web.platformViewRegistry
        .registerViewFactory(_viewID, (int _) => _videoElement);

    _initCamera();
  }

  @override
  void dispose() {
    _countdownAnim.dispose();
    _stopCamera();
    super.dispose();
  }

  void _stopCamera() {
    if (_videoElement.srcObject != null) {
      final stream = _videoElement.srcObject as web.MediaStream;
      for (final track in stream.getTracks().toDart) {
        track.stop();
      }
    }
  }

  Future<void> _initCamera() async {
    final constraints =
        {'video': {'facingMode': 'user'}, 'audio': false}.jsify()
            as web.MediaStreamConstraints;
    try {
      final stream = await web.window.navigator.mediaDevices
          .getUserMedia(constraints)
          .toDart;
      _videoElement.srcObject = stream;
      await _videoElement.play().toDart;

      if (mounted) {
        setState(() => _cameraReady = true);
        // Auto-start the capture sequence after a 2-second "get ready" delay
        Future.delayed(const Duration(seconds: 2), _startNextCapture);
      }
    } catch (e) {
      debugPrint('Camera Error: $e');
    }
  }

  /// Runs countdown for one photo, captures, then decides whether to loop.
  Future<void> _startNextCapture() async {
    final provider = context.read<PhotoboothProvider>();
    if (!mounted || provider.sessionComplete) return;
    if (_isCapturing) return;
    _isCapturing = true;

    // Countdown: 3 → 2 → 1
    for (int i = 3; i > 0; i--) {
      if (!mounted) return;
      setState(() => _countdown = i);
      _countdownAnim.forward(from: 0);
      await Future.delayed(const Duration(milliseconds: 950));
    }

    if (!mounted) return;
    setState(() {
      _countdown = 0;
      _showFlash = true;
    });

    // Capture the frame
    final bytes = await _captureFrame();
    if (!mounted) return;

    // Flash off
    await Future.delayed(const Duration(milliseconds: 200));
    setState(() => _showFlash = false);

    if (bytes != null) {
      // Show the just-captured photo briefly
      setState(() {
        _lastCapture = bytes;
        _showLastCapture = true;
      });

      provider.addPhoto(bytes);

      // Show thumbnail for 1.2s
      await Future.delayed(const Duration(milliseconds: 1200));
      if (!mounted) return;
      setState(() => _showLastCapture = false);

      // Check if we need more photos
      _isCapturing = false;
      if (!provider.sessionComplete) {
        await Future.delayed(const Duration(milliseconds: 300));
        _startNextCapture();
      }
    } else {
      _isCapturing = false;
    }
  }

  Future<Uint8List?> _captureFrame() async {
    try {
      final canvas =
          web.document.createElement('canvas') as web.HTMLCanvasElement;
      canvas.width = _videoElement.videoWidth;
      canvas.height = _videoElement.videoHeight;
      final ctx = canvas.context2D;

      // Mirror the frame (undo the CSS mirror so the saved image is correct)
      ctx.translate(canvas.width.toDouble(), 0);
      ctx.scale(-1, 1);
      ctx.drawImage(_videoElement, 0, 0);

      final completer = Completer<web.Blob>();
      canvas.toBlob(
          (web.Blob blob) { completer.complete(blob); }.toJS,
          'image/jpeg',
          0.92.jsify());
      final blob = await completer.future;

      final reader = web.FileReader();
      reader.readAsArrayBuffer(blob);
      await reader.onLoadEnd.first;

      final result = reader.result;
      if (result != null && result.isA<JSArrayBuffer>()) {
        return (result as JSArrayBuffer).toDart.asUint8List();
      }
    } catch (e) {
      debugPrint('Capture error: $e');
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PhotoboothProvider>();

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Live camera feed ──────────────────────────────────────────────
          HtmlElementView(key: ValueKey(_viewID), viewType: _viewID),

          // ── Loading overlay while camera initialises ──────────────────────
          if (!_cameraReady)
            Container(
              color: Colors.black.withValues(alpha: 0.85),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(
                        color: Color(0xFFE8C8A0), strokeWidth: 1.5),
                    const SizedBox(height: 20),
                    Text(
                      'STARTING CAMERA',
                      style: GoogleFonts.lato(
                          fontSize: 10, letterSpacing: 4, color: Colors.white54),
                    ),
                  ],
                ),
              ),
            ),

          // ── Top status bar ────────────────────────────────────────────────
          if (_cameraReady)
            Positioned(
              top: 0, left: 0, right: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(40, 32, 40, 24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.7),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Image.asset(
                      'assets/logo.png',
                      height: 36,
                      fit: BoxFit.contain,
                    ),
                    // Photo counter
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 8),
                      decoration: BoxDecoration(
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.3)),
                        borderRadius: BorderRadius.circular(3),
                        color: Colors.black.withValues(alpha: 0.3),
                      ),
                      child: Text(
                        'PHOTO  ${provider.capturedCount + (_isCapturing ? 1 : 0)}  /  ${provider.totalRequired}',
                        style: GoogleFonts.lato(
                          fontSize: 11,
                          letterSpacing: 3,
                          color: Colors.white,
                          fontWeight: FontWeight.w300,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ── Countdown overlay ─────────────────────────────────────────────
          if (_countdown > 0)
            AnimatedBuilder(
              animation: _countdownAnim,
              builder: (_, __) => Opacity(
                opacity: _countdownOpacity.value,
                child: Transform.scale(
                  scale: _countdownScale.value,
                  child: Center(
                    child: Text(
                      '$_countdown',
                      style: GoogleFonts.cormorantGaramond(
                        fontSize: 280,
                        fontWeight: FontWeight.w300,
                        fontStyle: FontStyle.italic,
                        color: Colors.white,
                        shadows: [
                          Shadow(
                            blurRadius: 60,
                            color: Colors.black.withValues(alpha: 0.9),
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // ── Flash overlay ─────────────────────────────────────────────────
          if (_showFlash)
            AnimatedOpacity(
              opacity: _showFlash ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 80),
              child: Container(color: Colors.white),
            ),

          // ── Last-captured thumbnail ───────────────────────────────────────
          if (_showLastCapture && _lastCapture != null)
            Positioned(
              bottom: 32, right: 32,
              child: AnimatedOpacity(
                opacity: _showLastCapture ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: Container(
                  width: 120,
                  height: 90,
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: const Color(0xFFE8C8A0), width: 2),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.5),
                          blurRadius: 16),
                    ],
                  ),
                  child: Image.memory(_lastCapture!, fit: BoxFit.cover),
                ),
              ),
            ),

          // ── Progress dots at the bottom ───────────────────────────────────
          if (_cameraReady)
            Positioned(
              bottom: 32, left: 0, right: 0,
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(provider.totalRequired, (i) {
                    final done = i < provider.capturedCount;
                    final current = i == provider.capturedCount && _isCapturing;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: current ? 24 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: done
                            ? const Color(0xFFE8C8A0)
                            : current
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    );
                  }),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
