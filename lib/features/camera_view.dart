import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:web/web.dart' as web;
import '../models/photo_models.dart';
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

  // Template image intrinsic size (loaded async)
  Size? _templateImageSize;

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

    _videoElement =
        web.document.createElement('video') as web.HTMLVideoElement
          ..autoplay = true
          ..muted = true
          ..playsInline = true
          ..style.transform = 'scaleX(-1)' // mirror
          ..style.objectFit = 'cover'
          ..style.width = '100%'
          ..style.height = '100%';

    ui_web.platformViewRegistry
        .registerViewFactory(_viewID, (int _) => _videoElement);

    _initCamera();

    // Load template image dimensions after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadTemplateSize());
  }

  @override
  void dispose() {
    _countdownAnim.dispose();
    _stopCamera();
    super.dispose();
  }

  // ── Template image size ─────────────────────────────────────────────────────

  void _loadTemplateSize() {
    if (!mounted) return;
    final layout = context.read<PhotoboothProvider>().selectedLayout;
    final imageProvider = AssetImage(layout.templateAsset);
    imageProvider
        .resolve(ImageConfiguration(bundle: DefaultAssetBundle.of(context)))
        .addListener(ImageStreamListener((info, _) {
      if (mounted) {
        setState(() {
          _templateImageSize = Size(
            info.image.width.toDouble(),
            info.image.height.toDouble(),
          );
        });
      }
    }));
  }

  // ── Camera ──────────────────────────────────────────────────────────────────

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
        Future.delayed(const Duration(seconds: 2), _startNextCapture);
      }
    } catch (e) {
      debugPrint('Camera Error: $e');
    }
  }

  Future<void> _startNextCapture() async {
    final provider = context.read<PhotoboothProvider>();
    if (!mounted || provider.sessionComplete) return;
    if (_isCapturing) return;
    _isCapturing = true;

    // Countdown 3 → 2 → 1
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

    final bytes = await _captureFrame();
    if (!mounted) return;

    await Future.delayed(const Duration(milliseconds: 200));
    setState(() => _showFlash = false);

    if (bytes != null) {
      provider.addPhoto(bytes);
      _isCapturing = false;
      if (!provider.sessionComplete) {
        // Brief pause before next slot countdown
        await Future.delayed(const Duration(milliseconds: 600));
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
      // Un-mirror for correct saved image
      ctx.translate(canvas.width.toDouble(), 0);
      ctx.scale(-1, 1);
      ctx.drawImage(_videoElement, 0, 0);

      final completer = Completer<web.Blob>();
      canvas.toBlob(
          (web.Blob blob) {
            completer.complete(blob);
          }.toJS,
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

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PhotoboothProvider>();
    final layout = provider.selectedLayout;
    final slots = layout.slots;

    return Scaffold(
      backgroundColor: const Color(0xFF080808),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Radial dark background ─────────────────────────────────────────
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.2,
                colors: [Color(0xFF181818), Color(0xFF040404)],
              ),
            ),
          ),

          // ── Loading overlay ────────────────────────────────────────────────
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
                        fontSize: 10,
                        letterSpacing: 4,
                        color: Colors.white54,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ── Template + slot camera view ────────────────────────────────────
          if (_cameraReady)
            _TemplateSlotView(
              layout: layout,
              slots: slots,
              templateImageSize: _templateImageSize,
              viewID: _viewID,
              provider: provider,
              countdown: _countdown,
              countdownAnim: _countdownAnim,
              countdownScale: _countdownScale,
              countdownOpacity: _countdownOpacity,
            ),

          // ── Top bar (logo + counter) ───────────────────────────────────────
          if (_cameraReady) _buildTopBar(provider),

          // ── Full-screen flash ──────────────────────────────────────────────
          if (_showFlash)
            AnimatedOpacity(
              opacity: _showFlash ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 80),
              child: Container(color: Colors.white),
            ),
        ],
      ),
    );
  }

  Widget _buildTopBar(PhotoboothProvider provider) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(40, 28, 40, 20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.65),
              Colors.transparent,
            ],
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Image.asset('assets/logo.png', height: 36, fit: BoxFit.contain),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              decoration: BoxDecoration(
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(3),
                color: Colors.black.withValues(alpha: 0.3),
              ),
              child: Text(
                'PHOTO  ${provider.capturedCount}  /  ${provider.totalRequired}',
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
    );
  }
}

// ── Template + Slot overlay widget ────────────────────────────────────────────

class _TemplateSlotView extends StatelessWidget {
  final PhotoLayout layout;
  final List<LayoutSlot> slots;
  final Size? templateImageSize;
  final String viewID;
  final PhotoboothProvider provider;
  final int countdown;
  final AnimationController countdownAnim;
  final Animation<double> countdownScale;
  final Animation<double> countdownOpacity;

