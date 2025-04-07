// lib/models/image_element.dart
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'element.dart';

// Represents an image placed on the canvas
class ImageElement extends DrawingElement {
  final ui.Image image; // The actual image data
  final Size size; // Display size of the image on the canvas
  final String? imagePath; // Path to the image file for serialization

  ImageElement({
    String? id,
    required Offset position,
    bool isSelected = false,
    required this.image,
    required this.size,
    this.imagePath,
    double rotation = 0.0, // Add rotation parameter
  }) : super(id: id, type: ElementType.image, position: position, isSelected: isSelected, rotation: rotation);

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
    Size? size,      // Allow resizing
    String? imagePath,
    double? rotation, // Add rotation parameter
  }) {
    return ImageElement(
      id: id ?? this.id,
      position: position ?? this.position,
      isSelected: isSelected ?? this.isSelected,
      image: image ?? this.image, // Keep original image by default
      size: size ?? this.size,    // Keep original size by default
      imagePath: imagePath ?? this.imagePath,
      rotation: rotation ?? this.rotation, // Include rotation
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
      imagePath: imagePath,
      rotation: rotation, // Include rotation in clone
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
      'imagePath': imagePath,
      'rotation': rotation, // Add rotation to serialization
    };
  }
  
  // This static method will need UI interaction to load the actual image
  // The full implementation would need to load the image from the path
  static ImageElement fromMap(Map<String, dynamic> map) {
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
    
    // Note: We can't fully deserialize here without loading the image,
    // which requires asynchronous code. We'd typically handle this in DrawingProvider.
    throw UnimplementedError(
      'ImageElement.fromMap requires loading an image, which is an async operation. '
      'The image path is: ${map['imagePath']}. This should be handled by a provider.'
    );
  }
}