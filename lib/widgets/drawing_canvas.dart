import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/drawing_provider.dart';
import '../models/element.dart';

class DrawingCanvas extends StatefulWidget {
  const DrawingCanvas({Key? key}) : super(key: key);

  @override
  State<DrawingCanvas> createState() => _DrawingCanvasState();
}

class _DrawingCanvasState extends State<DrawingCanvas> {
  Offset? _lastPosition;
  int _activePointers = 0;
  
  @override
  Widget build(BuildContext context) {
    return Consumer<DrawingProvider>(
      builder: (context, drawingProvider, child) {
        return Listener(
          // Track number of active pointers to only draw with single finger
          onPointerDown: (PointerDownEvent event) {
            setState(() {
              _activePointers++;
            });
            
            // Only start drawing if exactly one finger is used
            if (_activePointers == 1) {
              if (drawingProvider.currentTool == ElementType.pen) {
                drawingProvider.startDrawing(event.localPosition);
              } else {
                drawingProvider.selectElementAt(event.localPosition);
                _lastPosition = event.localPosition;
              }
            }
          },
          onPointerMove: (PointerMoveEvent event) {
            // Only update drawing if exactly one finger is active
            if (_activePointers == 1) {
              if (drawingProvider.currentTool == ElementType.pen) {
                drawingProvider.updateDrawing(event.localPosition);
              } else if (_lastPosition != null && 
                        drawingProvider.selectedElementIds.isNotEmpty) {
                final delta = event.localPosition - _lastPosition!;
                drawingProvider.moveSelected(delta);
                _lastPosition = event.localPosition;
              }
            }
          },
          onPointerUp: (PointerUpEvent event) {
            setState(() {
              _activePointers = _activePointers > 0 ? _activePointers - 1 : 0;
            });
            
            // Only finish drawing if no fingers are left
            if (_activePointers == 0) {
              if (drawingProvider.currentTool == ElementType.pen) {
                drawingProvider.endDrawing();
              }
              _lastPosition = null;
            }
          },
          onPointerCancel: (PointerCancelEvent event) {
            setState(() {
              _activePointers = _activePointers > 0 ? _activePointers - 1 : 0;
            });
          },
          child: CustomPaint(
            size: Size.infinite,
            painter: DrawingPainter(
              elements: drawingProvider.elements,
              currentElement: drawingProvider.currentElement,
            ),
            child: Container(
              width: double.infinity, 
              height: double.infinity,
              color: Colors.transparent,
            ),
          ),
        );
      },
    );
  }
}

class DrawingPainter extends CustomPainter {
  final List<DrawingElement> elements;
  final DrawingElement? currentElement;

  DrawingPainter({
    required this.elements,
    this.currentElement,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw all completed elements
    for (final element in elements) {
      element.render(canvas);
    }

    // Draw current element being created
    if (currentElement != null) {
      currentElement!.render(canvas);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}