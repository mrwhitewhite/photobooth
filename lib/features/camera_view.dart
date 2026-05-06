import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;
import 'package:google_fonts/google_fonts.dart';

class CameraView extends StatefulWidget {
  final Function(Uint8List) onCapture;

  const CameraView({super.key, required this.onCapture});

  @override
  CameraViewState createState() => CameraViewState();
}

class CameraViewState extends State<CameraView> {
  late web.HTMLVideoElement _videoElement;
  final String _viewID = 'camera-view';

  int _countdown = 0;
  bool _showFlash = false;

  @override
  void initState() {
    super.initState();
    _videoElement = web.document.createElement('video') as web.HTMLVideoElement
      ..autoplay = true
      ..style.transform = 'scaleX(-1)'
      ..style.objectFit = 'cover'
      ..style.width = '100%'
      ..style.height = '100%';

    ui_web.platformViewRegistry
        .registerViewFactory(_viewID, (int viewId) => _videoElement);
    _initCamera();
  }

  Future<void> _initCamera() async {
    final constraints =
        {'video': true, 'audio': false}.jsify() as web.MediaStreamConstraints;
    try {
      final stream = await web.window.navigator.mediaDevices
          .getUserMedia(constraints)
          .toDart;
      _videoElement.srcObject = stream;
    } catch (e) {
      debugPrint("Camera Error: $e");
    }
  }

  /// Public method to trigger the photobooth sequence
  Future<void> startCountdown() async {
    if (_countdown > 0) return;

    for (int i = 3; i > 0; i--) {
      setState(() => _countdown = i);
      await Future.delayed(const Duration(seconds: 1));
    }

    setState(() {
      _countdown = 0;
      _showFlash = true;
    });

    // Brief delay to show the white flash overlay
    await _capturePhoto();

    await Future.delayed(const Duration(milliseconds: 200));
    setState(() => _showFlash = false);
  }

  Future<void> _capturePhoto() async {
    final canvas =
        web.document.createElement('canvas') as web.HTMLCanvasElement;
    canvas.width = _videoElement.videoWidth;
    canvas.height = _videoElement.videoHeight;

    final ctx = canvas.context2D;
    ctx.translate(canvas.width.toDouble(), 0);
    ctx.scale(-1, 1);
    ctx.drawImage(_videoElement, 0, 0);

    final completer = Completer<web.Blob>();
    canvas.toBlob(
        (web.Blob blob) {
          completer.complete(blob);
        }.toJS,
        'image/jpeg',
        0.9.jsify());

    final blob = await completer.future;
    final reader = web.FileReader();
    reader.readAsArrayBuffer(blob);

    await reader.onLoadEnd.first;

    final result = reader.result;
    if (result != null && result.isA<JSArrayBuffer>()) {
      final jsBuffer = result as JSArrayBuffer;
      final uint8list = jsBuffer.toDart.asUint8List();
      widget.onCapture(uint8list);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // The Live Camera Feed[cite: 1]
        HtmlElementView(viewType: _viewID),

        // Countdown Overlay[cite: 1]
        if (_countdown > 0)
          Center(
            child: Text(
              '$_countdown',
              style: GoogleFonts.playfairDisplay(
                fontSize: 200,
                color: const Color(0xFFE8C4A0),
                fontWeight: FontWeight.bold,
                shadows: [
                  const Shadow(blurRadius: 20, color: Colors.black),
                ],
              ),
            ),
          ),

        // Flash Effect Overlay[cite: 1]
        if (_showFlash)
          Positioned.fill(
            child: Container(color: Colors.white),
          ),
      ],
    );
  }
}
