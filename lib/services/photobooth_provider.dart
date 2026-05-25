import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/photo_models.dart';

enum AppState {
  screensaver,
  homepage,
  layoutSelect,
  camera,
  preview,
}

class PhotoboothProvider extends ChangeNotifier {
  AppState _state = AppState.screensaver;
  PhotoLayout _selectedLayout = PhotoLayout.layout1x1;
  final List<Uint8List> _photos = [];
  Uint8List? _completedComposite;

  AppState get state => _state;
  PhotoLayout get selectedLayout => _selectedLayout;
  List<Uint8List> get photos => List.unmodifiable(_photos);
  Uint8List? get completedComposite => _completedComposite;

  int get capturedCount => _photos.length;
  int get totalRequired => _selectedLayout.photoCount;
  bool get sessionComplete => _photos.length >= _selectedLayout.photoCount;

  void goToHomepage() {
    _state = AppState.homepage;
    notifyListeners();
  }

  void goToLayoutSelect() {
    _state = AppState.layoutSelect;
    notifyListeners();
  }

  void startSession(PhotoLayout layout) {
    _selectedLayout = layout;
    _photos.clear();
    _completedComposite = null;
    _state = AppState.camera;
    notifyListeners();
  }

  void addPhoto(Uint8List bytes) {
    _photos.add(bytes);
    notifyListeners();
    if (_photos.length >= _selectedLayout.photoCount) {
      Future.delayed(const Duration(milliseconds: 400), () {
        _state = AppState.preview;
        notifyListeners();
      });
    }
  }

  void setComposite(Uint8List bytes) {
    _completedComposite = bytes;
    notifyListeners();
  }

  void reset() {
    _photos.clear();
    _completedComposite = null;
    _state = AppState.screensaver;
    notifyListeners();
  }

  List<Uint8List> get allPhotos => _photos;
}
