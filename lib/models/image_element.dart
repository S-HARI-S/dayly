// lib/models/image_element.dart
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'element.dart';

class ImageElement extends DrawingElement {
  final ui.Image image;
  Size size;
  
  ImageElement({
    required this.image,
    required super.position,
    required this.size,
    super.color = Colors.white,
    super.isSelected = false,
  }) : super(type: ElementType.image);

  @override
  bool containsPoint(Offset point) {
    return bounds.contains(point);
  }

  @override
  DrawingElement copyWith({
    Offset? position,
    Color? color,
    bool? isSelected,
    ui.Image? image,
    Size? size,
  }) {
    return ImageElement(
      image: image ?? this.image,
      position: position ?? this.position,
      size: size ?? this.size,
      color: color ?? this.color,
      isSelected: isSelected ?? this.isSelected,
    );
  }

  @override
  void render(Canvas canvas) {
    final paint = Paint();
    
    // Draw the image
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(position.dx, position.dy, size.width, size.height),
      paint,
    );
    
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
}