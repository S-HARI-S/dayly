// lib/models/element.dart
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

enum ElementType { pen, rectangle, circle, arrow, text }

abstract class DrawingElement {
  final String id;
  final ElementType type;
  Offset position;
  Color color;
  bool isSelected;
  
  DrawingElement({
    String? id,
    required this.type,
    required this.position,
    required this.color,
    this.isSelected = false,
  }) : id = id ?? const Uuid().v4();
  
  DrawingElement copyWith({
    Offset? position,
    Color? color,
    bool? isSelected,
  });
  
  void render(Canvas canvas);
  bool containsPoint(Offset point);
  Rect get bounds;
}

