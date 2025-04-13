// lib/models/handles.dart
import 'package:flutter/material.dart';

// Enum to represent different types of resize handles
enum ResizeHandleType {
  topLeft,
  topMiddle,
  topRight,
  middleLeft,
  middleRight,
  bottomLeft,
  bottomMiddle,
  bottomRight,
  rotate // Add rotation handle type
}

// Helper function to calculate the positions (Rects) of handles based on element bounds
Map<ResizeHandleType, Rect> calculateHandles(Rect bounds, double handleSize) {
  // Return empty map to disable all handles
  return {};

  // Original implementation:
  /*
  // Return empty map if bounds are invalid or too small
  if (bounds.isEmpty || bounds.width < handleSize || bounds.height < handleSize) {
    return {};
  }
  double halfHandle = handleSize / 2.0;

  final result = {
    // Corners
    ResizeHandleType.topLeft: Rect.fromCenter(center: bounds.topLeft, width: handleSize, height: handleSize),
    ResizeHandleType.topRight: Rect.fromCenter(center: bounds.topRight, width: handleSize, height: handleSize),
    ResizeHandleType.bottomLeft: Rect.fromCenter(center: bounds.bottomLeft, width: handleSize, height: handleSize),
    ResizeHandleType.bottomRight: Rect.fromCenter(center: bounds.bottomRight, width: handleSize, height: handleSize),

    // Middle Edges (optional)
    ResizeHandleType.topMiddle: Rect.fromCenter(center: bounds.topCenter, width: handleSize, height: handleSize),
    ResizeHandleType.bottomMiddle: Rect.fromCenter(center: bounds.bottomCenter, width: handleSize, height: handleSize),
    ResizeHandleType.middleLeft: Rect.fromCenter(center: bounds.centerLeft, width: handleSize, height: handleSize),
    ResizeHandleType.middleRight: Rect.fromCenter(center: bounds.centerRight, width: handleSize, height: handleSize),

    // Rotation Handle - positioned above top center
    ResizeHandleType.rotate: Rect.fromCenter(
      center: Offset(bounds.center.dx, bounds.top - handleSize * 2), 
      width: handleSize * 1.2, 
      height: handleSize * 1.2
    ),
  };

  return result;
  */
}