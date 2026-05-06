import 'package:flutter/material.dart';
import 'dart:typed_data';

enum AppState { layoutSelect, camera, review, complete }

class PhotoboothProvider extends ChangeNotifier {
  AppState _state = AppState.layoutSelect;
  Uint8List? _lastPhoto;

  AppState get state => _state;
  Uint8List? get lastPhoto => _lastPhoto;

  // Ensure this name matches exactly what main.dart calls
  void startSession() {
    _state = AppState.camera;
    notifyListeners();
  }

  void addPhoto(Uint8List bytes) {
    _lastPhoto = bytes;
    _state = AppState.review;
    notifyListeners();
  }

  void reset() {
    _state = AppState.layoutSelect;
    _lastPhoto = null;
    notifyListeners();
  }
}
