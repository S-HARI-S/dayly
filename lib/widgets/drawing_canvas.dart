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
import '../widgets/context_toolbar.dart';
import '../widgets/bottom_floating_button.dart';
import '../models/note_element.dart'; // Fixed missing quote

class DrawingCanvas extends StatefulWidget {
  final TransformationController transformationController;
  final bool isInteracting;
  
  const DrawingCanvas({
    Key? key,
    required this.transformationController,
    this.isInteracting = false,
  }) : super(key: key);

  @override
  State<DrawingCanvas> createState() => _DrawingCanvasState();
}

class _DrawingCanvasState extends State<DrawingCanvas> {
  // --- State & Config ---
  int _activePointers = 0; 
  Timer? _moveDelayTimer; 
  Timer? _longPressTimer; // Add timer for tap-and-hold selection
  bool _isMovingElement = false;
  Offset? _potentialInteractionStartPosition; 
  Offset? _lastInteractionPosition;
  bool _isResizingElement = false; 
  bool _isRotatingElement = false;
  bool _isSelectionInProgress = false; // Track if we're in selection mode
  ResizeHandleType? _draggedHandle;
  DrawingElement? _elementBeingInteractedWith;
  static const Duration longPressDuration = Duration(milliseconds: 350); // Slightly longer for clearer intent
  static const double moveCancelThreshold = 10.0;
  static const double animationScale = 1.05; // Scale factor for selection pop effect

  // Add state for toolbar height
  double _toolbarHeight = 0.0;

  // Initial angle for rotation tracking
  double? _startRotationAngle;

  // Track last tap time for double-tap detection
  DateTime? _lastTapTime;
  
  // Add a flag to track whether we're currently using a drawing tool
  bool get _isDrawingToolActive {
    final drawingProvider = Provider.of<DrawingProvider>(context, listen: false);
    return drawingProvider.currentTool != ElementType.select && 
           drawingProvider.currentTool != ElementType.none;
  }

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

  // Add a helper method to calculate angle between two points relative to a center point
  double _calculateAngleBetweenPoints(Offset center, Offset point1, Offset point2) {
    // Get vectors from center to each point
    final vec1 = point1 - center;
    final vec2 = point2 - center;
    
    // Calculate the angle between these vectors
    final angle = math.atan2(vec1.dy, vec1.dx) - math.atan2(vec2.dy, vec2.dx);
    
    // Normalize angle to be between 0 and 2π
    return (angle + 2 * math.pi) % (2 * math.pi);
  }

