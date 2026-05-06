import 'dart:async'; // FIX: Defines Completer
import 'dart:js_interop'; // For .toJS and .isA
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

class CameraView extends StatefulWidget {
  final Function(Uint8List) onCapture;

  const CameraView({super.key, required this.onCapture});

  @override
  CameraViewState createState() => CameraViewState();
}

class CameraViewState extends State<CameraView> {
  late web.HTMLVideoElement _videoElement;
  final String _viewID = 'camera-view';

  @override
  void initState() {
    super.initState();
    // Initialize the video element according to SnapBooth specs
    _videoElement = web.document.createElement('video') as web.HTMLVideoElement
      ..autoplay = true
      ..style.transform = 'scaleX(-1)' // Mirror for selfie[cite: 1]
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

  Future<void> takePhoto() async {
    final canvas =
        web.document.createElement('canvas') as web.HTMLCanvasElement;
    canvas.width = _videoElement.videoWidth;
    canvas.height = _videoElement.videoHeight;

    final ctx = canvas.context2D;
    ctx.translate(canvas.width.toDouble(), 0);
    ctx.scale(-1, 1);
    ctx.drawImage(_videoElement, 0, 0);

    // Using Completer to handle the non-Future toBlob callback[cite: 1]
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
      // Convert JSArrayBuffer to Uint8List for Flutter[cite: 1]
      final uint8list = jsBuffer.toDart.asUint8List();
      widget.onCapture(uint8list);
    }
  }

  // FIX: Added the missing build method[cite: 1]
  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewID);
  }
}
