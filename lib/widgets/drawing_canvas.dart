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

// Add ShadowPainter class before ElementPainter
class ShadowPainter extends CustomPainter {
  final DrawingElement element;
  final Matrix4 currentTransform;
  // Define the light source position (fixed at the top)
  final Offset lightSource = const Offset(0, -5000); // Light is positioned far above the canvas

  ShadowPainter({required this.element, required this.currentTransform});

  @override
  void paint(Canvas canvas, Size size) {
    final Rect bounds = element.bounds;
    if (bounds.isEmpty) return;
    
    final double scale = currentTransform.getMaxScaleOnAxis();
    final double inverseScale = (scale.abs() < 1e-6) ? 1.0 : 1.0 / scale;
    
    // Calculate shadow parameters based on physics
    final Offset elementCenter = bounds.center;
    
    // Direction from light source to element
    final Offset lightDirection = elementCenter - lightSource;
    
    // Normalize the direction vector
    final double lightDistance = lightDirection.distance;
    final Offset normalizedDirection = lightDirection / lightDistance;
    
    // Calculate element "height" based on element type
    // Different elements have different heights above the canvas
    double elementHeight;
    
    // Assign different heights based on element type
    if (element is TextElement) {
      elementHeight = 60 * inverseScale; // Increased height for more visible shadow
    } else if (element is NoteElement) {
      elementHeight = 100 * inverseScale; // Notes are like sticky notes
    } else if (element is ImageElement || element is VideoElement || element is GifElement) {
      elementHeight = 150 * inverseScale; // Media elements float higher
    } else if (element is PenElement) {
      elementHeight = 40 * inverseScale; // Pen strokes are close to canvas
    } else {
      elementHeight = 80 * inverseScale; // Default height
    }
    
    // Calculate shadow length based on element height and light angle
    // The shadow length is proportional to the height and the tangent of the light angle
    final double distanceRatio = lightDistance / 5000;
    final double shadowLength = elementHeight * distanceRatio * 8.0; // Increased multiplier for longer shadows
    
    // Shadow offset is based on normalized direction and shadow length
    final double offsetX = normalizedDirection.dx * shadowLength;
    final double offsetY = normalizedDirection.dy * shadowLength;
    
    // Shadow blur increases with distance from light and height
    // Higher objects cast more diffuse shadows
    final double shadowBlur = 5 * inverseScale * (1 + (elementHeight / 50)) * (1 + (distanceRatio * 0.5)); // Increased base blur
    
    // Shadow opacity decreases with distance (simulating light falloff)
    // and is affected by element type (some are more "transparent")
    double shadowOpacity = 0.6 * (3000 / (lightDistance + 1000)); // Increased base opacity
    
    // Adjust opacity based on element type
    if (element is PenElement) {
      shadowOpacity *= 0.8; // Pen strokes have lighter shadows
    } else if (element is TextElement) {
      shadowOpacity *= 1.0; // Text has clearer shadows
    } else if (element is NoteElement) {
      shadowOpacity *= 1.2; // Notes have stronger shadows
    }
    
    // Cap the opacity to a reasonable range
    shadowOpacity = shadowOpacity.clamp(0.2, 0.7); // Higher min and max opacity
    
    final Paint shadowPaint = Paint()
      ..color = Colors.black.withOpacity(shadowOpacity)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, shadowBlur);
    
    canvas.save();
    
    if (element.rotation != 0) {
      final center = element.bounds.center;
      canvas.translate(center.dx, center.dy);
      canvas.rotate(element.rotation);
      canvas.translate(-center.dx, -center.dy);
    }
    