  @override
  void dispose() { 
    _cancelMoveTimer();
    _cancelLongPressTimer();
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
        final elementsChanged = !identical(previous.elements, next.elements) ||
                                !listEquals(previous.elements, next.elements);
        final selectionChanged = !listEquals(previous.selectedElementIds, next.selectedElementIds);
        final currentChanged = previous.current != next.current;
        return elementsChanged || selectionChanged || currentChanged;
      },
      builder: (context, data, child) {
        final currentElements = data.elements;
        final selectedIds = data.selectedElementIds;
        final currentDrawingElement = data.current;
        final transform = widget.transformationController.value;

        return Stack(
          fit: StackFit.expand,
          children: [
            Listener(
              onPointerDown: (PointerDownEvent event) {
                if (!mounted) return;
                final Offset localPosition = event.localPosition;

                _cancelMoveTimer();
                _cancelLongPressTimer();
                
                // Store the pointer position with its unique ID
                _activePointerPositions[event.pointer] = localPosition;
                
                setState(() { 
                  _activePointers++; 
                  _isMovingElement = false; 
                  _isResizingElement = false; 
                  _isRotatingElement = false;
                  _isSelectionInProgress = false;
                  _draggedHandle = null; 
                  _elementBeingInteractedWith = null; 
                  _startRotationAngle = null;
                });
                
                _potentialInteractionStartPosition = localPosition; 
                _lastInteractionPosition = localPosition;
                
                // Check if we have exactly two pointers and an element is selected
                if (_activePointers == 2 && drawingProvider.selectedElementIds.length == 1) {
                  final selectedElementId = drawingProvider.selectedElementIds.first;
                  final selectedElement = currentElements.firstWhereOrNull(
                    (el) => el.id == selectedElementId
                  );
                  
                  if (selectedElement != null) {
                    // Initialize rotation mode
                    setState(() {
                      _isRotatingElement = true;
                      _elementBeingInteractedWith = selectedElement;
                      
                      // Calculate center of the element as the rotation pivot point
                      _rotationReferencePoint = selectedElement.bounds.center;
                      
                      // Get positions of both pointers
                      final pointerPositions = _activePointerPositions.values.toList();
                      if (pointerPositions.length == 2) {
                        // Calculate initial angle between pointers for reference
                        final initialAngle = _calculateAngleBetweenPoints(
                          _rotationReferencePoint!, 
                          pointerPositions[0], 
                          pointerPositions[1]
                        );
                        _startRotationAngle = initialAngle - selectedElement.rotation;
                      }
                    });
                    
                    drawingProvider.startPotentialRotation();
                    HapticFeedback.mediumImpact();
                    return; // Skip other handlers when starting two-finger rotation
                  }
                }
                
                if (_activePointers > 1 || widget.isInteracting) return;
                HapticFeedback.lightImpact();
                
                final currentTool = drawingProvider.currentTool;

                // Direct handling for pen tool to ensure drawing starts immediately
                if (currentTool == ElementType.pen) {
                  // Start drawing immediately
                  drawingProvider.startDrawing(localPosition);
                } else if (currentTool != ElementType.none) {
                  DrawingElement? hitElement = currentElements.lastWhereOrNull(
                    (el) => el.containsPoint(localPosition)
                  );

                  if (hitElement != null) {
                    _longPressTimer = Timer(longPressDuration, () {
                      if (!mounted) return;
                      
                      setState(() { 
                        _isSelectionInProgress = true;
                        _elementBeingInteractedWith = hitElement;
                      });
                      
                      HapticFeedback.mediumImpact();
                      drawingProvider.selectElement(hitElement);
                      drawingProvider.showContextToolbar = true;
                      
                      _moveDelayTimer = Timer(Duration(milliseconds: 50), () {
                        if (!mounted || _elementBeingInteractedWith == null) return;
                        
                        setState(() { 
                          _isMovingElement = true; 
                        });
                        
                        drawingProvider.startPotentialMove();
                      });
                    });
                  } else if (currentTool == ElementType.text) {
                    _showTextDialog(context, drawingProvider, localPosition);
                  }
                } else {
                  bool actionTaken = false;
                  
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
                        actionTaken = true;
                      }
                    }
                  }
                  
                  if (!actionTaken) {
                    DrawingElement? hitElement = currentElements.lastWhereOrNull(
                      (el) => el.containsPoint(localPosition)
                    );
                    
                    if (hitElement != null) {
                      setState(() {
                        _elementBeingInteractedWith = hitElement;
                      });
                      
                      _longPressTimer = Timer(longPressDuration, () {
                        if (!mounted || _elementBeingInteractedWith == null) return;
                        
                        setState(() { 
                          _isSelectionInProgress = true;
                        });
                        
                        drawingProvider.clearSelection(notify: false);
                        drawingProvider.selectElement(hitElement);
                        drawingProvider.showContextToolbar = true;
                        
                        HapticFeedback.mediumImpact(); 
                        
                        _moveDelayTimer = Timer(Duration(milliseconds: 50), () {
                          if (!mounted || _elementBeingInteractedWith == null) return;
                          
                          setState(() { 
                            _isMovingElement = true; 
                          });
                          
                          drawingProvider.startPotentialMove();
                        });
                      });
                      
                      actionTaken = true;
                    }
                  }
                  
                  if (!actionTaken) {
                    drawingProvider.clearSelection();
                    drawingProvider.showContextToolbar = false;
                  }
                }
              },

              onPointerMove: (PointerMoveEvent event) {
                if (!mounted) return;
                
                // Update the position of this pointer
                _activePointerPositions[event.pointer] = event.localPosition;
                
                // Handle two-finger rotation specifically
                if (_activePointers == 2 && _isRotatingElement && _elementBeingInteractedWith != null) {
                  final pointerPositions = _activePointerPositions.values.toList();
                  if (pointerPositions.length == 2 && _rotationReferencePoint != null && _startRotationAngle != null) {
                    // Calculate current angle between the two pointers relative to element center
                    final currentAngle = _calculateAngleBetweenPoints(
                      _rotationReferencePoint!, 
                      pointerPositions[0], 
                      pointerPositions[1]
                    );
                    
                    // Calculate and apply the rotation
                    final newRotation = currentAngle - _startRotationAngle!;
                    drawingProvider.rotateSelectedImmediate(_elementBeingInteractedWith!.id, newRotation);
                  }
                  return; // Skip other handlers when doing two-finger rotation
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
                
                // Remove this pointer from our tracking map
                _activePointerPositions.remove(event.pointer);
                
                _cancelMoveTimer();
                _cancelLongPressTimer();
                
                final Offset upPosition = event.localPosition;
                final tapPosition = _potentialInteractionStartPosition ?? upPosition;
                final currentTool = drawingProvider.currentTool;
                bool wasMoving = _isMovingElement; 
                bool wasResizing = _isResizingElement;
                bool wasRotating = _isRotatingElement;
                bool wasSelecting = _isSelectionInProgress;
                DrawingElement? interactedElement = _elementBeingInteractedWith;

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
                });
                
                _lastInteractionPosition = null; 
                _potentialInteractionStartPosition = null;

                // If pointer count drops to zero, end the current operation
                if (_activePointers == 0 && !widget.isInteracting) {
                  // Specifically check if a pen stroke is active and needs to be finalized
                  if (currentTool == ElementType.pen && drawingProvider.currentElement != null) { 
                    drawingProvider.endDrawing();
                    return; // Early return to avoid other handlers
                  }
                  
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
                    if (selectedIds.contains(interactedElement.id)) {
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
                      drawingProvider.selectElement(interactedElement);
                      drawingProvider.showContextToolbar = true;
                      Future.delayed(Duration(milliseconds: 100), () {
                        drawingProvider.clearSelection();
                      });
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
                bool wasMoving = _isMovingElement;
                bool wasResizing = _isResizingElement;
                bool wasRotating = _isRotatingElement;
                if (drawingProvider.currentTool == ElementType.pen && currentDrawingElement != null) {
                  drawingProvider.discardDrawing();
                } else if (wasResizing) { 
                  drawingProvider.endPotentialResize(); 
                } else if (wasMoving) { 
                  drawingProvider.endPotentialMove(); 
                } else if (wasRotating) { 
                  drawingProvider.endPotentialRotation();
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
                });
                _lastInteractionPosition = null;
                _potentialInteractionStartPosition = null;
              },
              behavior: HitTestBehavior.opaque,
              child: Stack(
                children: [
                  ...List.generate(currentElements.length, (index) {
                    final element = currentElements[index];
                    final bool isSelected = selectedIds.contains(element.id);
                    final bool isBeingInteracted = _elementBeingInteractedWith?.id == element.id;
                    final bool shouldAnimate = isSelected && isBeingInteracted && _isSelectionInProgress;
                    List<Widget> elementWidgets = [];
                    Widget elementWidget;
                    if (element is GifElement) {
                      final bounds = element.bounds;
                      elementWidget = Positioned(
                        left: bounds.left,
                        top: bounds.top,
                        width: bounds.width,
                        height: bounds.height,
                        child: Transform.rotate(
                          angle: element.rotation,
                          child: Image.network(
                            element.gifUrl,
                            fit: BoxFit.cover,
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return Container(
                                color: Colors.grey.withOpacity(0.3),
                                child: Center(
                                  child: CircularProgressIndicator(
                                    value: loadingProgress.expectedTotalBytes != null
                                        ? loadingProgress.cumulativeBytesLoaded / 
                                            loadingProgress.expectedTotalBytes!
                                        : null,
                                  ),
                                ),
                              );
                            },
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                color: Colors.grey.withOpacity(0.3),
                                child: const Center(
                                  child: Text("Error loading GIF", 
                                    style: TextStyle(color: Colors.red)),
                                ),
                              );
                            },
                          ),
                        ),
                      );
                    } else if (element is VideoElement) {
                      final bounds = element.bounds;
                      if (!element.controller.value.isInitialized) {
                        elementWidget = Positioned(
                          left: bounds.left,
                          top: bounds.top,
                          width: bounds.width,
                          height: bounds.height,
                          child: Container(
                              color: Colors.black,
                              child: const Center(child: CircularProgressIndicator())),
                        );
                      } else {
                        elementWidget = Positioned(
                          left: bounds.left,
                          top: bounds.top,
                          width: bounds.width,
                          height: bounds.height,
                          child: IgnorePointer(
                            child: VideoPlayer(element.controller),
                          ),
                        );
                      }
                    } else {
                      elementWidget = RepaintBoundary(
                        child: CustomPaint(
                          painter: ElementPainter(element: element, currentTransform: transform),
                          size: Size.infinite,
                        ),
                      );
                    }
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
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Material(
                type: MaterialType.transparency,
                child: Consumer<DrawingProvider>(
                  builder: (context, provider, _) {
                    final isVisible = provider.showContextToolbar;
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
            Consumer<DrawingProvider>(
              builder: (context, provider, _) {
                final toolbarOffset = provider.showContextToolbar ? _toolbarHeight : 0.0;
                return BottomFloatingButton(
                  bottomOffset: toolbarOffset,
                  onPressed: () {
                    _showAddElementMenu(context);
                  },
                  child: const Icon(Icons.add),
                );
              },
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
      return const Offset(50000, 50000);
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
              if (existingText != null) {
                provider.updateSelectedElementProperties({'text': t});
                provider.clearSelection();
              } else {
                provider.addTextElement(t, position);
              }
              Navigator.of(context).pop();
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              provider.resetTool();
              provider.clearSelection();
            },
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                if (existingText != null) {
                  provider.updateSelectedElementProperties({'text': controller.text});
                  provider.clearSelection();
                } else {
                  provider.addTextElement(controller.text, position);
                }
                Navigator.of(context).pop();
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
    
    if (element.rotation != 0) {
      final center = element.bounds.center;
      canvas.translate(center.dx, center.dy);
      canvas.rotate(element.rotation);
      canvas.translate(-center.dx, -center.dy);
    }
    
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