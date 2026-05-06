import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:snapbooth/models/photo_models.dart';

enum AppState { layoutSelect, camera, review, complete }

class PhotoboothProvider extends ChangeNotifier {
  AppState _state = AppState.layoutSelect;
  PhotoLayout _selectedLayout = PhotoLayout.single;
  final List<Uint8List> _photos = [];

  AppState get state => _state;
  PhotoLayout get selectedLayout => _selectedLayout;
  List<Uint8List> get photos => _photos;

  void startSession(PhotoLayout layout) {
    _selectedLayout = layout;
    _photos.clear();
    _state = AppState.camera;
    notifyListeners();
  }

  void addPhoto(Uint8List bytes) {
    _photos.add(bytes);
    // Auto-transition to review when all shots are taken
    if (_photos.length >= _selectedLayout.photoCount) {
      _state = AppState.review;
    }
    notifyListeners();
  }

  void reset() {
    _state = AppState.layoutSelect;
    _photos.clear();
    notifyListeners();
  }
}
