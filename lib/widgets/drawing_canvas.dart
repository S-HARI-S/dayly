// lib/widgets/drawing_canvas.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // FIX: Import for listEquals
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:vector_math/vector_math_64.dart' show Matrix4, MatrixUtils;
import 'package:collection/collection.dart'; // FIX: Import for firstWhereOrNull etc.

import '../providers/drawing_provider.dart'; // No extension needed here now
import '../models/element.dart';
import '../models/video_element.dart';
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
  Offset _getTransformedCanvasPosition(Offset globalPosition) {
    // ... (Keep same - uses localPosition directly now) ...
     // This method is now redundant if we use event.localPosition directly below
     // Kept here for reference, but should ideally be removed
     if (!mounted || context.findRenderObject() == null) return Offset.zero;
     final RenderBox renderBox = context.findRenderObject() as RenderBox;
     final Offset localPositionRelativeToWidget = renderBox.globalToLocal(globalPosition);
     try { final Matrix4 inverseMatrix = Matrix4.inverted(widget.transformationController.value); return MatrixUtils.transformPoint(inverseMatrix, localPositionRelativeToWidget); }
     catch (e) { return localPositionRelativeToWidget; }
  }
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

        return Listener(
          onPointerDown: (PointerDownEvent event) {
            if (!mounted) return;
            // Use event.localPosition - assuming Listener is correctly placed within transformed child
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
              // 2. Hit Element Body?
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
            if (_lastInteractionPosition != null && (localPosition - _lastInteractionPosition!).distanceSquared < 0.1) return;
            final delta = (_lastInteractionPosition != null) ? localPosition - _lastInteractionPosition! : Offset.zero;
            final currentTool = drawingProvider.currentTool;

            if (currentTool == ElementType.select) {
              if (_isResizingElement && _draggedHandle != null && _elementBeingInteractedWith != null) {
                 drawingProvider.resizeSelected( _elementBeingInteractedWith!.id, _draggedHandle!, delta, localPosition, _potentialInteractionStartPosition ?? localPosition);
              } else if (_elementBeingInteractedWith != null) {
                 if (_moveDelayTimer?.isActive ?? false) { if ((localPosition - _potentialInteractionStartPosition!).distance > moveCancelThreshold) { _cancelMoveTimer(); } }
                 if (_isMovingElement) { drawingProvider.moveSelected(delta); }
              }
            } else if (currentTool == ElementType.pen) {
              drawingProvider.updateDrawing(localPosition); // Pass localPosition
            }
            _lastInteractionPosition = localPosition;
          },

          onPointerUp: (PointerUpEvent event) {
            if (!mounted) return;
            _cancelMoveTimer();
            final Offset upPosition = event.localPosition; // Use localPosition
            final tapPosition = _potentialInteractionStartPosition ?? upPosition;
            final currentTool = drawingProvider.currentTool;
            bool wasMoving = _isMovingElement; bool wasResizing = _isResizingElement;
            DrawingElement? interactedElement = _elementBeingInteractedWith;

            setState(() { _activePointers = _activePointers > 0 ? _activePointers - 1 : 0; _isMovingElement = false; _isResizingElement = false; _draggedHandle = null; _elementBeingInteractedWith = null; });
            _lastInteractionPosition = null; _potentialInteractionStartPosition = null;

            if (_activePointers == 0 && !widget.isInteracting) {
              if (currentTool == ElementType.select) {
                if (wasResizing) { print("End Resize"); drawingProvider.endPotentialResize(); }
                else if (wasMoving) { print("End Move"); drawingProvider.endPotentialMove(); }
                else if (interactedElement != null) { print("Tap on element: ${interactedElement.id}"); if (interactedElement is VideoElement) { drawingProvider.toggleVideoPlayback(interactedElement.id); } }
                else { print("Tap on empty space."); }
              }
              else if (currentTool == ElementType.pen) { drawingProvider.endDrawing(); }
              else if (currentTool == ElementType.text) { _showTextDialog(context, drawingProvider, tapPosition); } // Pass localPosition (start pos)
            }
          },

          onPointerCancel: (PointerCancelEvent event) {
             if (!mounted) return; print("Pointer Cancelled");
             _cancelMoveTimer(); bool wasMoving = _isMovingElement; bool wasResizing = _isResizingElement;
             if (drawingProvider.currentTool == ElementType.pen && currentDrawingElement != null) { drawingProvider.discardDrawing(); }
             else if (wasResizing) { drawingProvider.endPotentialResize(); }
             else if (wasMoving) { drawingProvider.endPotentialMove(); }
             setState(() { _activePointers = _activePointers > 0 ? _activePointers - 1 : 0; _isMovingElement = false; _isResizingElement = false; _draggedHandle = null; _elementBeingInteractedWith = null; });
             _lastInteractionPosition = null; _potentialInteractionStartPosition = null;
          },

          behavior: HitTestBehavior.opaque,
          child: CustomPaint(
            painter: DrawingPainter(
              elements: currentElements, currentElement: currentDrawingElement,
              selectedIds: selectedIds, // Pass correct field name from tuple data
              currentTransform: transform,
            ),
            isComplex: selectedIds.isNotEmpty || currentDrawingElement != null,
            willChange: _isMovingElement || _isResizingElement || currentDrawingElement != null,
            size: Size.infinite,
            child: Container(color: Colors.transparent),
          ),
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


// --- DrawingPainter (Corrected Again) ---
class DrawingPainter extends CustomPainter {
  final List<DrawingElement> elements;
  final DrawingElement? currentElement;
  // Use the correct field name from the provider/selector data
  final List<String> selectedIds; // Changed from selectedElementIds for consistency IF tuple uses selectedIds
  final Matrix4 currentTransform;

  DrawingPainter({
    required this.elements, this.currentElement,
    required this.selectedIds, // Use the name passed from the builder
    required this.currentTransform,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // FIX: Correct scale calculation
    final double scale = currentTransform.getMaxScaleOnAxis();
    final double inverseScale = (scale.abs() < 1e-6) ? 1.0 : 1.0 / scale;

    for (final element in elements) {
      element.render(canvas, inverseScale: inverseScale);
      // Use the selectedIds list passed to the painter
      if (selectedIds.length == 1 && selectedIds.first == element.id) {
        _drawSelectionHandles(canvas, element, inverseScale);
      }
    }
    currentElement?.render(canvas, inverseScale: inverseScale);
  }

  void _drawSelectionHandles(Canvas canvas, DrawingElement element, double inverseScale) {
    // ... (handle drawing logic remains the same) ...
     final Rect bounds = element.bounds; if (bounds.isEmpty) return;
     final double handleSize = 8.0 * inverseScale;
     final double strokeWidth = 1.5 * inverseScale;
     final handlePaintFill = Paint()..color = Colors.white;
     final handlePaintStroke = Paint()..color = Colors.blue..style = PaintingStyle.stroke..strokeWidth = strokeWidth;
     canvas.drawRect(bounds, handlePaintStroke..color = handlePaintStroke.color.withOpacity(0.7));
     final handles = calculateHandles(bounds, handleSize);
     final handlesToDraw = [ ResizeHandleType.topLeft, ResizeHandleType.topRight, ResizeHandleType.bottomLeft, ResizeHandleType.bottomRight, ResizeHandleType.topMiddle, ResizeHandleType.bottomMiddle, ResizeHandleType.middleLeft, ResizeHandleType.middleRight, ];
     for (var handleType in handlesToDraw) { final handleRect = handles[handleType]; if (handleRect != null) { canvas.drawOval(handleRect, handlePaintFill); canvas.drawOval(handleRect, handlePaintStroke); } }
  }

  @override
  bool shouldRepaint(covariant DrawingPainter oldDelegate) {
    // FIX: Use listEquals from foundation.dart (imported above)
    if (currentTransform != oldDelegate.currentTransform) return true;
    // Compare the selectedIds list passed to this painter instance
    if (!listEquals(selectedIds, oldDelegate.selectedIds)) return true; // Correct
    if (currentElement != oldDelegate.currentElement) return true;
    if (!listEquals(elements, oldDelegate.elements)) return true; // Use listEquals for element list too if refs might not change
    return false;
  }
}