  const _TemplateSlotView({
    required this.layout,
    required this.slots,
    required this.templateImageSize,
    required this.viewID,
    required this.provider,
    required this.countdown,
    required this.countdownAnim,
    required this.countdownScale,
    required this.countdownOpacity,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final screenW = constraints.maxWidth;
      final screenH = constraints.maxHeight;

      // ── Calculate template display rect ───────────────────────────────────
      double tw, th;
      if (templateImageSize != null) {
        final ar = templateImageSize!.width / templateImageSize!.height;
        // Fill up to 85% of screen height; cap width at 60% of screen width
        th = screenH * 0.85;
        tw = th * ar;
        if (tw > screenW * 0.60) {
          tw = screenW * 0.60;
          th = tw / ar;
        }
      } else {
        // Fallback while image loads: assume portrait 2:3
        th = screenH * 0.85;
        tw = th * (2 / 3);
      }

      // Center the template on screen
      final offsetX = (screenW - tw) / 2;
      final offsetY = (screenH - th) / 2;

      return Stack(
        children: [
          // ── Template PNG ─────────────────────────────────────────────────
          Positioned(
            left: offsetX,
            top: offsetY,
            width: tw,
            height: th,
            child: Image.asset(layout.templateAsset, fit: BoxFit.fill),
          ),

          // ── Slot widgets ─────────────────────────────────────────────────
          for (int i = 0; i < slots.length; i++)
            _buildSlotWidget(i, slots[i], tw, th, offsetX, offsetY),

          // ── Countdown on active slot ──────────────────────────────────────
          if (countdown > 0 && provider.capturedCount < slots.length)
            _buildCountdownOverlay(
                slots[provider.capturedCount], tw, th, offsetX, offsetY),

          // ── Bottom hint label ─────────────────────────────────────────────
          Positioned(
            bottom: 24,
            left: 0,
            right: 0,
            child: _buildProgressDots(),
          ),
        ],
      );
    });
  }

  Widget _buildSlotWidget(
    int index,
    LayoutSlot slot,
    double tw,
    double th,
    double offsetX,
    double offsetY,
  ) {
    final left = offsetX + slot.x * tw;
    final top = offsetY + slot.y * th;
    final width = slot.w * tw;
    final height = slot.h * th;

    final isCaptured = index < provider.capturedCount;
    final isActive =
        index == provider.capturedCount && !provider.sessionComplete;

    Widget content;

    if (isCaptured) {
      // ── Captured photo fills the slot ───────────────────────────────────
      content = Image.memory(
        provider.photos[index],
        fit: BoxFit.cover,
        width: width,
        height: height,
      );
    } else if (isActive) {
      // ── Live camera feed in the active slot ──────────────────────────────
      content = Stack(
        fit: StackFit.expand,
        children: [
          // Camera feed
          HtmlElementView(viewType: viewID),
          // Gold animated border to highlight active slot
          const Positioned.fill(
            child: _ActiveBorder(),
          ),
        ],
      );
    } else {
      // ── Empty future slot ────────────────────────────────────────────────
      content = Container(
        width: width,
        height: height,
        color: Colors.black.withValues(alpha: 0.60),
        child: Center(
          child: Icon(
            Icons.camera_alt_outlined,
            color: Colors.white.withValues(alpha: 0.18),
            size: (width * 0.22).clamp(10.0, 34.0),
          ),
        ),
      );
    }

    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: ClipRect(child: content),
    );
  }

  Widget _buildCountdownOverlay(
    LayoutSlot slot,
    double tw,
    double th,
    double offsetX,
    double offsetY,
  ) {
    final slotLeft = offsetX + slot.x * tw;
    final slotTop = offsetY + slot.y * th;
    final slotW = slot.w * tw;
    final slotH = slot.h * th;
    final centerX = slotLeft + slotW / 2;
    final centerY = slotTop + slotH / 2;

    // Circle size: 60% of the smaller slot dimension, capped
    final circleSize = (slotW.clamp(60.0, 300.0) * 0.65).clamp(60.0, 180.0);
    final fontSize = (circleSize * 0.5).clamp(24.0, 90.0);

    return Positioned(
      left: centerX - circleSize / 2,
      top: centerY - circleSize / 2,
      width: circleSize,
      height: circleSize,
      child: AnimatedBuilder(
        animation: countdownAnim,
        builder: (_, __) => Opacity(
          opacity: countdownOpacity.value,
          child: Transform.scale(
            scale: countdownScale.value,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withValues(alpha: 0.55),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.3),
                  width: 1.5,
                ),
              ),
              child: Center(
                child: Text(
                  '$countdown',
                  style: GoogleFonts.lato(
                    fontSize: fontSize,
                    fontWeight: FontWeight.w300,
                    color: Colors.white,
                    height: 1.0,
                    shadows: [
                      Shadow(
                        blurRadius: 20,
                        color: Colors.black.withValues(alpha: 0.9),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProgressDots() {
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(provider.totalRequired, (i) {
          final done = i < provider.capturedCount;
          final current = i == provider.capturedCount && !provider.sessionComplete;
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
    );
  }
}

// ── Pulsing gold border for the active slot ────────────────────────────────────

class _ActiveBorder extends StatefulWidget {
  const _ActiveBorder();
  @override
  State<_ActiveBorder> createState() => _ActiveBorderState();
}

class _ActiveBorderState extends State<_ActiveBorder>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.5, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, __) => DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(
            color: const Color(0xFFE8C8A0).withValues(alpha: _pulse.value),
            width: 2.5,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFE8C8A0)
                  .withValues(alpha: _pulse.value * 0.35),
              blurRadius: 12,
              spreadRadius: 2,
            ),
          ],
        ),
      ),
    );
  }
}
