// lib/models/gif_element.dart
import 'package:flutter/material.dart';
import './element.dart'; // Ensure ElementType enum is accessible (often in element.dart)
import 'dart:ui' as ui; // Keep ui import if needed by base class or other methods

// Represents a GIF placed on the canvas
class GifElement extends DrawingElement {
  // final ui.Image image; // REMOVED - No longer storing pre-decoded image data
  final Size size;         // Display size of the GIF on the canvas
  final String gifUrl;     // URL of the GIF for display and serialization
  final String? previewUrl; // Optional preview URL (static image or smaller GIF)

  // --- Constructor Updated: No longer requires ui.Image ---
  GifElement({
    String? id,             // Pass ID to super constructor
    required Offset position,
    bool isSelected = false, // Pass selection state to super constructor
    // required ui.Image image, // REMOVED parameter
    required this.size,
    required this.gifUrl,
    this.previewUrl,
    double rotation = 0.0, // Add rotation parameter
  }) : super(id: id, type: ElementType.gif, position: position, isSelected: isSelected, rotation: rotation); // Pass type and rotation to super

  // --- DrawingElement Overrides ---

  @override
  Rect get bounds => Rect.fromLTWH(position.dx, position.dy, size.width, size.height);

  @override
  bool containsPoint(Offset point) => bounds.contains(point); // Fixed missing parenthesis

  @override
  void render(Canvas canvas, {double inverseScale = 1.0}) {
    // This render method is called ONLY by DrawingPainter IF excludeGifContent is false.
    // Since excludeGifContent is TRUE in your DrawingCanvas, this method isn't
    // currently used for drawing the actual GIF content.
    // You might draw a simple placeholder rectangle here if needed for some reason,
    // or leave it empty. The selection outline/handles are drawn separately by DrawingPainter.

    // Example: Draw a simple placeholder rectangle (optional)
    final Paint placeholderPaint = Paint()
        ..color = Colors.grey.withAlpha(50) // Semi-transparent grey
        ..style = PaintingStyle.fill;
    canvas.drawRect(bounds, placeholderPaint);

    // Example: Draw a border (optional)
    // final Paint borderPaint = Paint()
    //   ..color = Colors.grey
    //   ..style = PaintingStyle.stroke
    //   ..strokeWidth = 1.0 * inverseScale;
    // canvas.drawRect(bounds, borderPaint);
  }

  // --- copyWith Updated: No 'image' parameter ---
  @override
  GifElement copyWith({
    String? id,
    Offset? position,
    bool? isSelected,
    // ui.Image? image, // REMOVED parameter
    Size? size,
    String? gifUrl,
    String? previewUrl,
    double? rotation, // Add rotation parameter
    // Add other base properties if needed (e.g., rotation, scale from base class)
  }) {
    return GifElement(
      id: id ?? this.id,
      position: position ?? this.position,
      isSelected: isSelected ?? this.isSelected,
      // image: image ?? this.image, // REMOVED line
      size: size ?? this.size,
      gifUrl: gifUrl ?? this.gifUrl,
      previewUrl: previewUrl ?? this.previewUrl,
      rotation: rotation ?? this.rotation, // Pass rotation
      // Pass other base properties
    );
  }

  // --- clone Updated: No 'image' field ---
  @override
  GifElement clone() {
    // Cloning creates a new instance with the same data, typically used for undo/redo state.
    return GifElement(
      id: id, // Keep the same ID when cloning for state history
      position: position,
      isSelected: isSelected, // Clone selection state as well
      // image: image, // REMOVED - ui.Image wasn't deep cloned anyway
      size: size,
      gifUrl: gifUrl,
      previewUrl: previewUrl,
      rotation: rotation, // Include rotation in clone
      // Clone other base properties
    );
  }

  // --- Serialization Methods ---

  // toMap remains the same (doesn't include image)
  @override
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type.index, // Make sure ElementType enum is defined and accessible
      'position': {'dx': position.dx, 'dy': position.dy},
      'isSelected': isSelected,
      'size': {'width': size.width, 'height': size.height},
      'gifUrl': gifUrl,
      'previewUrl': previewUrl,
      'rotation': rotation, // Add rotation to serialization
      // Add other serializable base properties
    };
  }

  // fromMap Updated: No longer throws error, just constructs without image
  static GifElement fromMap(Map<String, dynamic> map) {
    final posMap = map['position'];
    final position = Offset(posMap['dx'] as double, posMap['dy'] as double);

    final sizeMap = map['size'];
    final size = Size(sizeMap['width'] as double, sizeMap['height'] as double);

    // Construct without the ui.Image
    return GifElement(
      id: map['id'] as String?, // Allow null ID if base class handles default
      position: position,
      isSelected: map['isSelected'] as bool? ?? false,
      size: size,
      gifUrl: map['gifUrl'] as String,
      previewUrl: map['previewUrl'] as String?,
      rotation: map['rotation'] as double? ?? 0.0, // Parse rotation from map
      // Deserialize other base properties if needed
    );
    // NOTE: If deserialization required async work (like loading data),
    // that logic should reside in the provider/service performing the loading,
    // not directly within a static fromMap method.
  }
}


// Ensure ElementType enum is defined, likely in element.dart
// enum ElementType { select, pen, text, image, video, gif /*, ... */ }