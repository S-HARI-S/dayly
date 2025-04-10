// lib/widgets/drawing_canvas.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // Import for listEquals
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:vector_math/vector_math_64.dart' show Matrix4, MatrixUtils;
import 'package:collection/collection.dart'; // Import for firstWhereOrNull etc.
import 'package:video_player/video_player.dart';
import 'dart:math' as math;

import '../providers/drawing_provider.dart';
import '../models/element.dart';
import '../models/text_element.dart';
import '../models/video_element.dart';
import '../models/gif_element.dart';
import '../models/handles.dart';
import '../models/pen_element.dart';  // Add missing import for PenElement
import '../models/image_element.dart'; // Add missing import for ImageElement
import '../widgets/bottom_floating_button.dart';
import '../models/note_element.dart'; // Fixed missing quote
import '../widgets/radial_menu.dart'; // Add import for RadialMenu

// Global key to access DrawingCanvas state from outside
final GlobalKey<_DrawingCanvasState> drawingCanvasKey = GlobalKey<_DrawingCanvasState>();

// Add a global method to toggle grid
void toggleCanvasGrid() {
  print("Attempting to toggle grid");
  printDrawingCanvasState();
  if (drawingCanvasKey.currentState != null) {
    print("DrawingCanvas state found, toggling grid");
    drawingCanvasKey.currentState!.toggleGrid();
  } else {
    print("Error: DrawingCanvas state not found");
  }
}

// Helper to debug key state
void printDrawingCanvasState() {
  print("DrawingCanvas key: $drawingCanvasKey");
  print("DrawingCanvas current state: ${drawingCanvasKey.currentState}");
  print("DrawingCanvas current context: ${drawingCanvasKey.currentContext}");
}

// Add GridPainter class to draw the background grid
class GridPainter extends CustomPainter {
  final Matrix4 transform;
  final Color gridColor;
  final double gridSpacing;
  final bool showGrid;
  
