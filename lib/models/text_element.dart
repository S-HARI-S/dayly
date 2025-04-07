// lib/models/text_element.dart
import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'element.dart';

// Represents a text element on the canvas
class TextElement extends DrawingElement {
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
    String? id,
    required Offset position,
    bool isSelected = false,
    required this.text,
    required this.color,
    this.fontSize = 24.0,
    this.fontFamily = 'Roboto', // Default font family
    this.fontWeight = FontWeight.normal,
    this.fontStyle = FontStyle.normal,
    this.textAlign = TextAlign.left,
    double rotation = 0.0, // Add rotation parameter
  }) : super(id: id, type: ElementType.text, position: position, isSelected: isSelected, rotation: rotation) {
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
    double? rotation, // Add rotation parameter
  }) {
    double finalFontSize = fontSize ?? this.fontSize;

    if (size != null) {
        Rect oldBounds = bounds;
        if (!oldBounds.isEmpty && oldBounds.height > 0) {
            double scaleY = size.height / oldBounds.height;
            finalFontSize = (this.fontSize * scaleY).clamp(8.0, 500.0);
        }
    }

    return TextElement(
      id: id ?? this.id,
      position: position ?? this.position,
      isSelected: isSelected ?? this.isSelected,
      text: text ?? this.text,
      color: color ?? this.color,
      fontSize: finalFontSize,
      fontFamily: fontFamily ?? this.fontFamily,
      fontWeight: fontWeight ?? this.fontWeight,
      fontStyle: fontStyle ?? this.fontStyle,
      textAlign: textAlign ?? this.textAlign,
      rotation: rotation ?? this.rotation, // Pass rotation
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