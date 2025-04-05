// lib/models/video_element.dart
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'dart:ui' as ui;
import 'element.dart';
import 'dart:async';
import 'dart:typed_data';
import 'dart:math' as math;

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
    
    // Draw black background
    final ph = Paint()..color = Colors.black87;
    canvas.drawRect(dst, ph);
    
    // Note: The actual video frames are rendered by VideoPlayer widget
    // Here we only render a placeholder and controls
    
    // If video isn't initialized, show a loading indicator
    if (!controller.value.isInitialized) {
      final loadingPaint = Paint()
        ..color = Colors.white.withOpacity(0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0 * inverseScale;
      // Draw a circular loading indicator
      final center = dst.center;
      final radius = math.min(dst.width, dst.height) * 0.2;
      canvas.drawCircle(center, radius, loadingPaint);
      canvas.drawCircle(center, radius, loadingPaint);
    }

    // Draw play/pause icon overlay
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
  
  // --- Serialization Methods ---
  
  @override
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'position': {'dx': position.dx, 'dy': position.dy},
      'isSelected': isSelected,
      'size': {'width': size.width, 'height': size.height},
      'videoUrl': videoUrl,
      // We don't serialize the controller - it will be recreated on load
    };
  }
  
  // Similar to ImageElement, this can't be fully deserialized without async operations
  static VideoElement fromMap(Map<String, dynamic> map) {
    // Parse position
    final posMap = map['position'];
    final position = Offset(
      posMap['dx'] as double, 
      posMap['dy'] as double
    );
    
    // Parse size
    final sizeMap = map['size'];
    final size = Size(
      sizeMap['width'] as double,
      sizeMap['height'] as double
    );
    
    // Note: Can't create the controller here since it requires async initialization
    throw UnimplementedError(
      'VideoElement.fromMap requires creating a VideoPlayerController, which is an async operation. '
      'The video URL is: ${map['videoUrl']}. This should be handled by a provider.'
    );
  }
}