    // Draw shadow based on element type
    if (element is PenElement) {
      final pen = element as PenElement;
      if (pen.points.length >= 2) {
        // For pen strokes, create a shadow that follows the stroke
        final strokeWidth = pen.strokeWidth;
        
        final Paint penShadowPaint = Paint()
          ..color = Colors.black.withOpacity(shadowOpacity * 1.2) // Increased opacity for pen shadows
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, shadowBlur * 1.2) // More blur for softer shadow
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth * 1.5 * inverseScale // Wider shadow for more visibility
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
          
        final shadowPath = Path();
        
        // Start point with physics-based offset
        final firstPoint = Offset(pen.points.first.dx + offsetX, pen.points.first.dy + offsetY);
        shadowPath.moveTo(firstPoint.dx, firstPoint.dy);
        
        // Connect points with curved paths for smoother shadow
        if (pen.points.length == 2) {
          // Simple line for just two points
          shadowPath.lineTo(pen.points[1].dx + offsetX, pen.points[1].dy + offsetY);
        } else if (pen.points.length == 3) {
          // Use quadratic bezier for 3 points
          final controlPoint = Offset(
            pen.points[1].dx + offsetX,
            pen.points[1].dy + offsetY
          );
          final endPoint = Offset(
            pen.points[2].dx + offsetX,
            pen.points[2].dy + offsetY
          );
          shadowPath.quadraticBezierTo(
            controlPoint.dx, controlPoint.dy,
            endPoint.dx, endPoint.dy
          );
        } else {
          // For many points, use a smooth curve algorithm
          // This creates a more natural shadow for pen strokes
          for (int i = 0; i < pen.points.length - 1; i++) {
            final p0 = (i > 0) ? pen.points[i - 1] : pen.points[0];
            final p1 = pen.points[i];
            final p2 = pen.points[i + 1];
            final p3 = (i < pen.points.length - 2) ? pen.points[i + 2] : p2;
            
            // Calculate control points for a smooth Catmull-Rom spline 
            // (approximated with cubic bezier)
            final double tension = 0.5; // Controls how tight the curve is
            
            final cp1 = Offset(
              p1.dx + (p2.dx - p0.dx) * tension / 6,
              p1.dy + (p2.dy - p0.dy) * tension / 6
            );
            
            final cp2 = Offset(
              p2.dx - (p3.dx - p1.dx) * tension / 6,
              p2.dy - (p3.dy - p1.dy) * tension / 6
            );
            
            // Add physics-based shadow offset
            final shadowP1 = Offset(p1.dx + offsetX, p1.dy + offsetY);
            final shadowP2 = Offset(p2.dx + offsetX, p2.dy + offsetY);
            final shadowCp1 = Offset(cp1.dx + offsetX, cp1.dy + offsetY);
            final shadowCp2 = Offset(cp2.dx + offsetX, cp2.dy + offsetY);
            
            if (i == 0) {
              shadowPath.moveTo(shadowP1.dx, shadowP1.dy);
            }
            
            // Use cubic bezier for smoother curves
            shadowPath.cubicTo(
              shadowCp1.dx, shadowCp1.dy,
              shadowCp2.dx, shadowCp2.dy,
              shadowP2.dx, shadowP2.dy
            );
          }
        }
        
        // Draw the main shadow
        canvas.drawPath(shadowPath, penShadowPaint);
        
        // Draw a second, more concentrated shadow for added depth
        final Paint secondaryShadowPaint = Paint()
          ..color = Colors.black.withOpacity(shadowOpacity * 1.5)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, shadowBlur * 0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth * 0.8 * inverseScale
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
          
        // Calculate a shorter offset for the secondary shadow (closer to the stroke)
        final double secondaryOffsetRatio = 0.6;
        final double secondaryOffsetX = offsetX * secondaryOffsetRatio;
        final double secondaryOffsetY = offsetY * secondaryOffsetRatio;
        
        // Create a secondary shadow path
        final secondaryShadowPath = Path();
        
        // Apply the same path generation logic with a shorter offset
        if (pen.points.length == 2) {
          secondaryShadowPath.moveTo(pen.points.first.dx + secondaryOffsetX, pen.points.first.dy + secondaryOffsetY);
          secondaryShadowPath.lineTo(pen.points[1].dx + secondaryOffsetX, pen.points[1].dy + secondaryOffsetY);
        } else if (pen.points.length == 3) {
          secondaryShadowPath.moveTo(pen.points.first.dx + secondaryOffsetX, pen.points.first.dy + secondaryOffsetY);
          secondaryShadowPath.quadraticBezierTo(
            pen.points[1].dx + secondaryOffsetX, pen.points[1].dy + secondaryOffsetY,
            pen.points[2].dx + secondaryOffsetX, pen.points[2].dy + secondaryOffsetY
          );
        } else {
          // Apply the same smooth curve algorithm for the secondary shadow
          for (int i = 0; i < pen.points.length - 1; i++) {
            final p0 = (i > 0) ? pen.points[i - 1] : pen.points[0];
            final p1 = pen.points[i];
            final p2 = pen.points[i + 1];
            final p3 = (i < pen.points.length - 2) ? pen.points[i + 2] : p2;
            
            final cp1 = Offset(
              p1.dx + (p2.dx - p0.dx) * 0.5 / 6,
              p1.dy + (p2.dy - p0.dy) * 0.5 / 6
            );
            
            final cp2 = Offset(
              p2.dx - (p3.dx - p1.dx) * 0.5 / 6,
              p2.dy - (p3.dy - p1.dy) * 0.5 / 6
            );
            
            final sShadowP1 = Offset(p1.dx + secondaryOffsetX, p1.dy + secondaryOffsetY);
            final sShadowP2 = Offset(p2.dx + secondaryOffsetX, p2.dy + secondaryOffsetY);
            final sShadowCp1 = Offset(cp1.dx + secondaryOffsetX, cp1.dy + secondaryOffsetY);
            final sShadowCp2 = Offset(cp2.dx + secondaryOffsetX, cp2.dy + secondaryOffsetY);
            
            if (i == 0) {
              secondaryShadowPath.moveTo(sShadowP1.dx, sShadowP1.dy);
            }
            
            secondaryShadowPath.cubicTo(
              sShadowCp1.dx, sShadowCp1.dy,
              sShadowCp2.dx, sShadowCp2.dy,
              sShadowP2.dx, sShadowP2.dy
            );
          }
        }
        
        // Draw the secondary shadow
        canvas.drawPath(secondaryShadowPath, secondaryShadowPaint);
      }
    } else {
      // For rectangular elements like TextElement, NoteElement, ImageElement, etc.
      final rect = bounds;
      final radius = element is TextElement || element is NoteElement 
          ? Radius.circular(8 * inverseScale)
          : Radius.circular(4 * inverseScale);
      
      // Create a layered shadow effect for greater depth
      
      // Outer shadow (more diffuse)
      final outerShadowPaint = Paint()
        ..color = Colors.black.withOpacity(shadowOpacity * 0.7)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, shadowBlur * 1.5);
        
      // Middle shadow
      final middleShadowPaint = Paint()
        ..color = Colors.black.withOpacity(shadowOpacity * 0.85)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, shadowBlur * 1.1);
        
      // Inner shadow (sharper)
      final innerShadowPaint = Paint()
        ..color = Colors.black.withOpacity(shadowOpacity * 1.0)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, shadowBlur * 0.7);
      
      // Calculate offset for each shadow layer
      final outerOffset = Offset(offsetX, offsetY);
      final middleOffset = Offset(offsetX * 0.8, offsetY * 0.8);
      final innerOffset = Offset(offsetX * 0.6, offsetY * 0.6);
      
      // Draw shadow with physics-based offset - outer layer
      final outerShadowRect = rect.translate(outerOffset.dx, outerOffset.dy);
      canvas.drawRRect(
        RRect.fromRectAndRadius(outerShadowRect, radius),
        outerShadowPaint
      );
      
      // Middle layer
      final middleShadowRect = rect.translate(middleOffset.dx, middleOffset.dy);
      canvas.drawRRect(
        RRect.fromRectAndRadius(middleShadowRect, radius),
        middleShadowPaint
      );
      
      // Inner layer
      final innerShadowRect = rect.translate(innerOffset.dx, innerOffset.dy);
      canvas.drawRRect(
        RRect.fromRectAndRadius(innerShadowRect, radius),
        innerShadowPaint
      );
    }
    
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant ShadowPainter oldDelegate) {
    return element != oldDelegate.element || 
           currentTransform != oldDelegate.currentTransform;
  }
}

