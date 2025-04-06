// lib/widgets/drawing_canvas.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // Import for listEquals
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:vector_math/vector_math_64.dart' show Matrix4, MatrixUtils;
import 'package:collection/collection.dart'; // Import for firstWhereOrNull etc.
import 'package:video_player/video_player.dart';

import '../providers/drawing_provider.dart';
import '../models/element.dart';
import '../models/video_element.dart';
import '../models/gif_element.dart';
import '../models/handles.dart';
import '../widgets/context_toolbar.dart';
import '../widgets/bottom_floating_button.dart';

class DrawingCanvas extends StatefulWidget {
  final TransformationController transformationController;
  final bool isInteracting;

  const DrawingCanvas({
    super.key,
    required this.transformationController,
    required this.isInteracting,
  });

  @override
  State<DrawingCanvas> createState() => _DrawingCanvasState();
}

class _DrawingCanvasState extends State<DrawingCanvas> {
  // --- State & Config ---
  int _activePointers = 0; 
  Timer? _moveDelayTimer; 
  bool _isMovingElement = false;
  Offset? _potentialInteractionStartPosition; 
  Offset? _lastInteractionPosition;
  bool _isResizingElement = false; 
  ResizeHandleType? _draggedHandle;
  DrawingElement? _elementBeingInteractedWith;
  static const Duration longPressDuration = Duration(milliseconds: 200);
  static const double moveCancelThreshold = 10.0;

  // Add state for toolbar height
  double _toolbarHeight = 0.0;

  // Helper method to get transformed canvas position
  Offset _getTransformedCanvasPosition(Offset globalPosition) {
    final RenderBox box = context.findRenderObject() as RenderBox;
    final Matrix4 transform = widget.transformationController.value.clone();
    final Offset localPosition = box.globalToLocal(globalPosition);
    return MatrixUtils.transformPoint(transform, localPosition);
  }

  void _cancelMoveTimer() { 
    _moveDelayTimer?.cancel(); 
    _moveDelayTimer = null; 
  }
  
  ResizeHandleType? _hitTestHandles(DrawingElement element, Offset point, double inverseScale) {
    final double handleSize = 8.0 * inverseScale;
    final double touchPadding = handleSize * 0.5;
    final handles = calculateHandles(element.bounds, handleSize);
    for (var entry in handles.entries) {
      if (entry.value.inflate(touchPadding).contains(point)) return entry.key;
    } 
    return null;
  }

  @override
  void dispose() { 
    _cancelMoveTimer();
    super.dispose(); 
  }

