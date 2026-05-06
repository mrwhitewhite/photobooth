import 'package:flutter/material.dart';
import 'dart:typed_data';
import '../models/photo_models.dart'; //

enum AppState { layoutSelect, camera, review, complete } //

class PhotoboothProvider extends ChangeNotifier {
  AppState _state = AppState.layoutSelect;
  PhotoLayout _selectedLayout = PhotoLayout.single;
  final List<Uint8List> _photos = [];

  // This is the missing piece causing your 'completedStrip' error[cite: 1]
  Uint8List? _completedStrip;

  AppState get state => _state;
  PhotoLayout get selectedLayout => _selectedLayout;
  List<Uint8List> get photos => _photos;

  // Getter for main.dart to access the final image[cite: 1]
  Uint8List? get completedStrip => _completedStrip;

  void startSession(PhotoLayout layout) {
    _selectedLayout = layout;
    _photos.clear();
    _completedStrip = null; //[cite: 1]
    _state = AppState.camera;
    notifyListeners();
  }

  void addPhoto(Uint8List bytes) {
    _photos.add(bytes);
    if (_photos.length >= _selectedLayout.photoCount) {
      _state = AppState.review;
    }
    notifyListeners();
  }

  // This is the missing method causing your 'completeSession' error[cite: 1]
  void completeSession(Uint8List stripBytes) {
    _completedStrip = stripBytes;
    _state = AppState.complete;
    notifyListeners();
  }

  void reset() {
    _state = AppState.layoutSelect;
    _photos.clear();
    _completedStrip = null; //[cite: 1]
    notifyListeners();
  }
}
