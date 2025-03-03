import 'package:flutter/material.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'element.dart';

class PenElement extends DrawingElement {
  final List<Offset> points;
  final double strokeWidth;
  
  PenElement({
    super.id,
    required super.position,
    required super.color,
    required this.points,
    this.strokeWidth = 2.0,
    super.isSelected = false,
  }) : super(type: ElementType.pen);
  
  @override
  DrawingElement copyWith({
    Offset? position,
    Color? color,
    bool? isSelected,
    List<Offset>? points,
    double? strokeWidth,
  }) {
    return PenElement(
      id: id,
      position: position ?? this.position,
      color: color ?? this.color,
      points: points ?? List.from(this.points),
      strokeWidth: strokeWidth ?? this.strokeWidth,
      isSelected: isSelected ?? this.isSelected,
    );
  }
  
  @override
  void render(Canvas canvas) {
    if (points.length < 2) return;
    
    final paint = Paint()
      ..color = isSelected ? color.withOpacity(0.8) : color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    
    final path = Path();
    
    // Convert Flutter Offset points to Point objects that perfect_freehand expects
    final inputPoints = points.map((p) => Point(p.dx, p.dy)).toList();
    
    // Use perfect_freehand for smoother strokes
    final stroke = getStroke(
      inputPoints,
      size: strokeWidth,
      thinning: 0.5,
      smoothing: 0.5,
      streamline: 0.5,
    );
    
    if (stroke.isNotEmpty) {
      // Access x and y properties of Point objects returned by getStroke
      path.moveTo(stroke[0].x, stroke[0].y);
      
      for (int i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].x, stroke[i].y);
      }
      
      if (stroke.length >= 3) {
        path.close();
      }
    }
    
    canvas.drawPath(path, paint);
    
    // Draw selection indicator
    if (isSelected) {
      final bounds = this.bounds;
      final selectionPaint = Paint()
        ..color = Colors.blue.withOpacity(0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
        
      canvas.drawRect(bounds.inflate(4), selectionPaint);
    }
  }
  
  @override
  bool containsPoint(Offset point) {
    if (points.isEmpty) return false;
    
    const hitSlop = 10.0;
    
    // Check if point is near any point in the stroke
    for (final p in points) {
      if ((p - point).distance < hitSlop) {
        return true;
      }
    }
    
    return false;
  }
  
  @override
  Rect get bounds {
    if (points.isEmpty) return Rect.zero;
    
    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = -double.infinity;
    double maxY = -double.infinity;
    
    for (final point in points) {
      minX = point.dx < minX ? point.dx : minX;
      minY = point.dy < minY ? point.dy : minY;
      maxX = point.dx > maxX ? point.dx : maxX;
      maxY = point.dy > maxY ? point.dy : maxY;
    }
    
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }
}