  @override
  Widget build(BuildContext context) {
    final drawingProvider = Provider.of<DrawingProvider>(context, listen: false);

    return Selector<DrawingProvider,
        ({List<DrawingElement> elements, List<String> selectedElementIds, DrawingElement? current})>(
      selector: (_, provider) => (
        elements: provider.elements,
        selectedElementIds: provider.selectedElementIds,
        current: provider.currentElement
      ),
      shouldRebuild: (previous, next) {
        // More robust check: rebuild if list instance changes OR content/order changes
        final elementsChanged = !identical(previous.elements, next.elements) ||
                                !listEquals(previous.elements, next.elements);
        final selectionChanged = !listEquals(previous.selectedElementIds, next.selectedElementIds);
        final currentChanged = previous.current != next.current;
        // Optional: Log which part changed
        // if (elementsChanged) print("Canvas rebuild: elements changed");
        // if (selectionChanged) print("Canvas rebuild: selection changed");
        // if (currentChanged) print("Canvas rebuild: current element changed");
        return elementsChanged || selectionChanged || currentChanged;
      },
      builder: (context, data, child) {
        final currentElements = data.elements;
        final selectedIds = data.selectedElementIds;
        final currentDrawingElement = data.current;
        final transform = widget.transformationController.value;

        // --- Add Logging Here ---
        print("--- DrawingCanvas Rendering (${currentElements.length} elements) ---");
        // --- End Logging ---

        return Stack(
          fit: StackFit.expand,
          children: [
            // The main canvas interaction listener
            Listener(
              onPointerDown: (PointerDownEvent event) {
                if (!mounted) return;
                final Offset localPosition = event.localPosition;

                _cancelMoveTimer();
                setState(() { 
                  _activePointers++; 
                  _isMovingElement = false; 
                  _isResizingElement = false; 
                  _draggedHandle = null; 
                  _elementBeingInteractedWith = null; 
                });
                
                _potentialInteractionStartPosition = localPosition; 
                _lastInteractionPosition = localPosition;
                
                if (_activePointers > 1 || widget.isInteracting) return;
                HapticFeedback.lightImpact();
                final currentTool = drawingProvider.currentTool;

                if (currentTool == ElementType.select) {
                  bool actionTaken = false;
                  // 1. Hit Handle?
                  if (selectedIds.length == 1) {
                    final selectedElement = currentElements.firstWhereOrNull(
                      (el) => el.id == selectedIds.first
                    );
                    if (selectedElement != null) {
                      final double scale = transform.getMaxScaleOnAxis();
                      final double inverseScale = (scale.abs() < 1e-6) ? 1.0 : 1.0 / scale;
                      _draggedHandle = _hitTestHandles(selectedElement, localPosition, inverseScale);
                      if (_draggedHandle != null) {
                        setState(() { 
                          _isResizingElement = true;
                          _elementBeingInteractedWith = selectedElement; 
                        });
                        drawingProvider.startPotentialResize(); 
                        HapticFeedback.mediumImpact();
                        print("Handle HIT: $_draggedHandle on ${selectedElement.id}"); 
                        actionTaken = true;
                      }
                    }
                  }
                  
                  // 2. Hit Element Body?
                  if (!actionTaken) {
                    DrawingElement? hitElement = currentElements.lastWhereOrNull(
                      (el) => el.containsPoint(localPosition)
                    );
                    if (hitElement != null) {
                      // Always show toolbar when element is hit
                      drawingProvider.showContextToolbarForElement(hitElement.id);
                      
                      // Now handle selection
                      if (!(selectedIds.length == 1 && selectedIds.first == hitElement.id)) {
                        drawingProvider.selectElementAt(localPosition);
                      } else {
                        // Force notify even if selection didn't change to ensure toolbar shows
                        drawingProvider.notifyListeners();
                      }
                      
                      setState(() { 
                        _elementBeingInteractedWith = hitElement;
                      });
                      drawingProvider.startPotentialMove(); 
                      actionTaken = true;
                      print("Element HIT: ${hitElement.id}. Showing toolbar.");
                      
                      // Continue with move timer
                      _moveDelayTimer = Timer(longPressDuration, () {
                        if (!mounted || _elementBeingInteractedWith == null) return;
                        print("** Move Timer Fired! Enabling Drag for ${_elementBeingInteractedWith?.id} **");
                        setState(() { 
                          _isMovingElement = true; 
                        }); 
                        HapticFeedback.mediumImpact();
                      });
                    }
                  }
                  
                  // 3. Tapped Empty Space?
                  if (!actionTaken) {
                    print("Tap empty space - clearing selection.");
                    drawingProvider.clearSelection();
                    // Explicitly hide toolbar when tapping empty space
                    drawingProvider.showContextToolbar = false;
                  }
                }
                else if (currentTool == ElementType.pen) { 
                  drawingProvider.startDrawing(localPosition);
                }
              },

              onPointerMove: (PointerMoveEvent event) {
                if (!mounted || _activePointers != 1 || widget.isInteracting) return;
                final Offset localPosition = event.localPosition;
                
                if (_lastInteractionPosition != null && 
                    (localPosition - _lastInteractionPosition!).distanceSquared < 0.1) return;
                
                final delta = (_lastInteractionPosition != null) 
                    ? localPosition - _lastInteractionPosition! 
                    : Offset.zero;
                final currentTool = drawingProvider.currentTool;

                if (currentTool == ElementType.select) {
                  if (_isResizingElement && _draggedHandle != null && _elementBeingInteractedWith != null) {
                    drawingProvider.resizeSelected(
                      _elementBeingInteractedWith!.id, 
                      _draggedHandle!, 
                      delta, 
                      localPosition, 
                      _potentialInteractionStartPosition ?? localPosition
                    );
                  } else if (_elementBeingInteractedWith != null) {
                    // Cancel move timer if pointer moves beyond threshold before timer fires
                    if (_moveDelayTimer?.isActive ?? false) { 
                      if ((localPosition - _potentialInteractionStartPosition!).distance > moveCancelThreshold) { 
                        print("Move cancelled before timer fired."); 
                        _cancelMoveTimer(); 
                      }
                    }
                    // Only move if the timer has fired (_isMovingElement is true)
                    if (_isMovingElement) { 
                      drawingProvider.moveSelected(delta);
                    }
                  }
                } else if (currentTool == ElementType.pen) {
                  drawingProvider.updateDrawing(localPosition);
                }
                _lastInteractionPosition = localPosition;
              },

              onPointerUp: (PointerUpEvent event) {
                if (!mounted) return;
                _cancelMoveTimer(); // Always cancel timer on up
                final Offset upPosition = event.localPosition;
                final tapPosition = _potentialInteractionStartPosition ?? upPosition;
                final currentTool = drawingProvider.currentTool;
                bool wasMoving = _isMovingElement; 
                bool wasResizing = _isResizingElement;
                DrawingElement? interactedElement = _elementBeingInteractedWith;

                setState(() { 
                  _activePointers = _activePointers > 0 ? _activePointers - 1 : 0; 
                  _isMovingElement = false; 
                  _isResizingElement = false; 
                  _draggedHandle = null; 
                  _elementBeingInteractedWith = null; 
                });
                _lastInteractionPosition = null; 
                _potentialInteractionStartPosition = null;

                if (_activePointers == 0 && !widget.isInteracting) {
                  if (currentTool == ElementType.select) {
                    if (wasResizing) { 
                      print("End Resize"); 
                      drawingProvider.endPotentialResize(); 
                    }
                    else if (wasMoving) { 
                      print("End Move"); 
                      drawingProvider.endPotentialMove(); 
                    }
                    // Check if it was a tap on an element (not a drag or resize)
                    else if (interactedElement != null) {
                      print("Tap on element: ${interactedElement.id}");
                      // If the tapped element was already selected, consider it a tap action (e.g., toggle video)
                      if (selectedIds.contains(interactedElement.id)) {
                         if (interactedElement is VideoElement) {
                            drawingProvider.toggleVideoPlayback(interactedElement.id);
                         }
                         // Add other tap actions for other element types if needed
                      }
                    }
                    else { 
                      print("Tap on empty space (after potential selection clear on down).");
                    }
                  }
                  else if (currentTool == ElementType.pen) { 
                    drawingProvider.endDrawing(); 
                  }
                  else if (currentTool == ElementType.text) { 
                    _showTextDialog(context, drawingProvider, tapPosition);
                  }
                }
              },

              onPointerCancel: (PointerCancelEvent event) {
                 if (!mounted) return; 
                 print("Pointer Cancelled");
                 _cancelMoveTimer(); 
                 bool wasMoving = _isMovingElement;
                 bool wasResizing = _isResizingElement;
                 
                 // Decide how to handle cancel: discard or finalize based on state
                 if (drawingProvider.currentTool == ElementType.pen && currentDrawingElement != null) {
                    drawingProvider.discardDrawing();
                 }
                 else if (wasResizing) { 
                    drawingProvider.endPotentialResize();
                 }
                 else if (wasMoving) { 
                    drawingProvider.endPotentialMove();
                 }
                 
                 // Reset state regardless
                 setState(() { 
                   _activePointers = _activePointers > 0 ? _activePointers - 1 : 0; 
                   _isMovingElement = false; 
                   _isResizingElement = false; 
                   _draggedHandle = null; 
                   _elementBeingInteractedWith = null; 
                 });
                 _lastInteractionPosition = null;
                 _potentialInteractionStartPosition = null;
               },

              behavior: HitTestBehavior.opaque, // Capture all events within bounds
              child: Stack(
                children: [
                  // Render elements individually. Lower index = bottom layer.
                  ...List.generate(currentElements.length, (index) {
                    final element = currentElements[index];
                    // --- Add Logging Here ---
                    print("  Rendering Index $index: ${element.id} (${element.type})");
                    // --- End Logging ---

                    List<Widget> elementWidgets = [];

                    // 1. Render the element content
                    if (element is GifElement) {
                      final bounds = element.bounds;
                      elementWidgets.add(
                        Positioned(
                          left: bounds.left,
                          top: bounds.top,
                          width: bounds.width,
                          height: bounds.height,
                          child: IgnorePointer(
                            child: Image.network(
                              element.gifUrl,
                              fit: BoxFit.fill,
                              loadingBuilder: (context, child, loadingProgress) {
                                if (loadingProgress == null) return child;
                                return Center(
                                  child: CircularProgressIndicator(
                                    value: loadingProgress.expectedTotalBytes != null
                                        ? loadingProgress.cumulativeBytesLoaded /
                                            loadingProgress.expectedTotalBytes!
                                        : null,
                                  ),
                                );
                              },
                              errorBuilder: (context, error, stackTrace) {
                                return element.previewUrl != null
                                    ? Image.network(
                                        element.previewUrl!,
                                        fit: BoxFit.fill,
                                        errorBuilder: (_, __, ___) => Container(
                                            color: Colors.grey[300],
                                            child: const Icon(Icons.broken_image)),
                                      )
                                    : Container(
                                        color: Colors.grey[300],
                                        child: const Icon(Icons.broken_image));
                              },
                            ),
                          ),
                        ),
                      );
                    } else if (element is VideoElement) {
                      final bounds = element.bounds;
                      if (!element.controller.value.isInitialized) {
                        elementWidgets.add(
                          Positioned(
                            left: bounds.left,
                            top: bounds.top,
                            width: bounds.width,
                            height: bounds.height,
                            child: Container(
                                color: Colors.black,
                                child: const Center(child: CircularProgressIndicator())),
                          ),
                        );
                      } else {
                        elementWidgets.add(
                          Positioned(
                            left: bounds.left,
                            top: bounds.top,
                            width: bounds.width,
                            height: bounds.height,
                            child: IgnorePointer(
                              child: VideoPlayer(element.controller),
                            ),
                          ),
                        );
                      }
                    } else {
                      // Use CustomPaint for other types (Pen, Text, Image)
                      elementWidgets.add(
                        CustomPaint(
                          painter: ElementPainter(element: element, currentTransform: transform),
                          size: Size.infinite, 
                          // Optimization: repaint only if element changes?
                          // isComplex: true, 
                          // willChange: true, 
                        )
                      );
                    }

                     // 2. Render selection handles on top if selected
                    if (selectedIds.contains(element.id)) {
                      elementWidgets.add(
                         CustomPaint(
                           painter: SelectionPainter(element: element, currentTransform: transform),
                           size: Size.infinite,
                         )
                      );
                    }

                    return Stack(
                      // Use a key that includes the index to ensure rebuild on order change
                      key: ValueKey('element-${element.id}-$index'),
                      children: elementWidgets
                    ); // Return a Stack containing element + optional handles
                  }),

                  // Current drawing element (e.g., pen stroke) always on top during creation
                  if (currentDrawingElement != null)
                     CustomPaint(
                        painter: ElementPainter(element: currentDrawingElement, currentTransform: transform),
                        size: Size.infinite,
                     ),

                ],
              ),
            ),

            // Make sure the toolbar is on top and properly positioned
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Material(
                type: MaterialType.transparency,
                child: Consumer<DrawingProvider>(
                  builder: (context, provider, _) {
                    final isVisible = provider.showContextToolbar;
                    print("Rendering toolbar with visibility: $isVisible");
                    
                    // Check if there are any selected elements
                    if (provider.selectedElementIds.isEmpty) {
                      print("No selected elements for toolbar");
                    } else {
                      print("Selected elements: ${provider.selectedElementIds}");
                    }
                    
                    return ContextToolbar(
                      key: const ValueKey('contextToolbar'),
                      isVisible: isVisible,
                      onHeightChanged: (height) {
                        if (mounted) {
                          setState(() {
                            _toolbarHeight = height;
                          });
                        }
                      },
                    );
                  },
                ),
              ),
            ),

            // Add the "+" button with animation based on toolbar height
            Consumer<DrawingProvider>(
              builder: (context, provider, _) {
                // Calculate bottom offset based on toolbar visibility
                final toolbarOffset = provider.showContextToolbar ? _toolbarHeight : 0.0;
                
                return BottomFloatingButton(
                  bottomOffset: toolbarOffset,
                  onPressed: () {
                    // Show a menu for creating new elements
                    _showAddElementMenu(context);
                  },
                  child: const Icon(Icons.add),
                );
              },
            ),

            // Debug overlay - REMOVE IN PRODUCTION
            if (false) // Set to false to disable the debug overlay
              Positioned(
                top: 100,
                right: 20,
                child: Consumer<DrawingProvider>(
                  builder: (context, provider, _) {
                    return Container(
                      padding: const EdgeInsets.all(8),
                      color: Colors.black.withOpacity(0.5),
                      child: Text(
                        "Toolbar visible: ${provider.showContextToolbar}\n"
                        "Selected: ${provider.selectedElementIds.length}\n"
                        "Height: $_toolbarHeight",
                        style: const TextStyle(color: Colors.white),
                      ),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  // Method to show a menu for adding new elements
  void _showAddElementMenu(BuildContext context) {
    final provider = Provider.of<DrawingProvider>(context, listen: false);
    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(const Offset(0, 0), ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );

    showMenu(
      context: context,
      position: position,
      items: [
        PopupMenuItem(
          child: const ListTile(
            leading: Icon(Icons.image),
            title: Text('Add Image'),
          ),
          onTap: () {
            // Add slight delay to allow menu to close
            Future.delayed(const Duration(milliseconds: 10), () {
              provider.addImageFromGallery(context, widget.transformationController);
            });
          },
        ),
        PopupMenuItem(
          child: const ListTile(
            leading: Icon(Icons.videocam),
            title: Text('Add Video'),
          ),
          onTap: () {
            Future.delayed(const Duration(milliseconds: 10), () {
              provider.addVideoFromGallery(context, widget.transformationController);
            });
          },
        ),
        PopupMenuItem(
          child: const ListTile(
            leading: Icon(Icons.gif_box),
            title: Text('Add GIF'),
          ),
          onTap: () {
            Future.delayed(const Duration(milliseconds: 10), () {
              provider.searchAndAddGif(context, widget.transformationController);
            });
          },
        ),
        PopupMenuItem(
          child: const ListTile(
            leading: Icon(Icons.text_fields),
            title: Text('Add Text'),
          ),
          onTap: () {
            Future.delayed(const Duration(milliseconds: 10), () {
              provider.setTool(ElementType.text);
              // Focus on center of screen for text input
              final center = _getCanvasCenter(provider, context);
              _showTextDialog(context, provider, center);
            });
          },
        ),
      ],
    );
  }

  // Helper method to get canvas center
  Offset _getCanvasCenter(DrawingProvider provider, BuildContext context) {
    final Size screenSize = MediaQuery.of(context).size;
    final Offset screenCenter = Offset(screenSize.width / 2, screenSize.height / 2);
    try {
      final Matrix4 inverseMatrix = Matrix4.inverted(widget.transformationController.value);
      return MatrixUtils.transformPoint(inverseMatrix, screenCenter);
    } catch (e) {
      return const Offset(50000, 50000); // Default center if transformation fails
    }
  }

  // Text Dialog implementation
  void _showTextDialog(BuildContext context, DrawingProvider provider, Offset position) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Enter Text"),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: "Type here..."),
          onSubmitted: (t) {
            if (t.trim().isNotEmpty) {
              provider.addTextElement(t, position);
              Navigator.of(context).pop();
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                provider.addTextElement(controller.text, position);
                Navigator.of(context).pop();
              }
            },
            child: const Text("Add"),
          ),
        ],
      ),
    );
  }
}

// --- NEW: ElementPainter ---
class ElementPainter extends CustomPainter {
  final DrawingElement element;
  final Matrix4 currentTransform;

  ElementPainter({required this.element, required this.currentTransform});

  @override
  void paint(Canvas canvas, Size size) {
    final double scale = currentTransform.getMaxScaleOnAxis();
    final double inverseScale = (scale.abs() < 1e-6) ? 1.0 : 1.0 / scale;
    element.render(canvas, inverseScale: inverseScale);
  }

  @override
  bool shouldRepaint(covariant ElementPainter oldDelegate) {
    // Repaint if element or transform changes
    return element != oldDelegate.element || currentTransform != oldDelegate.currentTransform;
  }
}

// --- NEW: SelectionPainter ---
class SelectionPainter extends CustomPainter {
  final DrawingElement element;
  final Matrix4 currentTransform;

  SelectionPainter({required this.element, required this.currentTransform});

  @override
  void paint(Canvas canvas, Size size) {
      final double scale = currentTransform.getMaxScaleOnAxis();
      final double inverseScale = (scale.abs() < 1e-6) ? 1.0 : 1.0 / scale;
      _drawSelectionHandles(canvas, element, inverseScale);
  }

  void _drawSelectionHandles(Canvas canvas, DrawingElement element, double inverseScale) {
    final Rect bounds = element.bounds;
    if (bounds.isEmpty) return;

    final double handleSize = 8.0 * inverseScale;
    final double strokeWidth = 1.5 * inverseScale;
    final handlePaintFill = Paint()..color = Colors.white;
    final handlePaintStroke = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    // Draw outline rect
    canvas.drawRect(
      bounds.inflate(strokeWidth / 2),
      handlePaintStroke..color = handlePaintStroke.color.withOpacity(0.7)
    );

    // Calculate and draw handles
    final handles = calculateHandles(bounds, handleSize);
    // Draw only corner handles for simplicity now, can add edge handles later
    final handlesToDraw = [
      ResizeHandleType.topLeft,
      ResizeHandleType.topRight,
      ResizeHandleType.bottomLeft,
      ResizeHandleType.bottomRight,
    ];

    for (var handleType in handlesToDraw) {
      final handleRect = handles[handleType];
      if (handleRect != null) {
        canvas.drawOval(handleRect, handlePaintFill);
        canvas.drawOval(handleRect, handlePaintStroke);
      }
    }
  }

  @override
  bool shouldRepaint(covariant SelectionPainter oldDelegate) {
     // Repaint if element or transform changes
     return element != oldDelegate.element || currentTransform != oldDelegate.currentTransform;
  }

}