  GridPainter({
    required this.transform,
    this.gridColor = Colors.grey,
    this.gridSpacing = 50.0,
    this.showGrid = true,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    if (!showGrid) return;
    
    // Get the scale factor from the transformation matrix
    final double scale = transform.getMaxScaleOnAxis();
    
    // Calculate visible area in the canvas coordinate system
    final Rect visibleRect = MatrixUtils.transformRect(
      transform.clone()..invert(),
      Rect.fromLTWH(0, 0, size.width, size.height),
    );
    
    // Adjust grid spacing based on zoom level for better visibility
    double effectiveSpacing = gridSpacing;
    double primaryLineOpacity = 0.15; // Reduced from 0.3
    double secondaryLineOpacity = 0.07; // Reduced from 0.15
    
    // Make grid spacing dynamic based on zoom level
    if (scale < 0.25) {
      effectiveSpacing = gridSpacing * 8;
      primaryLineOpacity = 0.25; // Reduced from 0.5
      secondaryLineOpacity = 0.0; // No secondary lines at far zoom
    } else if (scale < 0.5) {
      effectiveSpacing = gridSpacing * 4;
      primaryLineOpacity = 0.2; // Reduced from 0.4
      secondaryLineOpacity = 0.0;
    } else if (scale < 1.0) {
      effectiveSpacing = gridSpacing * 2;
      primaryLineOpacity = 0.15; // Reduced from 0.3
      secondaryLineOpacity = 0.05; // Reduced from 0.1
    } else if (scale > 2.0 && scale <= 4.0) {
      effectiveSpacing = gridSpacing / 2;
      primaryLineOpacity = 0.12; // Reduced from 0.25
      secondaryLineOpacity = 0.06; // Reduced from 0.15
    } else if (scale > 4.0) {
      effectiveSpacing = gridSpacing / 4;
      primaryLineOpacity = 0.1; // Reduced from 0.2
      secondaryLineOpacity = 0.05; // Reduced from 0.1
    }
    
    // Calculate grid boundaries
    final double left = (visibleRect.left / effectiveSpacing).floor() * effectiveSpacing;
    final double top = (visibleRect.top / effectiveSpacing).floor() * effectiveSpacing;
    final double right = (visibleRect.right / effectiveSpacing).ceil() * effectiveSpacing;
    final double bottom = (visibleRect.bottom / effectiveSpacing).ceil() * effectiveSpacing;
    
    // Create paints for primary and secondary lines
    final primaryPaint = Paint()
      ..color = gridColor.withOpacity(primaryLineOpacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5; // Reduced from 0.8
      
    final secondaryPaint = Paint()
      ..color = gridColor.withOpacity(secondaryLineOpacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.3; // Reduced from 0.5
    
    // Draw secondary grid lines (finer grid)
    if (secondaryLineOpacity > 0) {
      final secondarySpacing = effectiveSpacing / 5;
      
      for (double x = left; x <= right; x += secondarySpacing) {
        // Skip primary lines
        if (x % effectiveSpacing == 0) continue;
        
        canvas.drawLine(
          Offset(x, top),
          Offset(x, bottom),
          secondaryPaint,
        );
      }
      
      for (double y = top; y <= bottom; y += secondarySpacing) {
        // Skip primary lines
        if (y % effectiveSpacing == 0) continue;
        
        canvas.drawLine(
          Offset(left, y),
          Offset(right, y),
          secondaryPaint,
        );
      }
    }
    
    // Draw primary grid lines
    for (double x = left; x <= right; x += effectiveSpacing) {
      canvas.drawLine(
        Offset(x, top),
        Offset(x, bottom),
        primaryPaint,
      );
    }
    
    for (double y = top; y <= bottom; y += effectiveSpacing) {
      canvas.drawLine(
        Offset(left, y),
        Offset(right, y),
        primaryPaint,
      );
    }
    
    // Draw origin indicators if visible
    final originSize = effectiveSpacing / 5;
    if (visibleRect.contains(Offset.zero)) {
      // Draw X-axis
      canvas.drawLine(
        Offset(-originSize, 0),
        Offset(originSize, 0),
        Paint()
          ..color = Colors.red.withOpacity(0.4) // Reduced from 0.7
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5, // Reduced from 2.0
      );
      
      // Draw Y-axis
      canvas.drawLine(
        Offset(0, -originSize),
        Offset(0, originSize),
        Paint()
          ..color = Colors.green.withOpacity(0.4) // Reduced from 0.7
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5, // Reduced from 2.0
      );
    }
  }
  
  @override
  bool shouldRepaint(covariant GridPainter oldDelegate) {
    return oldDelegate.transform != transform ||
           oldDelegate.gridColor != gridColor ||
           oldDelegate.gridSpacing != gridSpacing ||
           oldDelegate.showGrid != showGrid;
  }
}

class DrawingCanvas extends StatefulWidget {
  final TransformationController transformationController;
  final bool isInteracting;
  
  const DrawingCanvas({
    Key? key,
    required this.transformationController,
    this.isInteracting = false,
  }) : super(key: key);

  @override
  State<DrawingCanvas> createState() {
    print("Creating DrawingCanvas state with key: ${drawingCanvasKey}");
    return _DrawingCanvasState();
  }
}

class _DrawingCanvasState extends State<DrawingCanvas> {
  // --- State & Config ---
  int _activePointers = 0; 
  Timer? _moveDelayTimer; 
  Timer? _longPressTimer; // Add timer for tap-and-hold selection
  Timer? _radialMenuTimer; // Timer specifically for radial menu
  bool _isMovingElement = false;
  Offset? _potentialInteractionStartPosition; 
  Offset? _lastInteractionPosition;
  bool _isResizingElement = false; 
  bool _isRotatingElement = false;
  bool _isSelectionInProgress = false; // Track if we're in selection mode
  ResizeHandleType? _draggedHandle;
  DrawingElement? _elementBeingInteractedWith;
  static const Duration longPressDuration = Duration(milliseconds: 350); // Regular selection duration
  static const Duration radialMenuDuration = Duration(milliseconds: 1000); // Longer duration for radial menu
  static const double moveCancelThreshold = 10.0; // Threshold to determine if user is moving
  static const double animationScale = 1.05; // Scale factor for selection pop effect

  // State for RadialMenu display
  OverlayEntry? _radialMenuOverlay;
  bool _isRadialMenuShowing = false;
  int? _radialMenuActivePointer; // Track which pointer activated the radial menu

  // Add state for toolbar height
  double _toolbarHeight = 0.0;

  // Initial angle for rotation tracking
  double? _startRotationAngle;

  // Add variable to track initial distance between pointers for scaling
  double? _startPointerDistance;

  // Add a variable to track initial vector for stable rotation
  Offset? _initialRotationVector;

  // Add variable to track initial element size for scaling
  Size? _initialElementSize;

  // Track last tap time for double-tap detection
  DateTime? _lastTapTime;
  
  // Add a flag to track whether we're currently using a drawing tool
  bool get _isDrawingToolActive {
    final drawingProvider = Provider.of<DrawingProvider>(context, listen: false);
    return drawingProvider.currentTool != ElementType.select && 
           drawingProvider.currentTool != ElementType.none;
  }

  // Add a flag to toggle grid visibility
  bool _showGrid = true;
  
  // Grid spacing
  double _gridSpacing = 50.0;

  // Add variables to track multiple pointers for rotation
  final Map<int, Offset> _activePointerPositions = {};
  Offset? _rotationReferencePoint;

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

  void _cancelLongPressTimer() {
    _longPressTimer?.cancel();
    _longPressTimer = null;
  }

  void _cancelRadialMenuTimer() {
    _radialMenuTimer?.cancel();
    _radialMenuTimer = null;
  }
  
  ResizeHandleType? _hitTestHandles(DrawingElement element, Offset point, double inverseScale) {
    final double handleSize = 10.0 * inverseScale;
    final double touchPadding = handleSize * 2.0;
    final handles = calculateHandles(element.bounds, handleSize);
    for (var entry in handles.entries) {
      if (entry.value.inflate(touchPadding).contains(point)) return entry.key;
    } 
    return null;
  }

  double _calculateAngle(Offset center, Offset point) {
    return math.atan2(point.dy - center.dy, point.dx - center.dx);
  }

  // Update this helper method to calculate the angle between two vectors
  double _calculateAngleBetweenVectors(Offset vec1, Offset vec2) {
    // Calculate the angle between these vectors using the dot product
    double dotProduct = vec1.dx * vec2.dx + vec1.dy * vec2.dy;
    double vec1Magnitude = math.sqrt(vec1.dx * vec1.dx + vec1.dy * vec1.dy);
    double vec2Magnitude = math.sqrt(vec2.dx * vec2.dx + vec2.dy * vec2.dy);
    
    // Handle division by zero
    if (vec1Magnitude == 0 || vec2Magnitude == 0) return 0;
    
    double cosAngle = dotProduct / (vec1Magnitude * vec2Magnitude);
    // Ensure cosAngle is within valid range for acos
    cosAngle = math.max(-1.0, math.min(1.0, cosAngle));
    
    // Get the angle
    double angle = math.acos(cosAngle);
    
    // Determine rotation direction using cross product (z-component)
    double crossZ = vec1.dx * vec2.dy - vec1.dy * vec2.dx;
    if (crossZ < 0) {
      angle = -angle;
    }
    
    return angle;
  }

  // Method to show the RadialMenu for a selected element
  void _showRadialMenu(BuildContext context, DrawingProvider provider, DrawingElement element, Offset position) {
    // First dismiss any existing menu
    _dismissRadialMenu();

    try {
      print("Creating RadialMenu overlay at position: $position");
      // Create a new overlay entry
      _radialMenuOverlay = OverlayEntry(
        builder: (context) => RadialMenu(
          position: position,
          element: element,
          provider: provider,
          onDismiss: _dismissRadialMenu,
          parentContext: context,
        ),
      );

      // Add the overlay to the current context
      Overlay.of(context).insert(_radialMenuOverlay!);
      _isRadialMenuShowing = true;
      print("RadialMenu overlay inserted successfully");
      
      // Ensure the haptic feedback happens
      HapticFeedback.heavyImpact();
    } catch (e) {
      print("Error showing radial menu: $e");
      // If an error occurs, make sure we don't leave the state hanging
      _dismissRadialMenu();
    }
  }

  // Method to dismiss the RadialMenu
  void _dismissRadialMenu() {
    print("Attempting to dismiss radial menu, isShowing: $_isRadialMenuShowing");
    if (_radialMenuOverlay != null) {
      try {
        _radialMenuOverlay!.remove();
        print("Radial menu dismissed successfully");
      } catch (e) {
        print("Error dismissing radial menu: $e");
      } finally {
        _radialMenuOverlay = null;
        _isRadialMenuShowing = false;
        _radialMenuActivePointer = null;
        
        // Reset active pointers and interaction state to ensure clean state
        _activePointers = 0;
        _activePointerPositions.clear();
        _potentialInteractionStartPosition = null;
        _lastInteractionPosition = null;
        _isMovingElement = false;
        _isResizingElement = false;
        _isRotatingElement = false;
        _isSelectionInProgress = false;
        _elementBeingInteractedWith = null;
      }
    }
  }

  @override
  void dispose() { 
    _cancelMoveTimer();
    _cancelLongPressTimer();
    _cancelRadialMenuTimer();
    _dismissRadialMenu(); // Make sure to dismiss any active radial menu
    super.dispose(); 
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DrawingProvider>(
      builder: (context, drawingProvider, child) {
        final currentDrawingElement = drawingProvider.currentElement;
        final elements = drawingProvider.elements;
        final selectedElementIds = drawingProvider.selectedElementIds;
        final currentTool = drawingProvider.currentTool;
        final transform = widget.transformationController.value;
        
        // Now pass toolbar height to the interactable widget
        return Stack(
          children: [
            // Add CustomPaint to draw the grid
            CustomPaint(
              painter: GridPainter(
                transform: transform,
                gridColor: Colors.grey,
                gridSpacing: _gridSpacing,
                showGrid: _showGrid,
              ),
              child: Container(
                width: double.infinity,
                height: double.infinity,
                color: Colors.transparent,
              ),
            ),
            
            Listener(
              onPointerDown: (PointerDownEvent event) {
                if (!mounted) return;
                // Remove debug message and notification
                
                final Offset localPosition = event.localPosition;

                _cancelMoveTimer();
                _cancelLongPressTimer();
                _cancelRadialMenuTimer();
                
                // Store the pointer position with its unique ID
                _activePointerPositions[event.pointer] = localPosition;
                
                setState(() { 
                  _activePointers++; 
                });
                
                _potentialInteractionStartPosition = localPosition; 
                _lastInteractionPosition = localPosition;
                
                // Check if we have exactly two pointers and an element is selected
                if (_activePointers == 2 && drawingProvider.selectedElementIds.length == 1) {
                  final selectedElementId = drawingProvider.selectedElementIds.first;
                  final selectedElement = elements.firstWhereOrNull(
                    (el) => el.id == selectedElementId
                  );
                  
                  if (selectedElement != null) {
                    // Initialize rotation and scaling mode
                    setState(() {
                      _isMovingElement = false;
                      _isResizingElement = false; 
                      _isRotatingElement = true;
                      _isSelectionInProgress = false;
                      _draggedHandle = null;
                      _elementBeingInteractedWith = selectedElement;
                      
                      // Store initial element size for scaling
                      _initialElementSize = Size(
                        selectedElement.bounds.width, 
                        selectedElement.bounds.height
                      );
                      
                      // Get positions of both pointers
                      final pointerPositions = _activePointerPositions.values.toList();
                      if (pointerPositions.length == 2) {
                        // Store the initial vector between the two points - this is our reference
                        _initialRotationVector = pointerPositions[1] - pointerPositions[0];
                        
                        // Store current rotation as the starting point
                        _startRotationAngle = selectedElement.rotation;
                        
                        // Calculate initial distance between pointers for scaling
                        _startPointerDistance = _initialRotationVector!.distance;
                        
                        // Center of rotation will be the midpoint between the two fingers
                        _rotationReferencePoint = Offset(
                          (pointerPositions[0].dx + pointerPositions[1].dx) / 2,
                          (pointerPositions[0].dy + pointerPositions[1].dy) / 2
                        );
                      }
                    });
                    
                    drawingProvider.startPotentialTransformation();
                    HapticFeedback.mediumImpact();
                    return;
                  }
                } else if (_activePointers == 1) {
                  final currentTool = drawingProvider.currentTool;
                
                  // Check if any handle is being touched
                  if (drawingProvider.selectedElementIds.length == 1 && currentTool == ElementType.none) {
                    final selectedElement = elements.firstWhereOrNull(
                      (el) => el.id == selectedElementIds.first
                    );
                    
                    if (selectedElement != null) {
                      final double scale = transform.getMaxScaleOnAxis();
                      final double inverseScale = (scale.abs() < 1e-6) ? 1.0 : 1.0 / scale;
                      _draggedHandle = _hitTestHandles(selectedElement, localPosition, inverseScale);
                      
                      if (_draggedHandle != null) {
                        setState(() { 
                          if (_draggedHandle == ResizeHandleType.rotate) {
                            _isRotatingElement = true;
                            final elementCenter = selectedElement.bounds.center;
                            _startRotationAngle = _calculateAngle(elementCenter, localPosition) - selectedElement.rotation;
                          } else {
                            _isResizingElement = true;
                          }
                          _elementBeingInteractedWith = selectedElement; 
                        });
                        
                        if (_isRotatingElement) {
                          drawingProvider.startPotentialRotation();
                        } else {
                          drawingProvider.startPotentialResize();
                        }
                        
                        HapticFeedback.mediumImpact();
                        return; // Exit early since we're handling a resize
                      }
                    }
                  }
                  
                  // If not handling resize, check if we're clicking on an element
                  if (currentTool == ElementType.none) {
                    DrawingElement? hitElement = elements.lastWhereOrNull(
                      (el) => el.containsPoint(localPosition)
                    );
                    
                    if (hitElement != null) {
                      // Set the element being interacted with
                      setState(() {
                        _elementBeingInteractedWith = hitElement;
                      });
                      
                      // Regular selection timer (shorter)
                      _longPressTimer = Timer(longPressDuration, () {
                        if (!mounted) return;
                        
                        setState(() { 
                          _isSelectionInProgress = true;
                        });
                        
                        // Clear current selection if we're in selection mode
                        if (currentTool == ElementType.none) {
                          drawingProvider.clearSelection(notify: false);
                        }
                        
                        HapticFeedback.mediumImpact();
                        drawingProvider.selectElement(hitElement);
                        
                        _moveDelayTimer = Timer(Duration(milliseconds: 50), () {
                          if (!mounted || _elementBeingInteractedWith == null) return;
                          
                          setState(() { 
                            _isMovingElement = true; 
                          });
                          
                          drawingProvider.startPotentialMove();
                        });

                        // Give immediate feedback that we're waiting for radial menu
                        HapticFeedback.lightImpact();
                        print("Started waiting for radial menu - will trigger in ${radialMenuDuration.inMilliseconds}ms");
                      });
                      
                      // Radial menu timer (longer) - only start if we're not already moving
                      _radialMenuTimer = Timer(radialMenuDuration, () {
                        print("Radial menu timer fired");
                        // Only show radial menu if user hasn't moved significantly
                        if (!mounted) {
                          print("Not mounted, can't show radial menu");
                          return;
                        }
                        
                        if (_elementBeingInteractedWith == null) {
                          print("No element being interacted with");
                          return;
                        }
                        
                        final currentPosition = _activePointerPositions[event.pointer];
                        if (currentPosition == null) {
                          print("Current position is null");
                          return;
                        }
                        
                        // Check if finger has moved significantly
                        final distance = (currentPosition - localPosition).distance;
                        print("Finger moved distance: $distance (threshold: $moveCancelThreshold)");
                        if (distance > moveCancelThreshold * 2) { // Increased threshold
                          // User has moved - don't show radial menu
                          print("User moved too much, not showing radial menu");
                          return;
                        }
                        
                        // Cancel movement if radial menu is showing
                        _cancelMoveTimer();
                        setState(() { 
                          _isMovingElement = false;
                          _radialMenuActivePointer = event.pointer;
                        });
                        
                        print("About to show radial menu");
                        HapticFeedback.heavyImpact();
                        
                        // Show radial menu at the touch point
                        final RenderBox box = context.findRenderObject() as RenderBox;
                        final Offset globalPosition = box.localToGlobal(localPosition);
                        _showRadialMenu(context, drawingProvider, hitElement, globalPosition);
                      });
                    } else {
                      // Tapped on empty space, clear selection
                      drawingProvider.clearSelection();
                    }
                  } else if (currentTool == ElementType.pen) {
                    // Start drawing immediately
                    drawingProvider.startDrawing(localPosition);
                  } else if (currentTool == ElementType.text) {
                    // Immediately show the text dialog at the tap location
                    _showTextDialog(context, drawingProvider, localPosition);
                    // After text dialog completes, it will reset the tool
                  }
                }
              },

              onPointerMove: (PointerMoveEvent event) {
                if (!mounted) return;
                
                final prevPosition = _activePointerPositions[event.pointer];
                
                // Update the position of this pointer
                _activePointerPositions[event.pointer] = event.localPosition;
                
                // If this pointer initiated the radial menu, let the menu handle it
                if (_isRadialMenuShowing && _radialMenuActivePointer == event.pointer) {
                  // Instead of just returning, pass the movement to the radial menu
                  if (_radialMenuOverlay != null) {
                    // Get the global position for the radial menu
                    final RenderBox box = context.findRenderObject() as RenderBox;
                    final Offset globalPosition = box.localToGlobal(event.localPosition);
                    // Update radial menu with the new position
                    RadialMenuController.instance.updatePointerPosition(globalPosition);
                  }
                  return;
                }
                
                // If user moved finger significantly before radial menu appeared, cancel the radial menu timer
                if (_radialMenuTimer != null && prevPosition != null && !_isRadialMenuShowing) {
                  final distance = (event.localPosition - prevPosition).distance;
                  if (distance > moveCancelThreshold) {
                    print("Canceling radial menu timer due to movement: $distance");
                    _cancelRadialMenuTimer();
                  }
                }
                
                // Handle two-finger rotation and scaling specifically
                if (_activePointers == 2 && _isRotatingElement && _elementBeingInteractedWith != null) {
                  if (_activePointerPositions.length == 2 && _initialRotationVector != null && _initialElementSize != null) {
                    // Get positions of both pointers
                    final pointerPositions = _activePointerPositions.values.toList();
                    
                    // Calculate current vector between the two points
                    final currentVector = pointerPositions[1] - pointerPositions[0];
                    
                    // Calculate the rotation angle as the angle between the initial and current vectors
                    final angleChange = _calculateAngleBetweenVectors(_initialRotationVector!, currentVector);
                    
                    // Apply rotation starting from the element's initial rotation
                    final newRotation = _startRotationAngle! + angleChange;
                    
                    // Update the midpoint for rotation
                    _rotationReferencePoint = Offset(
                      (pointerPositions[0].dx + pointerPositions[1].dx) / 2,
                      (pointerPositions[0].dy + pointerPositions[1].dy) / 2
                    );
                    
                    // Apply the rotation
                    drawingProvider.rotateSelectedImmediate(_elementBeingInteractedWith!.id, newRotation);
                    
                    // Calculate scaling factor based on distance change between pointers
                    if (_startPointerDistance != null && _startPointerDistance! > 0) {
                      final currentDistance = currentVector.distance;
                      final scaleFactor = currentDistance / _startPointerDistance!;
                      
                      // Apply scaling
                      drawingProvider.scaleSelectedImmediate(
                        _elementBeingInteractedWith!.id, 
                        scaleFactor,
                        _initialElementSize!
                      );
                    }
                  }
                  return;
                }
                
                if (_activePointers != 1 || widget.isInteracting) return;
                
                final Offset localPosition = event.localPosition;
                
                final delta = (_lastInteractionPosition != null) 
                    ? localPosition - _lastInteractionPosition! 
                    : Offset.zero;
                final currentTool = drawingProvider.currentTool;

                // Check if we're currently drawing with the pen tool
                if (currentTool == ElementType.pen && drawingProvider.currentElement != null) {
                  // If we're already drawing, keep updating the drawing
                  print("✏️ Drawing with pen at ${localPosition}");
                  drawingProvider.updateDrawing(localPosition);
                  _cancelLongPressTimer(); // Cancel any pending selection if we're actively drawing
                } else if (_longPressTimer?.isActive ?? false) {
                  final movementDistance = (_potentialInteractionStartPosition != null) 
                      ? (localPosition - _potentialInteractionStartPosition!).distance 
                      : 0.0;
                  
                  if (movementDistance > moveCancelThreshold) {
                    _cancelLongPressTimer();
                  }
                } else if (_isSelectionInProgress || _isMovingElement || _isResizingElement || _isRotatingElement) {
                  if (_isRotatingElement && _elementBeingInteractedWith != null && _startRotationAngle != null) {
                    final elementCenter = _elementBeingInteractedWith!.bounds.center;
                    final currentAngle = _calculateAngle(elementCenter, localPosition);
                    final newRotation = currentAngle - _startRotationAngle!;
                    
                    drawingProvider.rotateSelectedImmediate(_elementBeingInteractedWith!.id, newRotation);
                  } else if (_isResizingElement && _draggedHandle != null && _elementBeingInteractedWith != null) {
                    drawingProvider.resizeSelected(
                      _elementBeingInteractedWith!.id, 
                      _draggedHandle!, 
                      delta, 
                      localPosition, 
                      _potentialInteractionStartPosition ?? localPosition
                    );
                  } else if (_isMovingElement && _elementBeingInteractedWith != null) {
                    if (_moveDelayTimer?.isActive ?? false) {
                      _cancelMoveTimer();
                      setState(() {
                        _isMovingElement = true;
                      });
                      drawingProvider.startPotentialMove();
                    }
                    
                    Future.microtask(() {
                      if (mounted) {
                        drawingProvider.moveSelected(delta);
                      }
                    });
                  }
                }
                
                _lastInteractionPosition = localPosition;
              },

              onPointerUp: (PointerUpEvent event) {
                if (!mounted) return;
                
                // Remove the pointer from the active pointers
                _activePointerPositions.remove(event.pointer);
                
                _cancelLongPressTimer(); // Always clear the long-press timer on pointer up
                _cancelMoveTimer(); // Cancel move timer too for safety
                _cancelRadialMenuTimer(); // Cancel radial menu timer
                
                // If this is the pointer that triggered the radial menu, handle selection
                if (_isRadialMenuShowing && _radialMenuActivePointer == event.pointer) {
                  // Get the global position for the radial menu
                  final RenderBox box = context.findRenderObject() as RenderBox;
                  final Offset globalPosition = box.localToGlobal(event.localPosition);
                  
                  // Tell the radial menu to update with the final position
                  RadialMenuController.instance.updatePointerPosition(globalPosition);
                  
                  // Wait a tiny bit for the state to update
                  Future.delayed(Duration(milliseconds: 10), () {
                    // Trigger the selected action
                    print("Triggering radial menu action from pointer up");
                    RadialMenuController.instance.triggerAction();
                    
                    // Wait a bit more before dismissing to ensure the action is processed
                    Future.delayed(Duration(milliseconds: 50), () {
                      _dismissRadialMenu();
                      
                      // Reset element interaction state to prevent selection after radial menu
                      setState(() {
                        _elementBeingInteractedWith = null;
                        _isSelectionInProgress = false;
                      });
                      
                      // Force clear any selection that might have happened
                      drawingProvider.clearSelection();
                    });
                  });
                  return;
                }
                
                setState(() { _activePointers--; });
                
                final Offset upPosition = event.localPosition;
                final tapPosition = _potentialInteractionStartPosition ?? upPosition;
                final currentTool = drawingProvider.currentTool;
                bool wasMoving = _isMovingElement; 
                bool wasResizing = _isResizingElement;
                bool wasRotating = _isRotatingElement;
                bool wasSelecting = _isSelectionInProgress;
                DrawingElement? interactedElement = _elementBeingInteractedWith;

                // If we drop to 0 or 1 pointer while rotating, end the rotation
                if (wasRotating && _activePointers < 2) {
                  // End rotation mode completely
                  setState(() {
                    _isRotatingElement = false;
                    _initialRotationVector = null;
                    _startRotationAngle = null;
                    _rotationReferencePoint = null;
                    _elementBeingInteractedWith = null;
                    _initialElementSize = null;
                  });
                  
                  drawingProvider.endPotentialTransformation();
                  drawingProvider.clearSelection();
                  return; // Exit to prevent further processing
                }
                
                // Specifically check if a pen stroke is active and needs to be finalized
                if (currentTool == ElementType.pen && drawingProvider.currentElement != null) { 
                  drawingProvider.endDrawing(); // This now resets the tool to selection mode
                  return; // Early return to avoid other handlers
                }
                
                // If pointer count drops to zero, end all operations
                if (_activePointers == 0 && !widget.isInteracting) {
                  setState(() {
                    _isMovingElement = false; 
                    _isResizingElement = false;
                    _isSelectionInProgress = false;
                    _draggedHandle = null;
                    _elementBeingInteractedWith = null;
                    _initialRotationVector = null;
                    _startRotationAngle = null;
                    _rotationReferencePoint = null;
                    _initialElementSize = null;
                  });
                  
                  _lastInteractionPosition = null; 
                  _potentialInteractionStartPosition = null;

                  if (wasResizing) { 
                    drawingProvider.endPotentialResize();
                    drawingProvider.clearSelection();
                  } else if (wasMoving) { 
                    drawingProvider.endPotentialMove();
                    drawingProvider.clearSelection();
                  } else if (wasRotating) { 
                    drawingProvider.endPotentialRotation();
                    drawingProvider.clearSelection(); 
                  } else if (interactedElement != null && !wasSelecting) {
                    // Handle interaction with specific element types
                    if (selectedElementIds.contains(interactedElement.id)) {
                      // Handle taps on already selected elements
                      if (interactedElement is VideoElement) {
                        drawingProvider.toggleVideoPlayback(interactedElement.id);
                        drawingProvider.clearSelection();
                      } else if (interactedElement is NoteElement) {
                        final now = DateTime.now();
                        if (_lastTapTime != null && now.difference(_lastTapTime!).inMilliseconds < 500) {
                          _showNoteEditDialog(context, drawingProvider, interactedElement);
                        }
                        _lastTapTime = now;
                        drawingProvider.clearSelection();
                      } else if (interactedElement is TextElement) {
                        _showTextDialog(context, drawingProvider, tapPosition, existingText: interactedElement);
                        drawingProvider.clearSelection();
                      } else {
                        drawingProvider.clearSelection();
                      }
                    } else {
                      // Briefly select the element then clear after a short delay
                      drawingProvider.selectElement(interactedElement);
                      drawingProvider.clearSelection();
                    }
                  }
                }
              },

              onPointerCancel: (PointerCancelEvent event) {
                if (!mounted) return;
                
                // Remove this pointer from tracking
                _activePointerPositions.remove(event.pointer);
                
                _cancelMoveTimer(); 
                _cancelLongPressTimer();
                _cancelRadialMenuTimer();
                
                // If this is the pointer that initiated the radial menu, dismiss it
                if (_radialMenuActivePointer == event.pointer) {
                  _dismissRadialMenu();
                  _radialMenuActivePointer = null;
                }
                
                bool wasMoving = _isMovingElement;
                bool wasResizing = _isResizingElement;
                bool wasRotating = _isRotatingElement;
                
                if (drawingProvider.currentTool == ElementType.pen && currentDrawingElement != null) {
                  drawingProvider.discardDrawing();
                } else if (wasResizing) { 
                  drawingProvider.endPotentialResize();
                  drawingProvider.clearSelection(); // Add immediate clearSelection
                } else if (wasMoving) { 
                  drawingProvider.endPotentialMove();
                  drawingProvider.clearSelection(); // Add immediate clearSelection
                } else if (wasRotating) { 
                  drawingProvider.endPotentialRotation();
                  drawingProvider.clearSelection(); // Add immediate clearSelection
                }
                
                setState(() { 
                  _activePointers = _activePointers > 0 ? _activePointers - 1 : 0; 
                  _isMovingElement = false; 
                  _isResizingElement = false; 
                  _isRotatingElement = false;
                  _isSelectionInProgress = false;
                  _draggedHandle = null; 
                  _elementBeingInteractedWith = null; 
                  _startRotationAngle = null;
                  _rotationReferencePoint = null;
                  _initialRotationVector = null;
                  _initialElementSize = null;
                });
                _lastInteractionPosition = null;
                _potentialInteractionStartPosition = null;
              },
              behavior: HitTestBehavior.translucent,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Remove the colorful border decoration
                  // Container(
                  //   decoration: BoxDecoration(
                  //     border: Border.all(
                  //       color: currentTool == ElementType.pen ? Colors.red : Colors.blue,
                  //       width: 2.0,
                  //     ),
                  //   ),
                  // ),
                  
                  // Existing elements stack
                  ...elements.asMap().entries.map((entry) {
                    final int index = entry.key;
                    final element = entry.value;
                    final isSelected = selectedElementIds.contains(element.id);
                    final shouldAnimate = element.id == _elementBeingInteractedWith?.id && 
                                         (_isResizingElement || _isRotatingElement);
                    
                    final List<Widget> elementWidgets = [];
                    
                    final elementWidget = RepaintBoundary(
                      child: CustomPaint(
                        painter: ElementPainter(element: element, currentTransform: transform),
                        size: Size.infinite,
                      ),
                    );
                    
                    elementWidgets.add(
                      shouldAnimate
                        ? TweenAnimationBuilder<double>(
                            tween: Tween<double>(begin: 1.0, end: animationScale),
                            duration: const Duration(milliseconds: 100),
                            builder: (context, scale, child) {
                              return Transform.scale(
                                scale: scale,
                                alignment: Alignment.center,
                                child: child,
                              );
                            },
                            child: elementWidget,
                          )
                        : elementWidget,
                    );
                    if (isSelected) {
                      elementWidgets.add(
                        RepaintBoundary(
                          child: CustomPaint(
                            painter: SelectionPainter(element: element, currentTransform: transform),
                            size: Size.infinite,
                          ),
                        ),
                      );
                    }
                    return Stack(
                      key: ValueKey('element-${element.id}-$index'),
                      children: elementWidgets
                    );
                  }),
                  if (currentDrawingElement != null)
                     RepaintBoundary(
                       child: CustomPaint(
                          painter: ElementPainter(element: currentDrawingElement, currentTransform: transform),
                          size: Size.infinite,
                       ),
                     ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

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
            leading: Icon(Icons.sticky_note_2, color: Colors.amber),
            title: Text('Add Sticky Note', 
              style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          onTap: () {
            Future.delayed(const Duration(milliseconds: 10), () {
              final center = _getCanvasCenter(provider, context);
              provider.createStickyNote(center);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Sticky note created!'))
              );
            });
          },
        ),
        PopupMenuItem(
          child: const ListTile(
            leading: Icon(Icons.image),
            title: Text('Add Image'),
          ),
          onTap: () {
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
              final center = _getCanvasCenter(provider, context);
              _showTextDialog(context, provider, center);
              // Text dialog will handle tool reset
            });
          },
        ),
      ],
    );
  }

  Offset _getCanvasCenter(DrawingProvider provider, BuildContext context) {
    final Size screenSize = MediaQuery.of(context).size;
    final Offset screenCenter = Offset(screenSize.width / 2, screenSize.height / 2);
    try {
      final Matrix4 inverseMatrix = Matrix4.inverted(widget.transformationController.value);
      return MatrixUtils.transformPoint(inverseMatrix, screenCenter);
    } catch (e) {
      print("Error inverting transformation matrix: $e");
      // Return the center of the screen without transformation instead of extreme values
      return screenCenter;
    }
  }

  void _showTextDialog(BuildContext context, DrawingProvider provider, Offset position, {TextElement? existingText}) {
    final controller = TextEditingController(text: existingText?.text ?? '');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existingText != null ? "Edit Text" : "Enter Text"),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: "Type here..."),
          onSubmitted: (t) {
            if (t.trim().isNotEmpty) {
              // Handle submit via Enter key
              Navigator.of(context).pop();
              if (existingText != null) {
                provider.updateSelectedElementProperties({'text': t});
                provider.clearSelection();
              } else {
                provider.addTextElement(t, position);
              }
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              provider.resetTool(); // Explicitly reset the tool
              provider.clearSelection();
            },
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.of(context).pop(); // Close dialog first to avoid UI issues
                
                if (existingText != null) {
                  provider.updateSelectedElementProperties({'text': controller.text});
                  provider.clearSelection();
                } else {
                  provider.addTextElement(controller.text, position);
                }
              }
            },
            child: Text(existingText != null ? "Update" : "Add"),
          ),
        ],
      ),
    );
  }

  void _showNoteEditDialog(BuildContext context, DrawingProvider provider, NoteElement note) {
    final titleController = TextEditingController(text: note.title);
    final contentController = TextEditingController(text: note.content);
    
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit Note'),
          content: Container(
            width: 300,
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: 'Title',
                    hintText: 'Note title'
                  ),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: TextField(
                    controller: contentController,
                    decoration: const InputDecoration(
                      labelText: 'Content',
                      hintText: 'Note content'
                    ),
                    maxLines: null,
                    keyboardType: TextInputType.multiline,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                provider.updateNoteContent(
                  note.id, 
                  titleController.text,
                  contentController.text
                );
                Navigator.of(context).pop();
                provider.clearSelection();
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  // Public method to toggle grid visibility from outside
  void toggleGrid() {
    setState(() {
      _showGrid = !_showGrid;
    });
    // Provide haptic feedback
    HapticFeedback.mediumImpact();
    
    // Show a brief confirmation message
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_showGrid ? 'Grid enabled' : 'Grid disabled'),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'OK',
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
  }
}

