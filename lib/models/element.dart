// lib/models/element.dart
import 'package:flutter/material.dart';
import 'dart:ui' as ui; // For Canvas

// Enum defining the types of elements that can be drawn or interacted with
enum ElementType {
  select, // Special type for the selection tool itself
  pen,
  text,
  rectangle, // Placeholder
  circle, // Placeholder
  arrow, // Placeholder
  image,
  video,
  group // Placeholder
}

// Abstract base class for all drawable elements on the canvas
abstract class DrawingElement {
  final String id; // Unique identifier for the element
  final ElementType type; // Type of the element
  final Offset position; // Usually the top-left corner, but interpretation depends on the element
  final bool isSelected; // Flag indicating if the element is currently selected

  DrawingElement({
    String? id,
    required this.type,
    required this.position,
    this.isSelected = false,
  }) : id = id ?? DateTime.now().microsecondsSinceEpoch.toString() + UniqueKey().toString(); // More robust unique ID

  // Abstract method for subclasses to implement hit testing logic
  // Determines if a given point (in canvas coordinates) is contained within the element
  bool containsPoint(Offset point);

  // Abstract method for subclasses to implement rendering logic
  // Draws the element onto the provided canvas
  // `inverseScale` can be used to draw elements (like strokes) with a consistent screen size
  void render(Canvas canvas, {double inverseScale = 1.0});

  // Abstract method for creating a modified copy of the element.
  // Subclasses must implement this to support immutable updates.
  // Parameters should include all mutable properties of the element.
  DrawingElement copyWith({
    String? id, // Usually not changed, but possible
    Offset? position,
    bool? isSelected,
    Size? size, // Ensure this parameter exists in the base class
  });

  // Abstract method for creating a deep clone of the element state.
  // Essential for the undo/redo system. Selection state is typically NOT cloned.
  DrawingElement clone();

  // Abstract property defining the bounding box of the element.
  // Subclasses MUST override this to provide accurate bounds for selection and handles.
  // Should return Rect.zero or similar if bounds cannot be determined.
  Rect get bounds;

  // Abstract method for serialization - converts element to a map
  Map<String, dynamic> toMap();
  
  // Optional static method to create an element from map data
  // This will be implemented in each concrete subclass
  // static DrawingElement fromMap(Map<String, dynamic> map) {
  //   // Implementation in subclasses
  // }

  // Optional: Override equality operator and hashCode if elements need to be compared directly
  // (e.g., if used in Sets or as Map keys, or for more robust shouldRepaint checks)
  // @override
  // bool operator ==(Object other) =>
  //     identical(this, other) ||
  //     other is DrawingElement &&
  //         runtimeType == other.runtimeType &&
  //         id == other.id // Comparing by ID is usually sufficient
  // // Add other relevant properties if needed for equality check
  //         && position == other.position
  //         && isSelected == other.isSelected;
  //
  // @override
  // int get hashCode => id.hashCode ^ position.hashCode ^ isSelected.hashCode; // Combine relevant properties
}


