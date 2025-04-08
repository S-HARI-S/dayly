// lib/models/text_element.dart
import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'element.dart';
import 'dart:math' as math;

// Represents a text element on the canvas
class TextElement extends DrawingElement {
  // Add size constraints as static constants
  static const double MIN_FONT_SIZE = 8.0;
  static const double MAX_FONT_SIZE = 72.0; // Match the toolbar's maximum
  static const double MIN_WIDTH = 20.0;
  static const double MIN_HEIGHT = 20.0;
  
  final String text;
  final Color color;
  final double fontSize;
  final String fontFamily;
  final FontWeight fontWeight;
  final FontStyle fontStyle;
  final TextAlign textAlign;

  // Internal TextPainter for layout and rendering
  late final TextPainter _textPainter;

  TextElement({
    super.id,
    required super.position,
    super.isSelected,
    required this.text,
    required this.color,
    this.fontSize = 24.0,
    this.fontFamily = 'Roboto', // Default font family
    this.fontWeight = FontWeight.normal,
    this.fontStyle = FontStyle.normal,
    this.textAlign = TextAlign.left,
    super.rotation, // Add rotation parameter
  }) : super(type: ElementType.text) {
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
          fontFamily: fontFamily,
          fontWeight: fontWeight,
          fontStyle: fontStyle,
        ),
      ),
      textAlign: textAlign,
      textDirection: ui.TextDirection.ltr,
    )..layout(); // Perform layout to calculate size
  }

  // --- DrawingElement Overrides ---

  @override
  Rect get bounds => Rect.fromLTWH(position.dx, position.dy, _textPainter.width, _textPainter.height);

  @override
  bool containsPoint(Offset point) => bounds.contains(point);

  @override
  void render(Canvas canvas, {double inverseScale = 1.0}) {
    // Remove rotation application since ElementPainter handles it
    _textPainter.paint(canvas, position);
  }

  @override
  TextElement copyWith({
    String? id,
    Offset? position,
    bool? isSelected,
    String? text,
    Color? color,
    double? fontSize,
    String? fontFamily,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    TextAlign? textAlign,
    Size? size,
    double? rotation,
  }) {
    double finalFontSize = fontSize ?? this.fontSize;
    Offset finalPosition = position ?? this.position;

    if (size != null) {
      Rect oldBounds = bounds;
      if (!oldBounds.isEmpty && oldBounds.height > 0) {
        // Ensure size respects minimum constraints
        double constrainedWidth = math.max(size.width, MIN_WIDTH);
        double constrainedHeight = math.max(size.height, MIN_HEIGHT);
        
        // Calculate scale factors
        double scaleX = constrainedWidth / oldBounds.width;
        double scaleY = constrainedHeight / oldBounds.height;
        
        // Use the smaller scale to maintain aspect ratio
        double scale = math.min(scaleX, scaleY);
        
        // Update font size based on scale without clamping to MAX_FONT_SIZE
        finalFontSize = (this.fontSize * scale).clamp(MIN_FONT_SIZE, double.infinity);
        
        // Calculate new position to maintain center alignment
        final center = oldBounds.center;
        final newWidth = oldBounds.width * scale;
        final newHeight = oldBounds.height * scale;
        
        // If the element is rotated, we need to adjust the position calculation
        if (rotation != null && rotation != 0) {
          // Normalize rotation to be between 0 and 2π
          double normalizedRotation = rotation % (2 * math.pi);
          if (normalizedRotation < 0) normalizedRotation += 2 * math.pi;
          
          // Calculate the rotated center point
          // For angles close to 180 degrees or its multiples, use a different approach
          if ((normalizedRotation - math.pi).abs() < 0.01 || 
              (normalizedRotation - 2 * math.pi).abs() < 0.01) {
            // For angles close to 180 degrees, simply invert the coordinates
            finalPosition = Offset(
              center.dx - newWidth / 2,
              center.dy - newHeight / 2
            );
          } else {
            // For other angles, use the standard rotation formula
            final rotatedCenter = Offset(
              center.dx * math.cos(normalizedRotation) - center.dy * math.sin(normalizedRotation),
              center.dx * math.sin(normalizedRotation) + center.dy * math.cos(normalizedRotation)
            );
            
            finalPosition = Offset(
              rotatedCenter.dx - newWidth / 2,
              rotatedCenter.dy - newHeight / 2
            );
          }
        } else {
          // If not rotated, use the standard center alignment
          finalPosition = Offset(
            center.dx - newWidth / 2,
            center.dy - newHeight / 2
          );
        }
      }
    } else if (fontSize != null) {
      // If only fontSize is provided, only clamp to minimum
      finalFontSize = fontSize.clamp(MIN_FONT_SIZE, double.infinity);
    }

    return TextElement(
      id: id ?? this.id,
      position: finalPosition,
      isSelected: isSelected ?? this.isSelected,
      text: text ?? this.text,
      color: color ?? this.color,
      fontSize: finalFontSize,
      fontFamily: fontFamily ?? this.fontFamily,
      fontWeight: fontWeight ?? this.fontWeight,
      fontStyle: fontStyle ?? this.fontStyle,
      textAlign: textAlign ?? this.textAlign,
      rotation: rotation ?? this.rotation,
    );
  }

  @override
  TextElement clone() {
    return TextElement(
      id: id,
      position: position,
      isSelected: false,
      text: text,
      color: color,
      fontSize: fontSize,
      fontFamily: fontFamily,
      fontWeight: fontWeight,
      fontStyle: fontStyle,
      textAlign: textAlign,
      rotation: rotation, // Include rotation in clone
    );
  }

  // --- Serialization Methods ---

  @override
  Map<String, dynamic> toMap() {
    return {
      'elementType': 'text', // Ensure type is saved
      'id': id,
      'position': {'dx': position.dx, 'dy': position.dy},
      'isSelected': isSelected,
      'text': text,
      'color': color.value,
      'fontSize': fontSize,
      'fontFamily': fontFamily,
      'fontWeight': fontWeight.index, // Store enum index
      'fontStyle': fontStyle.index,
      'textAlign': textAlign.index,
      'rotation': rotation, // Add rotation to serialization
    };
  }

  static TextElement fromMap(Map<String, dynamic> map) {
    final posMap = map['position'];
    final position = Offset(
      posMap['dx'] as double,
      posMap['dy'] as double
    );

    return TextElement(
      id: map['id'],
      position: position,
      isSelected: map['isSelected'] ?? false,
      text: map['text'],
      color: Color(map['color']),
      fontSize: map['fontSize'] ?? 24.0,
      fontFamily: map['fontFamily'] ?? 'Roboto',
      fontWeight: FontWeight.values[map['fontWeight'] ?? FontWeight.normal.index],
      fontStyle: FontStyle.values[map['fontStyle'] ?? FontStyle.normal.index],
      textAlign: TextAlign.values[map['textAlign'] ?? TextAlign.left.index],
      rotation: map['rotation'] ?? 0.0, // Parse rotation from map
    );
  }
}