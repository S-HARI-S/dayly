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
import '../models/video_element.dart';
import '../models/gif_element.dart';
import '../models/handles.dart';
import '../widgets/context_toolbar.dart';
import '../widgets/bottom_floating_button.dart';
import '../models/note_element.dart'; // Add missing import for NoteElement

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
  bool _isMovingElement = false;
  Offset? _potentialInteractionStartPosition; 
  Offset? _lastInteractionPosition;
  bool _isResizingElement = false; 
  bool _isRotatingElement = false; // Add state for rotation
  ResizeHandleType? _draggedHandle;
  DrawingElement? _elementBeingInteractedWith;
  static const Duration longPressDuration = Duration(milliseconds: 200);
  static const double moveCancelThreshold = 10.0;

  // Add state for toolbar height
  double _toolbarHeight = 0.0;

  // Initial angle for rotation tracking
  double? _startRotationAngle;

  // Track last tap time for double-tap detection
  DateTime? _lastTapTime;
  
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
    // Increase the base handle size for better visibility
    final double handleSize = 10.0 * inverseScale;
    
    // Increase the touch padding significantly to make handles easier to grab
    // This creates a larger invisible touch area around each handle
    final double touchPadding = handleSize * 2.0;
    
    final handles = calculateHandles(element.bounds, handleSize);
    for (var entry in handles.entries) {
      if (entry.value.inflate(touchPadding).contains(point)) return entry.key;
    } 
    return null;
  }

  // Helper method to calculate angle between two points relative to center
  double _calculateAngle(Offset center, Offset point) {
    return math.atan2(point.dy - center.dy, point.dx - center.dx);
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
                  _isRotatingElement = false; // Reset rotation state
                  _draggedHandle = null; 
                  _elementBeingInteractedWith = null; 
                  _startRotationAngle = null; // Reset rotation angle
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
                          if (_draggedHandle == ResizeHandleType.rotate) {
                            _isRotatingElement = true;
                            // Store initial rotation angle between element center and pointer
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
                      drawingProvider.showContextToolbar = true;
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
                
                // Remove this check to ensure we process ALL movement events
                // This was causing the jankiness by skipping updates when pointer barely moved
                
                final delta = (_lastInteractionPosition != null) 
                    ? localPosition - _lastInteractionPosition! 
                    : Offset.zero;
                final currentTool = drawingProvider.currentTool;

                if (currentTool == ElementType.select) {
                  // Handle rotation
                  if (_isRotatingElement && _elementBeingInteractedWith != null && _startRotationAngle != null) {
                    final elementCenter = _elementBeingInteractedWith!.bounds.center;
                    final currentAngle = _calculateAngle(elementCenter, localPosition);
                    final newRotation = currentAngle - _startRotationAngle!;
                    
                    // IMPORTANT: Use direct update instead of Future.microtask
                    // Use rotateSelectedImmediate instead of rotateSelected for immediate visual feedback
                    // This ensures bounding box and element rotation stay in sync
                    drawingProvider.rotateSelectedImmediate(_elementBeingInteractedWith!.id, newRotation);
                  }
                  // Handle other interactions (resizing, moving)
                  else if (_isResizingElement && _draggedHandle != null && _elementBeingInteractedWith != null) {
                    drawingProvider.resizeSelected(
                      _elementBeingInteractedWith!.id, 
                      _draggedHandle!, 
                      delta, 
                      localPosition, 
                      _potentialInteractionStartPosition ?? localPosition
                    );
                  } 
                  // Handle moving
                  else if (_elementBeingInteractedWith != null) {
                    // Cancel move timer if pointer moves beyond threshold before timer fires
                    if (_moveDelayTimer?.isActive ?? false) { 
                      if ((localPosition - _potentialInteractionStartPosition!).distance > moveCancelThreshold) { 
                        print("Move cancelled before timer fired."); 
                        _cancelMoveTimer(); 
                        
                        // IMMEDIATE ENABLE MOVE! Don't wait for the timer (faster response)
                        setState(() { 
                          _isMovingElement = true; 
                        });
                        HapticFeedback.lightImpact();
                      }
                    }
                    // Only move if the timer has fired (_isMovingElement is true)
                    if (_isMovingElement) {
                      // IMPORTANT: Use microtask to ensure move happens on next frame
                      // This helps avoid the UI thread being blocked during drag operations
                      Future.microtask(() {
                        if (mounted) {
                          drawingProvider.moveSelected(delta);
                        }
                      });
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
                bool wasRotating = _isRotatingElement; // Track rotation state
                DrawingElement? interactedElement = _elementBeingInteractedWith;

                setState(() { 
                  _activePointers = _activePointers > 0 ? _activePointers - 1 : 0; 
                  _isMovingElement = false; 
                  _isResizingElement = false; 
                  _isRotatingElement = false; // Reset rotation flag
                  _draggedHandle = null; 
                  _elementBeingInteractedWith = null;
                  _startRotationAngle = null; // Reset rotation angle
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
                    else if (wasRotating) { 
                      print("End Rotation"); 
                      drawingProvider.endPotentialRotation(); 
                    }
                    // Check if it was a tap on an element (not a drag or resize)
                    else if (interactedElement != null) {
                      print("Tap on element: ${interactedElement.id}");
                      // If the tapped element was already selected, consider it a tap action
                      if (selectedIds.contains(interactedElement.id)) {
                         if (interactedElement is VideoElement) {
                            drawingProvider.toggleVideoPlayback(interactedElement.id);
                         } else if (interactedElement is NoteElement) {
                            // Check for double-tap by measuring time since last tap
                            final now = DateTime.now();
                            if (_lastTapTime != null && 
                                now.difference(_lastTapTime!).inMilliseconds < 500) {
                              // Show edit dialog on double tap
                              _showNoteEditDialog(context, drawingProvider, interactedElement);
                            }
                            _lastTapTime = now;
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
                bool wasRotating = _isRotatingElement; // Track rotation state
                
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
                else if (wasRotating) { 
                  drawingProvider.endPotentialRotation();
                }
                
                // Reset state regardless
                setState(() { 
                  _activePointers = _activePointers > 0 ? _activePointers - 1 : 0; 
                  _isMovingElement = false; 
                  _isResizingElement = false; 
                  _isRotatingElement = false; // Reset rotation flag
                  _draggedHandle = null; 
                  _elementBeingInteractedWith = null; 
                  _startRotationAngle = null; // Reset rotation angle
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
                    print("  Rendering Index $index: \\${element.id} (\\${element.type})");
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
                                print("Error loading GIF: $error");
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
                        RepaintBoundary(
                          child: CustomPaint(
                            painter: ElementPainter(element: element, currentTransform: transform),
                            size: Size.infinite, 
                          ),
                        ),
                      );
                    }
                    // 2. Render selection handles on top if selected
                    if (selectedIds.contains(element.id)) {
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
                  // Current drawing element (e.g., pen stroke) always on top during creation
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
        // Make the sticky note option more prominent by placing it at the top
        PopupMenuItem(
          child: const ListTile(
            leading: Icon(Icons.sticky_note_2, color: Colors.amber),
            title: Text('Add Sticky Note', 
              style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          onTap: () {
            Future.delayed(const Duration(milliseconds: 10), () {
              // Get the canvas center position
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

  // Note Edit Dialog implementation
  void _showNoteEditDialog(BuildContext context, DrawingProvider provider, NoteElement note) {
    final titleController = TextEditingController(text: note.title);
    final contentController = TextEditingController(text: note.content);
    
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit Note'),
          content: SizedBox(
            width: 300,
            height: 250,
            child: Column(
              mainAxisSize: MainAxisSize.min,
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
                Expanded(
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
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }
}

// --- ElementPainter ---
class ElementPainter extends CustomPainter {
  final DrawingElement element;
  final Matrix4 currentTransform;

  ElementPainter({required this.element, required this.currentTransform});

  @override
  void paint(Canvas canvas, Size size) {
    final double scale = currentTransform.getMaxScaleOnAxis();
    final double inverseScale = (scale.abs() < 1e-6) ? 1.0 : 1.0 / scale;
    
    // Save the current canvas state
    canvas.save();
    
    // If the element has rotation, apply it
    if (element.rotation != 0) {
      // Rotate around the center of the element's bounds
      final center = element.bounds.center;
      canvas.translate(center.dx, center.dy);
      canvas.rotate(element.rotation);
      canvas.translate(-center.dx, -center.dy);
    }
    
    // Render the element
    element.render(canvas, inverseScale: inverseScale);
    
    // Restore the canvas to its original state
    canvas.restore();    
  }
  
  @override
  bool shouldRepaint(covariant ElementPainter oldDelegate) {
    // Repaint if element or transform changes
    return element != oldDelegate.element || currentTransform != oldDelegate.currentTransform;
  }
} 

// --- SelectionPainter ---
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
    
    // Draw selection rectangle without rotation first
    final Paint selectionPaint = Paint()
      ..color = Colors.blue.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 * inverseScale;
    
    // If the element has rotation, apply it
    if (element.rotation != 0) {
      // Rotate around the center of the element's bounds
      final center = element.bounds.center;
      canvas.translate(center.dx, center.dy);
      canvas.rotate(element.rotation);
      canvas.translate(-center.dx, -center.dy);
    }
    
    // Draw the selection box
    canvas.drawRect(bounds.inflate(1.5 * inverseScale), selectionPaint);
    
    // Draw selection handles (these should not be rotated with the element)
    _drawSelectionHandles(canvas, element, inverseScale);
    
    // Restore canvas state before drawing rotation handle
    canvas.restore();
    
    // Now draw rotation handle (which shouldn't be rotated)
    _drawRotationHandle(canvas, element, inverseScale);
  }

  void _drawSelectionHandles(Canvas canvas, DrawingElement element, double inverseScale) {
    final Rect bounds = element.bounds;
    if (bounds.isEmpty) return;

    // Increase the base handle size for better visibility
    final double handleSize = 12.0 * inverseScale;
    
    // Create a more visible handle style
    final handlePaintFill = Paint()..color = Colors.white;
    final handlePaintStroke = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0 * inverseScale; // Thicker stroke for better visibility

    // Calculate and draw handles
    final handles = calculateHandles(bounds, handleSize);
    
    // Draw each handle with a larger touch target
    for (var entry in handles.entries) {
      if (entry.key == ResizeHandleType.rotate) continue; // Skip rotation handle
      
      final handleRect = entry.value;
      
      // Draw a larger invisible touch area (for hit testing)
      final touchArea = handleRect.inflate(handleSize);
      
      // Draw the visible handle
      canvas.drawRect(handleRect, handlePaintFill);
      canvas.drawRect(handleRect, handlePaintStroke);
    }
  }

  void _drawRotationHandle(Canvas canvas, DrawingElement element, double inverseScale) {
    final Rect bounds = element.bounds;
    if (bounds.isEmpty) return;

    // Make rotation handle larger and more visible
    final double handleSize = 14.0 * inverseScale;
    
    // Create a distinct style for the rotation handle
    final handlePaintFill = Paint()..color = Colors.white;
    final handlePaintStroke = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0 * inverseScale;
    
    // Calculate rotation handle position
    final handles = calculateHandles(bounds, handleSize);
    final rotateHandle = handles[ResizeHandleType.rotate];
    if (rotateHandle == null) return;
    
    // Draw a larger invisible touch area for the rotation handle
    final touchArea = rotateHandle.inflate(handleSize);
    
    // Draw the visible rotation handle
    canvas.drawRect(rotateHandle, handlePaintFill);
    canvas.drawRect(rotateHandle, handlePaintStroke);
    
    // Add a rotation indicator arrow
    final center = rotateHandle.center;
    final arrowPaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0 * inverseScale;
    
    // Draw a circular arrow around the handle
    final arrowRadius = handleSize * 0.8;
    canvas.drawArc(
      Rect.fromCenter(center: center, width: arrowRadius * 2, height: arrowRadius * 2),
      -math.pi / 4, // Start at -45 degrees
      math.pi * 1.5, // Draw 270 degrees
      false,
      arrowPaint
    );
  }

  @override
  bool shouldRepaint(covariant SelectionPainter oldDelegate) {
    // Repaint if element or transform changes
    return element != oldDelegate.element || currentTransform != oldDelegate.currentTransform;
  }
}