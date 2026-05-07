import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/photo_models.dart';

// ── App states ────────────────────────────────────────────────────────────────
enum AppState {
  screensaver,  // Idle — plays looping video
  homepage,     // Full-bleed homepage.png + "Start" button
  layoutSelect, // Pick a layout
  camera,       // Live feed → auto countdown → capture (×N)
  preview,      // Show composite result → Print / Download / Reset
}

// ── Provider ──────────────────────────────────────────────────────────────────
class PhotoboothProvider extends ChangeNotifier {
  AppState _state = AppState.screensaver;
  PhotoLayout _selectedLayout = PhotoLayout.layout1x1;
  final List<Uint8List> _photos = [];
  Uint8List? _completedComposite;

  // ── Getters ──────────────────────────────────────────────────────────────
  AppState get state => _state;
  PhotoLayout get selectedLayout => _selectedLayout;
  List<Uint8List> get photos => List.unmodifiable(_photos);
  Uint8List? get completedComposite => _completedComposite;

  // ── Convenience ──────────────────────────────────────────────────────────
  int get capturedCount => _photos.length;
  int get totalRequired => _selectedLayout.photoCount;
  bool get sessionComplete => _photos.length >= _selectedLayout.photoCount;

  // ── Transitions ──────────────────────────────────────────────────────────

  /// Screensaver → Homepage (after "Tap to Start")
  void goToHomepage() {
    _state = AppState.homepage;
    notifyListeners();
  }

  /// Homepage → Layout select
  void goToLayoutSelect() {
    _state = AppState.layoutSelect;
    notifyListeners();
  }

  /// Layout select → Camera (starts a new session)
  void startSession(PhotoLayout layout) {
    _selectedLayout = layout;
    _photos.clear();
    _completedComposite = null;
    _state = AppState.camera;
    notifyListeners();
  }

  /// Camera: add a captured photo. Auto-advances to preview when complete.
  void addPhoto(Uint8List bytes) {
    _photos.add(bytes);
    notifyListeners(); // update count immediately
    if (_photos.length >= _selectedLayout.photoCount) {
      // Slight delay so the last flash effect finishes in the UI
      Future.delayed(const Duration(milliseconds: 400), () {
        _state = AppState.preview;
        notifyListeners();
      });
    }
  }

  /// Preview: store the final composite image
  void setComposite(Uint8List bytes) {
    _completedComposite = bytes;
    notifyListeners();
  }

  /// Reset → back to screensaver
  void reset() {
    _photos.clear();
    _completedComposite = null;
    _state = AppState.screensaver;
    notifyListeners();
  }

  // Legacy compat
  List<Uint8List> get allPhotos => _photos;
}
