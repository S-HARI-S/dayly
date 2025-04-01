// lib/models/video_element.dart
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'dart:ui' as ui;
import 'element.dart';
import 'dart:async';

class VideoElement extends DrawingElement {
  final String videoUrl;
  final VideoPlayerController controller;
  final Size size;
  final ValueNotifier<bool> _showPlayIconNotifier;

  VideoElement({
    String? id,
    required Offset position,
    bool isSelected = false,
    required this.videoUrl,
    required this.controller,
    required this.size,
  }) : _showPlayIconNotifier = ValueNotifier(!controller.value.isPlaying),
       super(id: id, type: ElementType.video, position: position, isSelected: isSelected) {
    // Just add the listener directly - no assignment needed
    controller.addListener(_onVideoStateChanged);
    _onVideoStateChanged(); // Update initial state
  }

  void _onVideoStateChanged() {
    final shouldShowPlay = !controller.value.isPlaying;
    if (_showPlayIconNotifier.value != shouldShowPlay) {
      _showPlayIconNotifier.value = shouldShowPlay;
    }
  }

  void togglePlayPause() { 
    if(controller.value.isPlaying) {
      controller.pause();
    } else {
      if(controller.value.isInitialized) {
        controller.play(); 
        controller.setLooping(true);
      } else {
        print("Video not initialized");
      }
    } 
  }

  void dispose() {
     print("Disposing VideoElement ${id}");
     controller.removeListener(_onVideoStateChanged);
     controller.dispose();
     _showPlayIconNotifier.dispose();
  }

  @override
  Rect get bounds => Rect.fromLTWH(position.dx, position.dy, size.width, size.height);

  @override
  bool containsPoint(Offset point) => bounds.contains(point);

  @override
  void render(Canvas canvas, {double inverseScale = 1.0}) { 
    final dst = bounds;
    final ph = Paint()..color = Colors.black87;
    canvas.drawRect(dst, ph);
    
    final iconC = Colors.white.withOpacity(0.9);
    final iconP = Paint()..color = iconC;
    final iconS = (size.shortestSide * 0.3).clamp(15.0, 60.0);
    final iconR = Rect.fromCenter(center: dst.center, width: iconS, height: iconS);
    
    if(_showPlayIconNotifier.value) {
      // Draw play triangle
      final p = Path()
        ..moveTo(iconR.left, iconR.top)
        ..lineTo(iconR.right, iconR.center.dy)
        ..lineTo(iconR.left, iconR.bottom)
        ..close();
      canvas.drawPath(p, iconP);
    } else {
      // Draw pause bars
      final bw = iconS * 0.25;
      final g = iconS * 0.1;
      final lb = Rect.fromLTWH(iconR.center.dx - bw - g/2, iconR.top, bw, iconR.height);
      final rb = Rect.fromLTWH(iconR.center.dx + g/2, iconR.top, bw, iconR.height);
      canvas.drawRect(lb, iconP);
      canvas.drawRect(rb, iconP);
    }
  }

  @override
  VideoElement copyWith({
    String? id,
    Offset? position,
    bool? isSelected,
    Size? size,
    String? videoUrl,
    VideoPlayerController? controller,
  }) {
    assert(videoUrl == null && controller == null, "Cannot change video source or controller via copyWith.");
    return VideoElement(
      id: id ?? this.id,
      position: position ?? this.position,
      isSelected: isSelected ?? this.isSelected,
      videoUrl: this.videoUrl,
      controller: this.controller,
      size: size ?? this.size,
    );
  }

  @override
  VideoElement clone() {
    print("Warning: Cloning VideoElement shares controller");
    return VideoElement(
      id: id,
      position: position,
      isSelected: false,
      videoUrl: videoUrl,
      controller: controller,
      size: size,
    );
  }
}