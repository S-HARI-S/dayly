// lib/models/image_element.dart
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'element.dart';

// Represents an image placed on the canvas
class ImageElement extends DrawingElement {
  final ui.Image image; // The actual image data
  final Size size; // Display size of the image on the canvas

  ImageElement({
    String? id,
    required Offset position,
    bool isSelected = false,
    required this.image,
    required this.size,
  }) : super(id: id, type: ElementType.image, position: position, isSelected: isSelected);

  // --- DrawingElement Overrides ---

  @override
  Rect get bounds => Rect.fromLTWH(position.dx, position.dy, size.width, size.height);

  @override
  bool containsPoint(Offset point) => bounds.contains(point);

  @override
  void render(Canvas canvas, {double inverseScale = 1.0}) {
    // Define the source rectangle (full image)
    final srcRect = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    // Define the destination rectangle (position and size on canvas)
    final dstRect = bounds;

    // Draw the image scaled/positioned into the destination rect
    canvas.drawImageRect(image, srcRect, dstRect, Paint());

    // Optional: Draw selection highlight
    // if (isSelected) {
    //   final selectionPaint = Paint()
    //     ..color = Colors.blue.withAlpha(80)
    //     ..style = PaintingStyle.stroke
    //     ..strokeWidth = 1.5 * inverseScale;
    //   canvas.drawRect(bounds, selectionPaint);
    // }
  }

  @override
  ImageElement copyWith({
    String? id,
    Offset? position,
    bool? isSelected,
    ui.Image? image, // Allow replacing image if needed
    Size? size,       // Allow resizing
  }) {
    return ImageElement(
      id: id ?? this.id,
      position: position ?? this.position,
      isSelected: isSelected ?? this.isSelected,
      image: image ?? this.image, // Keep original image by default
      size: size ?? this.size,       // Keep original size by default
    );
  }

  @override
  ImageElement clone() {
    // Note: ui.Image itself might be immutable or reference-counted.
    // Cloning usually just involves copying the reference. Check Flutter docs if deep copy needed.
    return ImageElement(
      id: id,
      position: position,
      isSelected: false, // Selection is transient
      image: image, // Copy reference
      size: size,
    );
  }
}