// Add SelectionBorderPainter to handle selection borders
class SelectionBorderPainter extends CustomPainter {
  final DrawingElement element;
  final Matrix4 currentTransform;

  SelectionBorderPainter({required this.element, required this.currentTransform});

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
    
    // Draw selection outline with a clear blue color
    final selectionPaint = Paint()
      ..color = Colors.blue.withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * inverseScale;
    
    if (element is PenElement) {
      final pen = element as PenElement;
      if (pen.points.length >= 2) {
        // Draw selection outline for pen strokes
        final Path path = Path();
        path.moveTo(pen.points.first.dx, pen.points.first.dy);
        
        for (int i = 1; i < pen.points.length; i++) {
          path.lineTo(pen.points[i].dx, pen.points[i].dy);
        }
        
        canvas.drawPath(
          path,
          selectionPaint..strokeWidth = (pen.strokeWidth + 4) * inverseScale
        );
      }
    } else if (element is TextElement || element is NoteElement) {
      // Draw rounded rectangle for text and notes
      final radius = Radius.circular(8 * inverseScale);
      canvas.drawRRect(
        RRect.fromRectAndRadius(bounds, radius),
        selectionPaint
      );
    } else {
      // For other elements
      final radius = Radius.circular(4 * inverseScale);
      canvas.drawRRect(
        RRect.fromRectAndRadius(bounds, radius),
        selectionPaint
      );
    }
    
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant SelectionBorderPainter oldDelegate) {
    return element != oldDelegate.element || currentTransform != oldDelegate.currentTransform;
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

class _DrawingCanvasState extends State<DrawingCanvas> with SingleTickerProviderStateMixin {
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
  static const Duration longPressDuration = Duration(milliseconds: 500); // Regular selection duration
  static const Duration radialMenuDuration = Duration(milliseconds: 1800); // Longer duration for radial menu
  static const double moveCancelThreshold = 10.0; // Threshold to determine if user is moving
  static const double animationScale = 1.05; // Scale factor for selection pop effect
  
  // Physical interaction properties
  static const double elevationAmount = 20.0; // Increased lift amount for more dramatic effect
  bool _isElementElevated = false; // Track if element is currently lifted
  bool _isElementDropping = false; // Track if element is in dropping animation
  
  // Pressure build-up animation properties
  late AnimationController _pressureController;
  Timer? _pressureTimer; // Dedicated timer for pressure animation
  double _pressureThreshold = 0.8; // Increased threshold to make the pop more dramatic
  bool _isPressingElement = false; // Track if element is currently being pressed
  bool _hasPoppedOut = false; // Track if the element has popped out
  int _pressureUpdateCounter = 0; // Counter for pressure updates
  static const int pressureThresholdTime = 450; // Time in ms until pop occurs

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
  void initState() {
    super.initState();
    
    // Initialize pressure animation controller with longer duration
    _pressureController = AnimationController(
      vsync: this, 
      duration: const Duration(milliseconds: pressureThresholdTime),
      value: 0.0,
    );
    
    // Add listener to handle the "pop" when reaching threshold
    _pressureController.addListener(_handlePressureChange);
  }
  
  void _handlePressureChange() {
    // Pop out when we reach the threshold
    if (_pressureController.value >= _pressureThreshold && !_hasPoppedOut && _isPressingElement) {
      setState(() {
        _hasPoppedOut = true;
        _isElementElevated = true;
      });
      
      // Create a dramatic pop effect with a spring animation
      _popEffectAnimation();
      
      // Provide haptic feedback when element pops
      HapticFeedback.mediumImpact();
      print("POPPED OUT at pressure: ${_pressureController.value}, time: ${_pressureUpdateCounter}ms");
    }
  }
  
  // Create a dramatic popping animation with overshoot
  void _popEffectAnimation() {
    if (!mounted || _elementBeingInteractedWith == null) return;
    
    // Animate the controller to slightly overshoot and bounce back
    _pressureController.animateTo(
      1.0, // Full value
      duration: Duration(milliseconds: 300),
      curve: Curves.elasticOut, // Spring effect
    );
  }
  
  void _startPressureBuild(DrawingElement element) {
    // Reset pressure state
    _pressureController.value = 0.0;
    _pressureUpdateCounter = 0;
    _hasPoppedOut = false;
    _isPressingElement = true;
    
    print("Starting pressure build-up animation");
    
    // Cancel any existing timer
    _pressureTimer?.cancel();
    
    // Start incrementing pressure gradually - 16ms is approximately 60fps
    _pressureTimer = Timer.periodic(Duration(milliseconds: 16), (timer) {
      if (!mounted || !_isPressingElement) {
        timer.cancel();
        return;
      }
      
      _pressureUpdateCounter += 16; // Increment by approx time between frames
      
      if (_hasPoppedOut) {
        // If already popped, stop incrementing pressure
        timer.cancel();
        return;
      }
      
      // Calculate pressure based on elapsed time with non-linear curve
      // This will create a slow start, faster middle, then dramatically pop at the end
      double pressureValue = 0.0;
      try {
        // Map time to pressure range with an acceleration curve
        // This creates a more dramatic build-up effect
        final double normalizedTime = _pressureUpdateCounter / pressureThresholdTime;
        
        if (normalizedTime < 0.5) {
          // First half: slow start (quadratic curve)
          pressureValue = 0.3 * math.pow(normalizedTime * 2, 2);
        } else if (normalizedTime < 0.85) {
          // Middle part: linear increase
          pressureValue = 0.3 + 0.3 * ((normalizedTime - 0.5) / 0.35);
        } else {
          // Final rush toward threshold (cubic acceleration)
          final double t = (normalizedTime - 0.85) / 0.15;
          pressureValue = 0.6 + 0.4 * math.pow(t, 1.5);
        }
        
        // Ensure value is within bounds
        pressureValue = pressureValue.clamp(0.0, 1.0);
      } catch (e) {
        print("Error calculating pressure: $e");
        // Fallback to linear calculation
        pressureValue = (_pressureUpdateCounter / pressureThresholdTime).clamp(0.0, 1.0);
      }
      
      if (mounted) {
        setState(() {
          _pressureController.value = pressureValue;
          
          // Debug log
          if (_pressureUpdateCounter % 100 == 0) {
            print("Pressure: ${_pressureController.value}, Time: ${_pressureUpdateCounter}ms");
          }
        });
      } else {
        timer.cancel();
      }
    });
  }
  
  void _stopPressureBuild() {
    _isPressingElement = false;
    _pressureTimer?.cancel();
    _pressureTimer = null;
    _pressureController.value = 0.0;
  }

  @override
  void dispose() { 
    _pressureController.dispose();
    _pressureTimer?.cancel();
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
                      print("Element hit: ${hitElement.runtimeType} - starting interactions");
                      
                      // Set the element being interacted with
                      setState(() {
                        _elementBeingInteractedWith = hitElement;
                        _hasPoppedOut = false;
                        _isPressingElement = true;
                      });
                      
                      // Start building pressure for the pop effect
                      _startPressureBuild(hitElement);
                      print("Started pressure build, current pressure: ${_pressureController.value}");
                      
                      // Regular selection timer (shorter)
                      _longPressTimer = Timer(longPressDuration, () {
                        if (!mounted) return;
                        
                        print("Long press timer fired");
                        
                        setState(() { 
                          _isSelectionInProgress = true;
                        });
                        
                        // Clear current selection if we're in selection mode
                        if (currentTool == ElementType.none) {
                          drawingProvider.clearSelection(notify: false);
                        }
                        
                        // If element hasn't popped yet via pressure, force it now
                        if (!_hasPoppedOut) {
                          print("Element hasn't popped yet, forcing pop");
                          setState(() {
                            _hasPoppedOut = true;
                            _isElementElevated = true;
                          });
                          HapticFeedback.mediumImpact();
                        } else {
                          print("Element already popped out: $_hasPoppedOut");
                        }
                        
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
                
                final Offset currentPosition = event.localPosition;
                final Offset? previousPosition = _activePointerPositions[event.pointer];
                
                // Update the position of this pointer
                _activePointerPositions[event.pointer] = currentPosition;
                
                // If this pointer initiated the radial menu, let the menu handle it
                if (_isRadialMenuShowing && _radialMenuActivePointer == event.pointer) {
                  // Instead of just returning, pass the movement to the radial menu
                  if (_radialMenuOverlay != null) {
                    // Get the global position for the radial menu
                    final RenderBox box = context.findRenderObject() as RenderBox;
                    final Offset globalPosition = box.localToGlobal(currentPosition);
                    // Update radial menu with the new position
                    RadialMenuController.instance.updatePointerPosition(globalPosition);
                  }
                  return;
                }
                
                // Check if user moved finger significantly
                if (previousPosition != null) {
                  final double distance = (currentPosition - previousPosition).distance;
                  
                  // If we're currently building pressure and the pointer moved significantly, cancel the pressure build-up
                  if (_isPressingElement && distance > moveCancelThreshold / 2) {
                    print("Canceling pressure build due to movement: $distance px");
                    _stopPressureBuild();
                  }
                  
                  // If waiting for long press or radial menu, check for movement to cancel
                  if ((_longPressTimer?.isActive ?? false) && distance > moveCancelThreshold) {
                    print("Canceling long press timer due to movement: $distance px");
                    _cancelLongPressTimer();
                  }
                  
                  if ((_radialMenuTimer?.isActive ?? false) && !_isRadialMenuShowing && distance > moveCancelThreshold) {
                    print("Canceling radial menu timer due to movement: $distance px");
                    _cancelRadialMenuTimer();
                  }
                }
                
                // Handle two-finger rotation and scaling specifically
                if (_activePointers == 2 && _isRotatingElement && _elementBeingInteractedWith != null) {
                  if (_activePointerPositions.length == 2 && _initialRotationVector != null && _initialElementSize != null) {
                    // Set elevation state
                    if (!_isElementElevated) {
                      setState(() {
                        _isElementElevated = true;
                      });
                    }
                    
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
                
                final delta = (previousPosition != null) 
                    ? currentPosition - previousPosition 
                    : Offset.zero;
                final currentTool = drawingProvider.currentTool;

                // Check if we're currently drawing with the pen tool
                if (currentTool == ElementType.pen && drawingProvider.currentElement != null) {
                  // If we're already drawing, keep updating the drawing
                  print("✏️ Drawing with pen at ${currentPosition}");
                  drawingProvider.updateDrawing(currentPosition);
                  _cancelLongPressTimer(); // Cancel any pending selection if we're actively drawing
                  _stopPressureBuild(); // Also stop pressure build if we're drawing
                } else if (_isSelectionInProgress || _isMovingElement || _isResizingElement || _isRotatingElement) {
                  // Set elevation state for dragging operations
                  if (!_isElementElevated) {
                    setState(() {
                      _isElementElevated = true;
                      // If we start moving while building pressure, cancel the pressure
                      if (_isPressingElement) {
                        _stopPressureBuild();
                      }
                    });
                  }
                  
                  if (_isRotatingElement && _elementBeingInteractedWith != null && _startRotationAngle != null) {
                    final elementCenter = _elementBeingInteractedWith!.bounds.center;
                    final currentAngle = _calculateAngle(elementCenter, currentPosition);
                    final newRotation = currentAngle - _startRotationAngle!;
                    
                    drawingProvider.rotateSelectedImmediate(_elementBeingInteractedWith!.id, newRotation);
                  } else if (_isResizingElement && _draggedHandle != null && _elementBeingInteractedWith != null) {
                    drawingProvider.resizeSelected(
                      _elementBeingInteractedWith!.id, 
                      _draggedHandle!, 
                      delta, 
                      currentPosition, 
                      _potentialInteractionStartPosition ?? currentPosition
                    );
                  } else if (_isMovingElement && _elementBeingInteractedWith != null) {
                    if (_moveDelayTimer?.isActive ?? false) {
                      _cancelMoveTimer();
                      setState(() {
                        _isMovingElement = true;
                        _isElementElevated = true; // Ensure element is elevated during movement
                        
                        // If we start moving while building pressure, cancel the pressure
                        if (_isPressingElement) {
                          _stopPressureBuild();
                        }
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
                
                _lastInteractionPosition = currentPosition;
              },

              onPointerUp: (PointerUpEvent event) {
                if (!mounted) return;
                
                // Check if currently pressing an element and handle animation
                bool wasPressingElement = _isPressingElement;
                DrawingElement? pressedElement = _isPressingElement ? _elementBeingInteractedWith : null;
                
                // Stop pressure build-up
                _stopPressureBuild();
                
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
                        _isElementElevated = false; // Reset elevation
                      });
                      
                      // Force clear any selection that might have happened
                      drawingProvider.clearSelection();
                    });
                  });
                  return;
                }
                
                // Track element state before we change it
                bool wasElevated = _isElementElevated;
                bool hadPoppedOut = _hasPoppedOut;
                DrawingElement? interactedElement = _elementBeingInteractedWith;
                
                // If element was elevated or popped out, start the drop animation
                if ((wasElevated || hadPoppedOut) && interactedElement != null) {
                  print("Starting drop animation for ${interactedElement.runtimeType}");
                  setState(() { 
                    _isElementElevated = false;
                    _hasPoppedOut = false;
                    _isElementDropping = true;
                  });
                  
                  // Provide haptic feedback for the drop
                  HapticFeedback.lightImpact();
                  
                  // Use a short animation to show the element dropping
                  Future.delayed(Duration(milliseconds: 150), () {
                    if (mounted) {
                      setState(() {
                        _isElementDropping = false;
                        _elementBeingInteractedWith = null;
                      });
                    }
                  });
                } else if (wasPressingElement && pressedElement != null && !hadPoppedOut) {
                  // Element was pressed but never popped - just handle as a tap
                  print("Element was pressed but not popped, handling as tap");
                  setState(() { 
                    _isElementElevated = false;
                    _hasPoppedOut = false;
                  });
                  
                  // Simple selection feedback
                  HapticFeedback.selectionClick();
                  
                  // Select the element briefly then clear selection
                  drawingProvider.selectElement(pressedElement);
                  Future.delayed(Duration(milliseconds: 300), () {
                    drawingProvider.clearSelection();
                  });
                } else {
                  // Not elevated or interacting - just reset state
                  setState(() { 
                    _isElementElevated = false;
                    _hasPoppedOut = false;
                  });
                }
                
                setState(() { 
                  _activePointers--; 
                });
                
                final Offset upPosition = event.localPosition;
                final tapPosition = _potentialInteractionStartPosition ?? upPosition;
                final currentTool = drawingProvider.currentTool;
                bool wasMoving = _isMovingElement; 
                bool wasResizing = _isResizingElement;
                bool wasRotating = _isRotatingElement;
                bool wasSelecting = _isSelectionInProgress;

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
                
                // Stop pressure build-up
                _stopPressureBuild();
                
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
                    
                    // Replace the SelectionPainter with our new ShadowPainter for all elements
                    elementWidgets.add(
                      RepaintBoundary(
                        child: CustomPaint(
                          painter: ShadowPainter(element: element, currentTransform: transform),
                          size: Size.infinite,
                        ),
                      ),
                    );
                    
                    // Add selection border only for selected elements
                    if (isSelected) {
                      elementWidgets.add(
                        RepaintBoundary(
                          child: CustomPaint(
                            painter: SelectionBorderPainter(element: element, currentTransform: transform),
                            size: Size.infinite,
                          ),
                        ),
                      );
                    }
                    
                    // Then add the actual element widget on TOP of the shadow
                    final elementWidget = RepaintBoundary(
                      child: CustomPaint(
                        painter: ElementPainter(element: element, currentTransform: transform),
                        size: Size.infinite,
                      ),
                    );
                    
                    // Apply "pop out" elevation effect when the element is being moved/dragged
                    final bool shouldElevate = element.id == _elementBeingInteractedWith?.id && 
                                              (_isMovingElement || _isResizingElement || _isRotatingElement);
                    
                    // Calculate how much to lift the element
                    final double scale = transform.getMaxScaleOnAxis();
                    final double inverseScale = (scale.abs() < 1e-6) ? 1.0 : 1.0 / scale;
                    final double elevationOffset = shouldElevate ? (elevationAmount * inverseScale) : 0.0;
                    
                    // Check if this element is in the dropping animation
                    final bool isDropping = _isElementDropping && element.id == _elementBeingInteractedWith?.id;
                    
                    // Wrap the element with necessary transforms
                    Widget elevatedElement;
                    bool shouldShowEffects = shouldElevate || shouldAnimate || isDropping;
                    bool isBeingPressed = element.id == _elementBeingInteractedWith?.id && _isPressingElement;
                    
                    if (shouldShowEffects || isBeingPressed) {
                      // Calculate animation values based on state
                      double beginScale = 1.0;
                      double endScale = 1.0;
                      double translateY = 0.0;
                      Curve curve = Curves.easeOutCubic;
                      Duration duration = Duration(milliseconds: 200);
                      
                      if (isDropping) {
                        // Dropping animation
                        beginScale = 1.03;
                        endScale = 1.0;
                        translateY = 0.0;
                        curve = Curves.easeInCubic;
                        duration = Duration(milliseconds: 150);
                      } else if (_hasPoppedOut) {
                        // Popped out state - more dramatic with spring effect
                        beginScale = shouldAnimate ? 1.0 : (shouldElevate ? 0.97 : 1.05);
                        endScale = shouldAnimate ? animationScale : (shouldElevate ? 1.15 : 1.08);
                        translateY = -elevationOffset * 1.3; // Increase elevation for popped state
                        curve = Curves.elasticOut;
                        duration = Duration(milliseconds: 350); // Longer for spring animation
                      } else if (isBeingPressed) {
                        // Being pressed, building pressure - make this more dramatic
                        double pressureValue = _pressureController.value;
                        
                        // Transform pressure value (0.0-1.0) into visual scaling effects
                        // Create a visible build-up before the pop
                        double pressureScale;
                        
                        if (pressureValue < 0.3) {
                          // Initial phase - subtle compression (gets smaller)
                          pressureScale = 1.0 - 0.03 * (pressureValue / 0.3);
                        } else if (pressureValue < 0.6) {
                          // Middle phase - starts expanding slowly
                          double t = (pressureValue - 0.3) / 0.3;
                          pressureScale = 0.97 + 0.05 * t;
                        } else if (pressureValue < _pressureThreshold) {
                          // Pre-pop phase - noticeable pulsing effect
                          double pulsePhase = ((pressureValue - 0.6) / 0.2) * 2 * math.pi;
                          double pulseAmplitude = 0.02;
                          pressureScale = 1.02 + pulseAmplitude * math.sin(pulsePhase);
                        } else {
                          // About to pop
                          pressureScale = 1.05;
                        }
                        
                        beginScale = pressureScale;
                        endScale = pressureScale;
                        
                        // Elevation follows pressure more dramatically
                        translateY = -elevationOffset * math.pow(pressureValue, 2) * 0.4;
                        
                        curve = Curves.easeInCubic;
                        duration = Duration(milliseconds: 16);
                      }
                      
                      elevatedElement = Transform.translate(
                        offset: Offset(0, translateY),
                        child: TweenAnimationBuilder<double>(
                          tween: Tween<double>(begin: beginScale, end: endScale),
                          duration: duration,
                          curve: curve,
                          builder: (context, scale, child) {
                            return Transform.scale(
                              scale: scale,
                              alignment: Alignment.center,
                              child: child,
                            );
                          },
                          child: elementWidget,
                        ),
                      );
                    } else {
                      // No effects - return element as is
                      elevatedElement = elementWidget;
                    }
                    
                    // Debug for pressure animation
                    if (isBeingPressed) {
                      print("Pressure value: ${_pressureController.value}, HasPopped: $_hasPoppedOut");
                    }
                    
                    elementWidgets.add(elevatedElement);
                    
                    return Stack(
                      key: ValueKey('element-${element.id}-$index'),
                      children: elementWidgets
                    );
                  }).toList(),
                  if (currentDrawingElement != null)
                    Stack(
                      children: [
                        // Add shadow to the current drawing element
                        RepaintBoundary(
                          child: CustomPaint(
                            painter: ShadowPainter(element: currentDrawingElement, currentTransform: transform),
                            size: Size.infinite,
                          ),
                        ),
                        // And the actual element on top
                        RepaintBoundary(
                          child: CustomPaint(
                            painter: ElementPainter(element: currentDrawingElement, currentTransform: transform),
                            size: Size.infinite,
                          ),
                        ),
                      ],
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