class ElementPainter extends CustomPainter {
  final DrawingElement element;
  final Matrix4 currentTransform;

  ElementPainter({required this.element, required this.currentTransform});

  @override
  void paint(Canvas canvas, Size size) {
    final double scale = currentTransform.getMaxScaleOnAxis();
    final double inverseScale = (scale.abs() < 1e-6) ? 1.0 : 1.0 / scale;
    
    canvas.save();
    
    // Check if the element type internally handles rotation
    bool elementHandlesOwnRotation = element is ImageElement || 
                                    element is VideoElement || 
                                    element is GifElement;
    
    if (element.rotation != 0 && !elementHandlesOwnRotation) {
      // Only apply rotation here if the element doesn't handle its own rotation
      final center = element.bounds.center;
      canvas.translate(center.dx, center.dy);
      canvas.rotate(element.rotation);
      canvas.translate(-center.dx, -center.dy);
    }
    
    // For elements that handle their own rotation, pass a flag to indicate
    // that rotation is already applied at the container level
    element.render(canvas, inverseScale: inverseScale);
    canvas.restore();
  }
  
  @override
  bool shouldRepaint(covariant ElementPainter oldDelegate) {
    return element != oldDelegate.element || currentTransform != oldDelegate.currentTransform;
  }
}

class SelectionPainter extends CustomPainter {
  final DrawingElement element;
  final Matrix4 currentTransform;

