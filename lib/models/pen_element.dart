// lib/models/pen_element.dart
import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'element.dart';

// Represents a freehand drawing (a series of connected points)
class PenElement extends DrawingElement {
  final List<Offset> points; // List of points defining the path
  final Color color;
  final double strokeWidth;

  PenElement({
    String? id,
    required Offset position, // Note: position might be redundant if bounds are calculated from points
    bool isSelected = false,
    required this.points,
    required this.color,
    required this.strokeWidth,
  }) : super(id: id, type: ElementType.pen, position: position, isSelected: isSelected);

  // --- DrawingElement Overrides ---

  @override
  bool containsPoint(Offset point) {
    // Hit testing for a path is more complex.
    // A simple approach is to check distance to line segments or use bounds.
    // Using bounds is faster but less accurate for thin/sparse lines.
    if (bounds.contains(point)) {
      // Optional: More precise check - iterate through line segments
      // and check distance from point to segment.
      for (int i = 0; i < points.length - 1; i++) {
        // Basic distance check to segment (simplified)
        // A more robust check involves projections.
        Rect segmentBounds = Rect.fromPoints(points[i], points[i + 1]).inflate(strokeWidth * 2); // Inflate for easier hit
        if (segmentBounds.contains(point)) {
            // TODO: Implement point-to-line segment distance check for better accuracy
            return true; // Placeholder: Return true if near any segment bounds
        }
      }
       // If bounds contain point but no segment near, maybe return false? Depends on desired accuracy.
       // return false; // If more precise check fails
    }
    return false; // Default to bounds check for performance
  }

  @override
  void render(Canvas canvas, {double inverseScale = 1.0}) {
    if (points.length < 2) return; // Need at least two points to draw

    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth // Use original stroke width for path data
      // Consider scaling stroke width for consistent appearance: strokeWidth * inverseScale
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round // Smoother line joins
      ..strokeJoin = StrokeJoin.round;

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }

    canvas.drawPath(path, paint);

    // Optional: Draw selection highlight if selected (using bounds)
    // if (isSelected) {
    //   final selectionPaint = Paint()
    //     ..color = Colors.blue.withAlpha(80)
    //     ..style = PaintingStyle.stroke
    //     ..strokeWidth = 1.5 * inverseScale; // Scale highlight stroke
    //   canvas.drawRect(bounds.inflate(strokeWidth / 2), selectionPaint); // Inflate bounds slightly
    // }
  }

  @override
  Rect get bounds {
    if (points.isEmpty) return Rect.fromLTWH(position.dx, position.dy, 0, 0);

    // Calculate bounds based on actual points
    double minX = points.first.dx, maxX = points.first.dx;
    double minY = points.first.dy, maxY = points.first.dy;
    for (int i = 1; i < points.length; i++) {
      final p = points[i];
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }
    // Inflate bounds slightly to account for stroke width for accurate handle placement
    return Rect.fromLTRB(minX, minY, maxX, maxY).inflate(strokeWidth / 2);
  }

  @override
  PenElement copyWith({
    String? id,
    Offset? position, // New top-left position (requires recalculating points if used)
    bool? isSelected,
    List<Offset>? points, // New list of points
    Color? color,
    double? strokeWidth,
    Size? size, // Size parameter for resizing - requires scaling points
  }) {
    List<Offset> finalPoints = points ?? this.points;
    Offset finalPosition = position ?? this.position; // Original or new position

    // --- Handle Resizing based on 'size' parameter ---
    // This is complex for pen strokes. A simple approach scales points relative to the old bounds.
    if (size != null) {
       Rect oldBounds = bounds; // Get bounds BEFORE applying new position
       if (!oldBounds.isEmpty && oldBounds.size != Size.zero) {
           double scaleX = size.width / oldBounds.width;
           double scaleY = size.height / oldBounds.height;

           // Apply new position as the top-left anchor for scaling
           finalPosition = position ?? oldBounds.topLeft; // Use new position if provided, else old top-left

           List<Offset> scaledPoints = [];
           for (var p in this.points) {
               // Translate point relative to old top-left, scale, then translate to new top-left
               double newDx = finalPosition.dx + (p.dx - oldBounds.left) * scaleX;
               double newDy = finalPosition.dy + (p.dy - oldBounds.top) * scaleY;
               scaledPoints.add(Offset(newDx, newDy));
           }
           finalPoints = scaledPoints;
       }
    }
    // --- Handle Position change WITHOUT size change ---
    // If only position changed, translate all points
    else if (position != null && position != this.position) {
       Offset delta = position - this.position;
       finalPoints = this.points.map((p) => p + delta).toList();
       finalPosition = position; // Use the new position
    }


    return PenElement(
      id: id ?? this.id, // Keep ID
      position: finalPosition, // Use the calculated final position
      isSelected: isSelected ?? this.isSelected,
      points: finalPoints, // Use the updated points list
      color: color ?? this.color,
      strokeWidth: strokeWidth ?? this.strokeWidth,
    );
  }


  @override
  PenElement clone() {
    return PenElement(
      id: id, // Keep ID
      position: position,
      isSelected: false, // Selection state is transient
      points: List<Offset>.from(points), // *** Crucial: Deep copy the points list ***
      color: color,
      strokeWidth: strokeWidth,
    );
  }
  
  // --- Serialization Methods ---
  
  @override
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'position': {'dx': position.dx, 'dy': position.dy},
      'isSelected': isSelected,
      'color': color.value, // Store color as integer value
      'strokeWidth': strokeWidth,
      'points': points.map((p) => {'dx': p.dx, 'dy': p.dy}).toList(),
    };
  }
  
  static PenElement fromMap(Map<String, dynamic> map) {
    // Parse position
    final posMap = map['position'];
    final position = Offset(
      posMap['dx'] as double, 
      posMap['dy'] as double
    );
    
    // Parse points
    final pointsList = (map['points'] as List)
        .map((pointMap) => Offset(
              pointMap['dx'] as double,
              pointMap['dy'] as double,
            ))
        .toList();
    
    return PenElement(
      id: map['id'],
      position: position,
      isSelected: map['isSelected'] ?? false,
      color: Color(map['color']),
      strokeWidth: map['strokeWidth'],
      points: pointsList,
    );
  }
}