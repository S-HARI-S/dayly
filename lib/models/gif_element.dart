import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'element.dart';

class GifElement extends DrawingElement {
  final String gifUrl;
  final String? previewUrl;
  final Size size;

  GifElement({
    String? id,
    required super.position,
    super.isSelected,
    required this.size,
    required this.gifUrl,
    this.previewUrl,
    super.rotation,
  }) : super(
          id: id ?? const Uuid().v4(),
          type: ElementType.gif,
        );

  @override
  Rect get bounds => Rect.fromLTWH(position.dx, position.dy, size.width, size.height);

  @override
  bool containsPoint(Offset point) => bounds.contains(point);

  @override
  void render(Canvas canvas, {double inverseScale = 1.0}) {
    // GIFs are rendered by the Flutter widget system in DrawingCanvas
    // Here we just render a placeholder when needed
    final paint = Paint()..color = Colors.grey.withOpacity(0.3);
    canvas.drawRect(bounds, paint);
    
    // Draw a GIF indicator
    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'GIF',
        style: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas, 
      Offset(
        bounds.center.dx - textPainter.width / 2,
        bounds.center.dy - textPainter.height / 2
      )
    );
  }

  @override
  GifElement copyWith({
    String? id,
    Offset? position,
    bool? isSelected,
    Size? size,
    String? gifUrl,
    String? previewUrl,
    double? rotation,
  }) {
    return GifElement(
      id: id ?? this.id,
      position: position ?? this.position,
      isSelected: isSelected ?? this.isSelected,
      size: size ?? this.size,
      gifUrl: gifUrl ?? this.gifUrl,
      previewUrl: previewUrl ?? this.previewUrl,
      rotation: rotation ?? this.rotation,
    );
  }

  @override
  GifElement clone() {
    return GifElement(
      id: id,
      position: position,
      isSelected: false,
      size: size,
      gifUrl: gifUrl,
      previewUrl: previewUrl,
      rotation: rotation,
    );
  }
  
  // --- Serialization Methods ---
  @override
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'elementType': 'gif',
      'position': {'dx': position.dx, 'dy': position.dy},
      'isSelected': isSelected,
      'size': {'width': size.width, 'height': size.height},
      'gifUrl': gifUrl,
      'previewUrl': previewUrl,
      'rotation': rotation,
    };
  }
  
  static GifElement fromMap(Map<String, dynamic> map) {
    // Parse position
    final posMap = map['position'];
    final position = Offset(
      posMap['dx'] as double, 
      posMap['dy'] as double
    );
    
    // Parse size
    final sizeMap = map['size'];
    final size = Size(
      sizeMap['width'] as double,
      sizeMap['height'] as double
    );
    
    return GifElement(
      id: map['id'],
      position: position,
      isSelected: map['isSelected'] ?? false,
      size: size,
      gifUrl: map['gifUrl'],
      previewUrl: map['previewUrl'],
      rotation: map['rotation'] ?? 0.0,
    );
  }
}