  SelectionPainter({required this.element, required this.currentTransform});

  @override
  void paint(Canvas canvas, Size size) {
    final double scale = currentTransform.getMaxScaleOnAxis();
    final double inverseScale = (scale.abs() < 1e-6) ? 1.0 : 1.0 / scale;
    final Rect bounds = element.bounds;
    if (bounds.isEmpty) return;
    
    canvas.save();
    
    if (element.rotation != 0) {
      final center = element.bounds.center;
      canvas.translate(center.dx, center.dy);
      canvas.rotate(element.rotation);
      canvas.translate(-center.dx, -center.dy);
    }
    
    final Paint outlinePaint = Paint()
      ..color = Colors.blue.withOpacity(0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 * inverseScale;
    
    if (element is PenElement) {
      final pen = element as PenElement;
      if (pen.points.length >= 2) {
        final path = Path();
        path.moveTo(pen.points.first.dx, pen.points.first.dy);
        for (int i = 1; i < pen.points.length; i++) {
          path.lineTo(pen.points[i].dx, pen.points[i].dy);
        }
        outlinePaint.strokeWidth = (pen.strokeWidth + 2) * inverseScale;
        canvas.drawPath(path, outlinePaint);
      }
    } else if (element is TextElement || element is NoteElement) {
      final rect = bounds.inflate(1 * inverseScale);
      final radius = Radius.circular(8 * inverseScale);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, radius),
        outlinePaint
      );
    } else if (element is ImageElement || element is VideoElement || element is GifElement) {
      final rect = bounds.inflate(1 * inverseScale);
      final radius = Radius.circular(4 * inverseScale);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, radius),
        outlinePaint
      );
    } else {
      canvas.drawRect(bounds.inflate(1 * inverseScale), outlinePaint);
    }
    
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant SelectionPainter oldDelegate) {
    return element != oldDelegate.element || currentTransform != oldDelegate.currentTransform;
  }
}