// lib/models/image_element.dart
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'element.dart';

// Represents an image placed on the canvas
class ImageElement extends DrawingElement {
  final ui.Image? image; // Make nullable if loading can fail
  final Size size; // Display size of the image on the canvas
  final String? imagePath; // Path to the image file for serialization
  final double brightness; // Add brightness field
  final double contrast; // Add contrast field

  ImageElement({
    super.id,
    required super.position,
    super.isSelected,
    required this.size,
    this.image,
    this.imagePath,
    this.brightness = 0.0, // Default value
    this.contrast = 0.0, // Default value
    super.rotation, // Add rotation parameter
  }) : super(type: ElementType.image);

  // --- DrawingElement Overrides ---

  @override
  Rect get bounds => Rect.fromLTWH(position.dx, position.dy, size.width, size.height);

  @override
  bool containsPoint(Offset point) => bounds.contains(point);

  @override
  void render(Canvas canvas, {double inverseScale = 1.0}) {
    if (image == null) {
      // Draw a placeholder if image is not loaded
      final Paint placeholderPaint = Paint()
        ..color = Colors.grey[300]!
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0 * inverseScale;
      canvas.drawRect(bounds, placeholderPaint);
      // Optionally draw an icon or text
      return;
    }

    // Apply brightness and contrast using ColorFilter
    final Paint paint = Paint();
    if (brightness != 0.0 || contrast != 0.0) {
      // Simple brightness/contrast matrix approximation
      // Contrast factor (1.0 = normal, >1 = more contrast, <1 = less contrast)
      double contrastFactor = contrast + 1.0;
      // Brightness adjustment (added after contrast scaling)
      double brightnessAdjust = brightness * 255;

      paint.colorFilter = ColorFilter.matrix(<double>[
        contrastFactor, 0, 0, 0, brightnessAdjust, // Red channel
        0, contrastFactor, 0, 0, brightnessAdjust, // Green channel
        0, 0, contrastFactor, 0, brightnessAdjust, // Blue channel
        0, 0, 0, 1, 0, // Alpha channel
      ]);
    }

    // Define the source rectangle (full image)
    final srcRect = Rect.fromLTWH(0, 0, image!.width.toDouble(), image!.height.toDouble());
    // Define the destination rectangle (position and size on canvas)
    final dstRect = bounds;

    // Apply rotation around the center of the image
    applyRotation(canvas, bounds, () {
      // Draw the image scaled/positioned into the destination rect
      canvas.drawImageRect(image!, srcRect, dstRect, paint);
    });

    // Remove selection highlight since SelectionPainter will handle this
    // The selection shadow will be drawn by SelectionPainter
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
    double? brightness, // Add brightness parameter
    double? contrast, // Add contrast parameter
  }) {
    return ImageElement(
      id: id ?? this.id,
      position: position ?? this.position,
      isSelected: isSelected ?? this.isSelected,
      image: image ?? this.image, // Keep original image by default
      size: size ?? this.size,    // Keep original size by default
      imagePath: imagePath ?? this.imagePath,
      rotation: rotation ?? this.rotation, // Include rotation
      brightness: brightness ?? this.brightness, // Include brightness
      contrast: contrast ?? this.contrast, // Include contrast
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
      brightness: brightness, // Include brightness in clone
      contrast: contrast, // Include contrast in clone
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
      'brightness': brightness, // Add brightness to serialization
      'contrast': contrast, // Add contrast to serialization
    };
  }
  
  // This static method will need UI interaction to load the actual image
  // The full implementation would need to load the image from the path
  factory ImageElement.fromMap(Map<String, dynamic> map) {
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
    return ImageElement(
      id: map['id'],
      position: position,
      size: size,
      isSelected: map['isSelected'] ?? false,
      rotation: map['rotation'] ?? 0.0,
      imagePath: map['imagePath'],
      brightness: map['brightness'] ?? 0.0,
      contrast: map['contrast'] ?? 0.0,
      // ui.Image is loaded separately during deserialization process
    );
  }

  @override
  void dispose() {
    image?.dispose(); // Dispose the ui.Image object
  }
}