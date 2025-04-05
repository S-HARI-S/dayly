// lib/widgets/drawing_canvas.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // FIX: Import for listEquals
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:vector_math/vector_math_64.dart' show Matrix4, MatrixUtils;
import 'package:collection/collection.dart'; // FIX: Import for firstWhereOrNull etc.
import 'package:video_player/video_player.dart';

import '../providers/drawing_provider.dart'; // No extension needed here now
import '../models/element.dart';
import '../models/video_element.dart';
import '../models/gif_element.dart'; // Import GIF element
import '../models/handles.dart';

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
  int _activePointers = 0; Timer? _moveDelayTimer; bool _isMovingElement = false;
  Offset? _potentialInteractionStartPosition; Offset? _lastInteractionPosition;
  bool _isResizingElement = false; ResizeHandleType? _draggedHandle;
  DrawingElement? _elementBeingInteractedWith;
  static const Duration longPressDuration = Duration(milliseconds: 200);
  static const double moveCancelThreshold = 10.0;

  // --- Helpers ---
  // _getTransformedCanvasPosition is less critical if using event.localPosition directly
  // within the transformed space. Ensure the Listener is a child of InteractiveViewer's builder.
  // Offset _getTransformedCanvasPosition(Offset globalPosition) {
  // ... (Keep same - uses localPosition directly now) ...
  // }

  void _cancelMoveTimer() { _moveDelayTimer?.cancel(); _moveDelayTimer = null; }
  ResizeHandleType? _hitTestHandles(DrawingElement element, Offset point, double inverseScale) {
    final double handleSize = 8.0 * inverseScale; final double touchPadding = handleSize * 0.5;
    final handles = calculateHandles(element.bounds, handleSize);
    for (var entry in handles.entries) { if (entry.value.inflate(touchPadding).contains(point)) return entry.key; } return null;
  }

  @override
  void dispose() { _cancelMoveTimer(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final drawingProvider = Provider.of<DrawingProvider>(context, listen: false);

    return Selector<DrawingProvider,
        // FIX: Correct tuple field name to match provider field
        ({List<DrawingElement> elements, List<String> selectedElementIds, DrawingElement? current})>(
      selector: (_, provider) => (
        elements: provider.elements,
        selectedElementIds: provider.selectedElementIds, // Use correct field name
        current: provider.currentElement
      ),
      shouldRebuild: (previous, next) => previous.elements != next.elements || !listEquals(previous.selectedElementIds, next.selectedElementIds) || previous.current != next.current, // Use listEquals
      builder: (context, data, child) {
        final currentElements = data.elements;
        // FIX: Access tuple field using correct name
        final selectedIds = data.selectedElementIds; // Use selectedElementIds here
        final currentDrawingElement = data.current;
        final transform = widget.transformationController.value;

        // Get video elements from the list of elements
        final List<VideoElement> videoElements = currentElements
            .whereType<VideoElement>()
            .toList();

        // Get GIF elements from the list of elements
        final List<GifElement> gifElements = currentElements
            .whereType<GifElement>()
            .toList();

        return Stack(
          fit: StackFit.expand,
          children: [
            // The main canvas interaction listener
            Listener(
              onPointerDown: (PointerDownEvent event) {
                if (!mounted) return;
                // Assuming Listener is placed within the transformed space (e.g., child of InteractiveViewer builder)
                final Offset localPosition = event.localPosition;

                _cancelMoveTimer();
                setState(() { _activePointers++; _isMovingElement = false; _isResizingElement = false; _draggedHandle = null; _elementBeingInteractedWith = null; });
                _potentialInteractionStartPosition = localPosition; _lastInteractionPosition = localPosition;
                if (_activePointers > 1 || widget.isInteracting) return;
                HapticFeedback.lightImpact();
                final currentTool = drawingProvider.currentTool;

                if (currentTool == ElementType.select) {
                  bool actionTaken = false;
                  // 1. Hit Handle?
                  if (selectedIds.length == 1) {
                     // FIX: Use firstWhereOrNull from collection package
                     final selectedElement = currentElements.firstWhereOrNull((el) => el.id == selectedIds.first);
                     if (selectedElement != null) {
                       // FIX: Correct scale calculation
                       final double scale = transform.getMaxScaleOnAxis();
                       final double inverseScale = (scale.abs() < 1e-6) ? 1.0 : 1.0 / scale;
                       _draggedHandle = _hitTestHandles(selectedElement, localPosition, inverseScale);
                       if (_draggedHandle != null) {
                         setState(() { _isResizingElement = true; _elementBeingInteractedWith = selectedElement; });
                         drawingProvider.startPotentialResize(); HapticFeedback.mediumImpact();
                         print("Handle HIT: $_draggedHandle on ${selectedElement.id}"); actionTaken = true;
                       }
                     }
                   }
                  // 2. Hit Element Body? (Check last element first for correct hit detection on overlapping elements)
                  if (!actionTaken) {
                    // FIX: Use lastWhereOrNull from collection package
                    DrawingElement? hitElement = currentElements.lastWhereOrNull((el) => el.containsPoint(localPosition));
                    if (hitElement != null) {
                       if (!(selectedIds.length == 1 && selectedIds.first == hitElement.id)) { drawingProvider.selectElementAt(localPosition); }
                       setState(() { _elementBeingInteractedWith = hitElement; });
                       drawingProvider.startPotentialMove(); actionTaken = true;
                       print("Element HIT: ${hitElement.id}. Starting move timer.");
                       _moveDelayTimer = Timer(longPressDuration, () {
                         // FIX: Correct boolean check for null element
                         if (!mounted || _elementBeingInteractedWith == null) return; // Check == null
                         print("** Move Timer Fired! Enabling Drag for ${_elementBeingInteractedWith?.id} **");
                         setState(() { _isMovingElement = true; }); HapticFeedback.mediumImpact();
                       });
                     }
                  }
                  // 3. Tapped Empty Space?
                  if (!actionTaken) { print("Tap empty space - clearing selection."); drawingProvider.clearSelection(); }
                }
                else if (currentTool == ElementType.pen) { drawingProvider.startDrawing(localPosition); } // Pass localPosition
              },

              onPointerMove: (PointerMoveEvent event) {
                if (!mounted || _activePointers != 1 || widget.isInteracting) return;
                final Offset localPosition = event.localPosition; // Use localPosition
                if (_lastInteractionPosition != null && (localPosition - _lastInteractionPosition!).distanceSquared < 0.1) return; // Threshold to reduce unnecessary updates
                final delta = (_lastInteractionPosition != null) ? localPosition - _lastInteractionPosition! : Offset.zero;
                final currentTool = drawingProvider.currentTool;

                if (currentTool == ElementType.select) {
                  if (_isResizingElement && _draggedHandle != null && _elementBeingInteractedWith != null) {
                    drawingProvider.resizeSelected( _elementBeingInteractedWith!.id, _draggedHandle!, delta, localPosition, _potentialInteractionStartPosition ?? localPosition);
                  } else if (_elementBeingInteractedWith != null) {
                    // Cancel move timer if pointer moves beyond threshold before timer fires
                    if (_moveDelayTimer?.isActive ?? false) { if ((localPosition - _potentialInteractionStartPosition!).distance > moveCancelThreshold) { print("Move cancelled before timer fired."); _cancelMoveTimer(); } }
                    // Only move if the timer has fired (_isMovingElement is true)
                    if (_isMovingElement) { drawingProvider.moveSelected(delta); }
                  }
                } else if (currentTool == ElementType.pen) {
                  drawingProvider.updateDrawing(localPosition); // Pass localPosition
                }
                _lastInteractionPosition = localPosition;
              },

              onPointerUp: (PointerUpEvent event) {
                if (!mounted) return;
                _cancelMoveTimer(); // Always cancel timer on up
                final Offset upPosition = event.localPosition; // Use localPosition
                final tapPosition = _potentialInteractionStartPosition ?? upPosition; // Position where interaction started or ended if start is null
                final currentTool = drawingProvider.currentTool;
                bool wasMoving = _isMovingElement; bool wasResizing = _isResizingElement;
                DrawingElement? interactedElement = _elementBeingInteractedWith; // Store before resetting state

                setState(() { _activePointers = _activePointers > 0 ? _activePointers - 1 : 0; _isMovingElement = false; _isResizingElement = false; _draggedHandle = null; _elementBeingInteractedWith = null; });
                _lastInteractionPosition = null; _potentialInteractionStartPosition = null;

                if (_activePointers == 0 && !widget.isInteracting) {
                  if (currentTool == ElementType.select) {
                    if (wasResizing) { print("End Resize"); drawingProvider.endPotentialResize(); }
                    else if (wasMoving) { print("End Move"); drawingProvider.endPotentialMove(); }
                    // Check if it was a tap on an element (not a drag or resize)
                    else if (interactedElement != null) {
                      print("Tap on element: ${interactedElement.id}");
                      // If the tapped element was already selected, consider it a tap action (e.g., toggle video)
                      // If it wasn't selected, the selectElementAt was called on down, so nothing more needed here.
                      if (selectedIds.contains(interactedElement.id)) {
                         if (interactedElement is VideoElement) {
                            drawingProvider.toggleVideoPlayback(interactedElement.id);
                         }
                         // Add other tap actions for other element types if needed
                      }
                    }
                    else { print("Tap on empty space (after potential selection clear on down)."); }
                  }
                  else if (currentTool == ElementType.pen) { drawingProvider.endDrawing(); }
                  else if (currentTool == ElementType.text) { _showTextDialog(context, drawingProvider, tapPosition); } // Pass localPosition (start pos)
                }
              },

              onPointerCancel: (PointerCancelEvent event) {
                 if (!mounted) return; print("Pointer Cancelled");
                 _cancelMoveTimer(); bool wasMoving = _isMovingElement; bool wasResizing = _isResizingElement;
                 // Decide how to handle cancel: discard or finalize based on state
                 if (drawingProvider.currentTool == ElementType.pen && currentDrawingElement != null) { drawingProvider.discardDrawing(); }
                 else if (wasResizing) { drawingProvider.endPotentialResize(); } // Remove unsupported parameter
                 else if (wasMoving) { drawingProvider.endPotentialMove(); } // Remove unsupported parameter
                 // Reset state regardless
                 setState(() { _activePointers = _activePointers > 0 ? _activePointers - 1 : 0; _isMovingElement = false; _isResizingElement = false; _draggedHandle = null; _elementBeingInteractedWith = null; });
                 _lastInteractionPosition = null; _potentialInteractionStartPosition = null;
               },

              behavior: HitTestBehavior.opaque, // Capture all events within bounds
              child: Stack(
                children: [
                  // Background canvas with CustomPaint
                  CustomPaint(
                    painter: DrawingPainter(
                      elements: currentElements,
                      currentElement: currentDrawingElement,
                      selectedIds: selectedIds,
                      currentTransform: transform,
                      excludeVideoContent: true, // Exclude video content from canvas painting
                      excludeGifContent: true,   // Exclude GIF content from canvas painting
                    ),
                    isComplex: selectedIds.isNotEmpty || currentDrawingElement != null, // Hint for optimization
                    willChange: _isMovingElement || _isResizingElement || currentDrawingElement != null, // Hint for optimization
                    size: Size.infinite, // Allow painter to draw anywhere
                    child: Container(color: Colors.transparent), // Needs a child for hit testing
                  ),

                  // ---- START: GIF Rendering ----
                  // Render GIF elements using Image.network widgets positioned in the Stack
                  ...gifElements.map((gifElement) {
                    final bounds = gifElement.bounds;

                    return Positioned(
                      left: bounds.left,
                      top: bounds.top,
                      width: bounds.width,
                      height: bounds.height,
                      child: IgnorePointer( // Ignore pointer events for the GIF itself
                        child: Image.network(
                          gifElement.gifUrl,
                          fit: BoxFit.fill, // Fill the bounds defined by the element
                          // Optional: Add loading builder
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Center(
                              child: CircularProgressIndicator(
                                value: loadingProgress.expectedTotalBytes != null
                                    ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                                    : null,
                              ),
                            );
                          },
                          // Optional: Add error builder (uses preview or placeholder)
                          errorBuilder: (context, error, stackTrace) {
                            return gifElement.previewUrl != null
                                ? Image.network(
                                    gifElement.previewUrl!,
                                    fit: BoxFit.fill,
                                    errorBuilder: (context, error, stackTrace) =>
                                        Container(color: Colors.grey[300], child: const Icon(Icons.broken_image)),
                                  )
                                : Container(color: Colors.grey[300], child: const Icon(Icons.broken_image)); // Placeholder if preview also fails or doesn't exist
                          },
                        ),
                      ),
                    );
                  }).toList(),
                  // ---- END: GIF Rendering ----

                  // Video players integrated directly in the canvas transform space
                  ...videoElements.map((videoElement) {
                    final bounds = videoElement.bounds;

                    // Only render the video if it's initialized
                    if (!videoElement.controller.value.isInitialized) {
                      // Optionally show a placeholder or loading indicator here
                       return Positioned(
                         left: bounds.left, top: bounds.top, width: bounds.width, height: bounds.height,
                         child: Container(color: Colors.black, child: const Center(child: CircularProgressIndicator())),
                       );
                    }

                    return Positioned(
                      left: bounds.left,
                      top: bounds.top,
                      width: bounds.width,
                      height: bounds.height,
                      child: IgnorePointer( // Video should not capture pointer events handled by the Listener
                        child: VideoPlayer(videoElement.controller),
                      ),
                    );
                  }).toList(),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // --- Text Dialog (Keep as before) ---
  void _showTextDialog(BuildContext context, DrawingProvider provider, Offset position) {
    final controller = TextEditingController();
    showDialog( context: context, builder: (context) => AlertDialog( title: const Text("Enter Text"), content: TextField( controller: controller, autofocus: true, decoration: const InputDecoration(hintText: "Type here..."), onSubmitted: (t){ if(t.trim().isNotEmpty){provider.addTextElement(t,position); Navigator.of(context).pop();} }, ), actions: [ TextButton(onPressed:()=>Navigator.of(context).pop(), child: const Text("Cancel")), TextButton(onPressed:(){ if(controller.text.trim().isNotEmpty){provider.addTextElement(controller.text, position); Navigator.of(context).pop();} }, child: const Text("Add")), ], ), );
  }
}


// --- DrawingPainter (Updated to exclude GIFs/Videos) ---
class DrawingPainter extends CustomPainter {
  final List<DrawingElement> elements;
  final DrawingElement? currentElement;
  final List<String> selectedIds; // Name matches the data passed from the builder
  final Matrix4 currentTransform;
  final bool excludeVideoContent;
  final bool excludeGifContent;

  DrawingPainter({
    required this.elements,
    this.currentElement,
    required this.selectedIds, // Use the name passed from the builder
    required this.currentTransform,
    this.excludeVideoContent = false, // Default to false if not passed
    this.excludeGifContent = false,   // Default to false if not passed
  });

  @override
  void paint(Canvas canvas, Size size) {
    // FIX: Correct scale calculation
    final double scale = currentTransform.getMaxScaleOnAxis();
    final double inverseScale = (scale.abs() < 1e-6) ? 1.0 : 1.0 / scale; // Avoid division by zero

    for (final element in elements) {
       // Determine if the element's content should be skipped by this painter
       bool skipContent = (excludeVideoContent && element is VideoElement) ||
                          (excludeGifContent && element is GifElement);

       if (skipContent) {
         // Still draw selection handles/outline if it's selected, even if content is skipped
         if (selectedIds.contains(element.id)) {
           _drawSelectionHandles(canvas, element, inverseScale);
         }
       } else {
         // Render the element normally using its own render method
         element.render(canvas, inverseScale: inverseScale);

         // Draw selection handles if needed AFTER rendering the element
         if (selectedIds.contains(element.id)) {
           _drawSelectionHandles(canvas, element, inverseScale);
         }
       }
    }
    // Draw the element currently being created (e.g., pen stroke) on top
    currentElement?.render(canvas, inverseScale: inverseScale);
  }

  void _drawSelectionHandles(Canvas canvas, DrawingElement element, double inverseScale) {
    // ... (handle drawing logic remains the same) ...
     final Rect bounds = element.bounds; if (bounds.isEmpty) return;
     final double handleSize = 8.0 * inverseScale;
     final double strokeWidth = 1.5 * inverseScale;
     final handlePaintFill = Paint()..color = Colors.white;
     final handlePaintStroke = Paint()..color = Colors.blue..style = PaintingStyle.stroke..strokeWidth = strokeWidth;
     // Draw outline rect
     canvas.drawRect(bounds.inflate(strokeWidth / 2), handlePaintStroke..color = handlePaintStroke.color.withOpacity(0.7)); // Inflate slightly so stroke is outside/on bounds
     // Calculate and draw handles
     final handles = calculateHandles(bounds, handleSize);
     final handlesToDraw = [ ResizeHandleType.topLeft, ResizeHandleType.topRight, ResizeHandleType.bottomLeft, ResizeHandleType.bottomRight, /* Add middle handles if needed */ ];
     // Optional: Only draw corner handles for simplicity or performance
     // final handlesToDraw = [ ResizeHandleType.topLeft, ResizeHandleType.topRight, ResizeHandleType.bottomLeft, ResizeHandleType.bottomRight ];
     for (var handleType in handlesToDraw) { final handleRect = handles[handleType]; if (handleRect != null) { canvas.drawOval(handleRect, handlePaintFill); canvas.drawOval(handleRect, handlePaintStroke); } }
  }

  @override
  bool shouldRepaint(covariant DrawingPainter oldDelegate) {
    // FIX: Use listEquals from foundation.dart (already imported)
    return currentTransform != oldDelegate.currentTransform ||
           !listEquals(selectedIds, oldDelegate.selectedIds) || // Use listEquals for lists
           currentElement != oldDelegate.currentElement ||
           !listEquals(elements, oldDelegate.elements) ||       // Use listEquals for lists
           excludeVideoContent != oldDelegate.excludeVideoContent ||
           excludeGifContent != oldDelegate.excludeGifContent;
  }
}