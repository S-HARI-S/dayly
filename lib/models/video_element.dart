// lib/models/video_element.dart
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'element.dart';

class VideoElement extends DrawingElement {
  final String videoUrl;
  final VideoPlayerController controller;
  Size size;
  bool isPlaying;
  
  VideoElement({
    required this.videoUrl,
    required this.controller,
    required super.position,
    required this.size,
    this.isPlaying = false,
    super.color = Colors.white,
    super.isSelected = false,
  }) : super(type: ElementType.video);

  @override
  bool containsPoint(Offset point) {
    return bounds.contains(point);
  }

  @override
  DrawingElement copyWith({
    Offset? position,
    Color? color,
    bool? isSelected,
    String? videoUrl,
    VideoPlayerController? controller,
    Size? size,
    bool? isPlaying,
  }) {
    return VideoElement(
      videoUrl: videoUrl ?? this.videoUrl,
      controller: controller ?? this.controller,
      position: position ?? this.position,
      size: size ?? this.size,
      isPlaying: isPlaying ?? this.isPlaying,
      color: color ?? this.color,
      isSelected: isSelected ?? this.isSelected,
    );
  }

  @override
  void render(Canvas canvas) {
    // Draw a placeholder when the video isn't initialized
    final paint = Paint()
      ..color = Colors.black.withOpacity(0.1)
      ..style = PaintingStyle.fill;
    
    canvas.drawRect(bounds, paint);
    
    // Draw play/pause icon
    final iconPaint = Paint()
      ..color = Colors.white.withOpacity(0.8);
    
    if (!isPlaying) {
      // Draw play triangle
      final path = Path();
      final centerX = bounds.center.dx;
      final centerY = bounds.center.dy;
      final size = 24.0;
      
      path.moveTo(centerX - size/2, centerY - size/2);
      path.lineTo(centerX - size/2, centerY + size/2);
      path.lineTo(centerX + size/2, centerY);
      path.close();
      
      canvas.drawPath(path, iconPaint);
    } else {
      // Draw pause bars
      final size = 20.0;
      final centerX = bounds.center.dx;
      final centerY = bounds.center.dy;
      
      canvas.drawRect(
        Rect.fromLTWH(centerX - size/2, centerY - size/2, size/3, size),
        iconPaint,
      );
      
      canvas.drawRect(
        Rect.fromLTWH(centerX + size/6, centerY - size/2, size/3, size),
        iconPaint,
      );
    }
    
    // Draw selection border if selected
    if (isSelected) {
      final borderPaint = Paint()
        ..color = Colors.blue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      
      canvas.drawRect(bounds, borderPaint);
      
      // Draw resize handles
      final handlePaint = Paint()..color = Colors.blue;
      final handleSize = 8.0;
      
      // Corner handles
      canvas.drawCircle(Offset(bounds.left, bounds.top), handleSize, handlePaint);
      canvas.drawCircle(Offset(bounds.right, bounds.top), handleSize, handlePaint);
      canvas.drawCircle(Offset(bounds.left, bounds.bottom), handleSize, handlePaint);
      canvas.drawCircle(Offset(bounds.right, bounds.bottom), handleSize, handlePaint);
    }
  }
  
  @override
  Rect get bounds => Rect.fromLTWH(position.dx, position.dy, size.width, size.height);
  
  void togglePlayPause() {
    if (controller.value.isPlaying) {
      controller.pause();
      isPlaying = false;
    } else {
      controller.play();
      isPlaying = true;
    }
  }
  
  void dispose() {
    controller.dispose();
  }
}