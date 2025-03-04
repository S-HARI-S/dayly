import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/drawing_provider.dart';
import '../models/element.dart';

class DrawingCanvas extends StatefulWidget {
  final bool isPanning;
  const DrawingCanvas({super.key, this.isPanning = false});

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
          onPointerDown: (PointerDownEvent event) {
            setState(() {
              _activePointers++;
            });

            if (_activePointers == 1 && !widget.isPanning) {
              if (drawingProvider.currentTool == ElementType.pen) {
                drawingProvider.startDrawing(event.localPosition);
              } else if (drawingProvider.currentTool == ElementType.text) {
                // Open a dialog for text input
                showDialog(
                  context: context,
                  builder: (context) {
                    final controller = TextEditingController();
                    return AlertDialog(
                      title: const Text("Enter Text"),
                      content: TextField(
                        controller: controller,
                        decoration: const InputDecoration(
                          hintText: "Type your text here",
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () {
                            // Call the provider method to add a text element
                            drawingProvider.addTextElement(
                              controller.text,
                              event.localPosition,
                            );
                            Navigator.of(context).pop();
                          },
                          child: const Text("Add"),
                        ),
                      ],
                    );
                  },
                );
              } else {
                drawingProvider.selectElementAt(event.localPosition);
                _lastPosition = event.localPosition;
              }
            }
          },

          onPointerMove: (PointerMoveEvent event) {
            // Only update drawing if exactly one finger is active and not panning
            if (_activePointers == 1 && !widget.isPanning) {
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

            // Only finish drawing if no fingers are left and not panning
            if (_activePointers == 0 && !widget.isPanning) {
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

  DrawingPainter({required this.elements, this.currentElement});

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
