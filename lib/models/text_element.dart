// lib/models/text_element.dart
import 'package:flutter/material.dart';
import 'element.dart';

class TextElement extends DrawingElement {
  final String text;
  final double fontSize;

  TextElement({
    required Offset position,
    required this.text,
    required Color color,
    this.fontSize = 16.0,
    String? id,
    bool isSelected = false,
  }) : super(
         id: id ?? UniqueKey().toString(),
         position: position,
         color: color,
         isSelected: isSelected,
         type: ElementType.text,
       );

  @override
  void render(Canvas canvas) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: fontSize),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, position);
  }

  @override
  Rect get bounds {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: fontSize),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    return position & textPainter.size;
  }

  @override
  bool containsPoint(Offset point) {
    return bounds.contains(point);
  }

  @override
  DrawingElement copyWith({
    Offset? position,
    bool? isSelected,
    Color? color,
    String? text,
    double? fontSize,
  }) {
    return TextElement(
      position: position ?? this.position,
      text: text ?? this.text,
      color: color ?? this.color,
      fontSize: fontSize ?? this.fontSize,
      id: id,
      isSelected: isSelected ?? this.isSelected,
    );
  }
}
