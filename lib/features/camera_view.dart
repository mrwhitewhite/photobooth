import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/photo_models.dart';
import '../services/photobooth_provider.dart';

class CameraView extends StatefulWidget {
  const CameraView({super.key});

  @override
  CameraViewState createState() => CameraViewState();
}

class CameraViewState extends State<CameraView>
    with SingleTickerProviderStateMixin {
  CameraController? _controller;

  int _countdown = 0;
  bool _showFlash = false;
  bool _isCapturing = false;
  bool _cameraReady = false;
  String? _cameraError;

  Size? _templateImageSize;

  late AnimationController _countdownAnim;
  late Animation<double> _countdownScale;
  late Animation<double> _countdownOpacity;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    _countdownAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _countdownScale = Tween<double>(begin: 1.6, end: 0.85).animate(
        CurvedAnimation(parent: _countdownAnim, curve: Curves.easeOut));
    _countdownOpacity = Tween<double>(begin: 1.0, end: 0.0)
        .animate(CurvedAnimation(parent: _countdownAnim, curve: Curves.easeIn));

    _initCamera();

    WidgetsBinding.instance.addPostFrameCallback((_) => _loadTemplateSize());
  }

  @override
  void dispose() {
    _countdownAnim.dispose();
    _controller?.dispose();
    super.dispose();
  }

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

  Future<void> _initCamera() async {
    try {
      final permission = await Permission.camera.request();
      if (!permission.isGranted) {
        if (mounted) {
          setState(() {
            _cameraError = 'Camera permission is required to continue.';
            _cameraReady = false;
          });
        }
        return;
      }

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) {
          setState(() {
            _cameraError = 'No camera found on this device.';
            _cameraReady = false;
          });
        }
        return;
      }

      final selected = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        selected,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      _controller = controller;
      await controller.initialize();

      if (!mounted) return;
      setState(() {
        _cameraReady = true;
        _cameraError = null;
      });
      Future.delayed(const Duration(seconds: 2), _startNextCapture);
    } catch (e) {
      if (mounted) {
        setState(() {
          _cameraError = 'Camera error: $e';
          _cameraReady = false;
        });
      }
    }
  }

  Future<void> _startNextCapture() async {
    final provider = context.read<PhotoboothProvider>();
    if (!mounted || provider.sessionComplete) return;
    if (_isCapturing) return;
    _isCapturing = true;

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
        await Future.delayed(const Duration(milliseconds: 600));
        _startNextCapture();
      }
    } else {
      _isCapturing = false;
    }
  }

  Future<Uint8List?> _captureFrame() async {
    try {
      final controller = _controller;
      if (controller == null || !controller.value.isInitialized) return null;
      if (controller.value.isTakingPicture) return null;

      final file = await controller.takePicture();
      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return bytes;

      final normalized = _downscaleImage(decoded);
      final flipped = img.flipHorizontal(normalized);
      final encoded = img.encodeJpg(flipped, quality: 92);
      return Uint8List.fromList(encoded);
    } catch (e) {
      debugPrint('Capture error: $e');
    }
    return null;
  }

  img.Image _downscaleImage(img.Image source) {
    const maxDimension = 2048;
    final maxSide = math.max(source.width, source.height);
    if (maxSide <= maxDimension) return source;
    final scale = maxDimension / maxSide;
    return img.copyResize(
      source,
      width: (source.width * scale).round(),
      height: (source.height * scale).round(),
      interpolation: img.Interpolation.cubic,
    );
  }

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
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.2,
                colors: [Color(0xFF181818), Color(0xFF040404)],
              ),
            ),
          ),
          if (!_cameraReady)
            Container(
              color: Colors.black.withValues(alpha: 0.85),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_cameraError == null) ...[
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
                    ] else ...[
                      const Icon(Icons.error_outline,
                          color: Color(0xFFE8C8A0), size: 40),
                      const SizedBox(height: 16),
                      Text(
                        _cameraError!,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.lato(
                          fontSize: 12,
                          letterSpacing: 1,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          if (_cameraReady)
            _TemplateSlotView(
              layout: layout,
              slots: slots,
              templateImageSize: _templateImageSize,
              cameraPreview: _buildCameraPreview(),
              provider: provider,
              countdown: _countdown,
              countdownAnim: _countdownAnim,
              countdownScale: _countdownScale,
              countdownOpacity: _countdownOpacity,
            ),
          if (_cameraReady) _buildTopBar(provider),
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

  Widget _buildCameraPreview() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox.shrink();
    }
    final size = controller.value.previewSize;
    if (size == null) return const SizedBox.shrink();

    final double previewW = size.height;
    final double previewH = size.width;

    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: previewW,
          height: previewH,
          child: CameraPreview(controller),
        ),
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
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
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

class _TemplateSlotView extends StatelessWidget {
  final PhotoLayout layout;
  final List<LayoutSlot> slots;
  final Size? templateImageSize;
  final Widget cameraPreview;
  final PhotoboothProvider provider;
  final int countdown;
  final AnimationController countdownAnim;
  final Animation<double> countdownScale;
  final Animation<double> countdownOpacity;

  const _TemplateSlotView({
    required this.layout,
    required this.slots,
    required this.templateImageSize,
    required this.cameraPreview,
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

      double tw, th;
      if (templateImageSize != null) {
        final ar = templateImageSize!.width / templateImageSize!.height;

        th = screenH * 0.85;
        tw = th * ar;
        if (tw > screenW * 0.60) {
          tw = screenW * 0.60;
          th = tw / ar;
        }
      } else {
        th = screenH * 0.85;
        tw = th * (2 / 3);
      }

      final offsetX = (screenW - tw) / 2;
      final offsetY = (screenH - th) / 2;

      final activeIndex = provider.capturedCount;
      final hasActiveSlot =
          !provider.sessionComplete && activeIndex < slots.length;

      final double camLeft =
          hasActiveSlot ? offsetX + slots[activeIndex].x * tw : 0;
      final double camTop =
          hasActiveSlot ? offsetY + slots[activeIndex].y * th : 0;
      final double camW = hasActiveSlot ? slots[activeIndex].w * tw : 0;
      final double camH = hasActiveSlot ? slots[activeIndex].h * th : 0;

      return Stack(
        children: [
          Positioned(
            left: offsetX,
            top: offsetY,
            width: tw,
            height: th,
            child: Image.asset(layout.templateAsset, fit: BoxFit.fill),
          ),
          for (int i = 0; i < slots.length; i++)
            _buildSlotWidget(i, slots[i], tw, th, offsetX, offsetY),
          if (hasActiveSlot)
            Positioned(
              left: camLeft,
              top: camTop,
              width: camW,
              height: camH,
              child: cameraPreview,
            ),
          if (hasActiveSlot)
            Positioned(
              left: camLeft,
              top: camTop,
              width: camW,
              height: camH,
              child: const _ActiveBorder(),
            ),
          if (countdown > 0 && hasActiveSlot)
            _buildCountdownOverlay(
                slots[activeIndex], tw, th, offsetX, offsetY),
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

    if (isActive) return const SizedBox.shrink();

    Widget content;

    if (isCaptured) {
      content = Image.memory(
        provider.photos[index],
        fit: BoxFit.cover,
        width: width,
        height: height,
      );
    } else {
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
          final current =
              i == provider.capturedCount && !provider.sessionComplete;
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
