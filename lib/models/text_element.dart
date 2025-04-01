// lib/models/text_element.dart
import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'element.dart';

// Represents a text element on the canvas
class TextElement extends DrawingElement {
  final String text;
  final Color color;
  final double fontSize; // Added font size property
  // Add other text properties like fontWeight, fontFamily etc. if needed

  // Internal TextPainter for layout and rendering
  late final TextPainter _textPainter;

  TextElement({
    String? id,
    required Offset position,
    bool isSelected = false,
    required this.text,
    required this.color,
    this.fontSize = 24.0, // Default font size
  }) : super(id: id, type: ElementType.text, position: position, isSelected: isSelected) {
    // Initialize TextPainter immediately
    _updateTextPainter();
  }

  // Helper to configure the TextPainter
  void _updateTextPainter() {
    _textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          // Add other styles (fontWeight, fontFamily) here
        ),
      ),
      textDirection: ui.TextDirection.ltr, // Or determine based on locale
    )..layout(); // Perform layout to calculate size
  }

  // --- DrawingElement Overrides ---

  @override
  Rect get bounds => Rect.fromLTWH(position.dx, position.dy, _textPainter.width, _textPainter.height);

  @override
  bool containsPoint(Offset point) => bounds.contains(point);

  @override
  void render(Canvas canvas, {double inverseScale = 1.0}) {
    // Paint the text at the element's position
    _textPainter.paint(canvas, position);

    // Optional: Draw selection highlight using bounds
    // if (isSelected) {
    //   final selectionPaint = Paint()
    //     ..color = Colors.blue.withAlpha(80)
    //     ..style = PaintingStyle.stroke
    //     ..strokeWidth = 1.5 * inverseScale;
    //   canvas.drawRect(bounds, selectionPaint);
    // }
  }

  @override
  TextElement copyWith({
    String? id,
    Offset? position,
    bool? isSelected,
    String? text,
    Color? color,
    double? fontSize,
    Size? size, // Size parameter for resizing (likely changes font size)
  }) {
    double finalFontSize = fontSize ?? this.fontSize;

    // --- Handle Resizing ---
    // Simplest way to resize text is to adjust font size based on height change.
    // Assumes resizing is proportional or primarily vertical.
    if (size != null) {
        Rect oldBounds = bounds; // Bounds based on current font size
        if (!oldBounds.isEmpty && oldBounds.height > 0) {
            double scaleY = size.height / oldBounds.height;
            // Adjust font size proportionally (clamp to reasonable limits)
            finalFontSize = (this.fontSize * scaleY).clamp(8.0, 500.0);
        }
    }

    return TextElement(
      id: id ?? this.id,
      position: position ?? this.position, // Update position if provided
      isSelected: isSelected ?? this.isSelected,
      text: text ?? this.text, // Update text if provided
      color: color ?? this.color,
      fontSize: finalFontSize, // Use potentially updated font size
    );
  }

  @override
  TextElement clone() {
    return TextElement(
      id: id,
      position: position,
      isSelected: false, // Selection is transient
      text: text,
      color: color,
      fontSize: fontSize,
    );
  }
}