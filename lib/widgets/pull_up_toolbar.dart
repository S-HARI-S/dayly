import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter/services.dart';

import '../providers/drawing_provider.dart';
import '../models/element.dart';
import '../models/image_element.dart';
import '../models/text_element.dart';
import '../models/pen_element.dart';
import '../models/note_element.dart';
import '../models/video_element.dart';
import '../models/gif_element.dart';
import '../widgets/drawing_canvas.dart'; // Import to access toggleCanvasGrid

// Custom painter to preview stroke width - moved to top level
class StrokePreviewPainter extends CustomPainter {
  final double strokeWidth;
  final Color color;
  
  StrokePreviewPainter({
    required this.strokeWidth,
    required this.color,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    
    final Path path = Path();
    path.moveTo(20, size.height / 2);
    path.cubicTo(
      size.width * 0.3, size.height * 0.2,
      size.width * 0.7, size.height * 0.8,
      size.width - 20, size.height / 2,
    );
    
    canvas.drawPath(path, paint);
  }
  
  @override
  bool shouldRepaint(covariant StrokePreviewPainter oldDelegate) {
    return strokeWidth != oldDelegate.strokeWidth || color != oldDelegate.color;
  }
}

class PullUpToolbar extends StatefulWidget {
  final TransformationController? transformationController;
  
  const PullUpToolbar({
    Key? key, 
    this.transformationController,
  }) : super(key: key);

  @override
  State<PullUpToolbar> createState() => _PullUpToolbarState();
}

class _PullUpToolbarState extends State<PullUpToolbar> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _isExpanded = false;
  
  // Compact toolbar shows just a few actions - reduced height for more minimal design
  final double _compactHeight = 52.0;
  
  // Expanded toolbar has more tools and options - reduced height for cleaner look
  final double _expandedHeight = 150.0;
  
  // Vertical drag controller
  double _dragOffset = 0;
  
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }
  
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
  }
  
  void _handleDragUpdate(DragUpdateDetails details) {
    // Negative delta.dy means dragging upward
    if (details.delta.dy < 0 && !_isExpanded) {
      _toggleExpanded();
    } 
    // Positive delta.dy means dragging downward
    else if (details.delta.dy > 0 && _isExpanded) {
      _toggleExpanded();
    }
  }
  
  // Show color picker dialog
  void _showColorPicker(BuildContext context, DrawingProvider provider, Color currentColor) {
    Color selectedColor = currentColor;
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return AlertDialog(
              title: const Text('Pick a color'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ColorPicker(
                      pickerColor: selectedColor,
                      onColorChanged: (color) {
                        setState(() => selectedColor = color);
                      },
                      pickerAreaHeightPercent: 0.8,
                      enableAlpha: true,
                      displayThumbColor: true,
                      labelTypes: const [],
                    ),
                    const SizedBox(height: 10),
                    // Display the selected color
                    Container(
                      width: double.infinity,
                      height: 40,
                      decoration: BoxDecoration(
                        color: selectedColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  child: const Text('Cancel'),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                TextButton(
                  child: const Text('Apply'),
                  onPressed: () {
                    provider.updateSelectedElementProperties({'color': selectedColor});
                    Navigator.of(context).pop();
                    
                    // Show confirmation
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Color applied'),
                        duration: const Duration(seconds: 1),
                        backgroundColor: selectedColor.withOpacity(0.7),
                      ),
                    );
                  },
                ),
              ],
            );
          }
        );
      },
    );
  }
  
  // Show stroke width dialog
  void _showStrokeWidthDialog(BuildContext context, DrawingProvider provider, double currentWidth) {
    double newWidth = currentWidth;
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return AlertDialog(
              title: const Text('Set stroke width'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Slider(
                    value: newWidth,
                    min: 1.0,
                    max: 20.0,
                    divisions: 19,
                    label: newWidth.toStringAsFixed(1),
                    onChanged: (value) {
                      setState(() => newWidth = value);
                    }
                  ),
                  Text('${newWidth.toStringAsFixed(1)} px'),
                  
                  // Preview of stroke width
                  const SizedBox(height: 16),
                  CustomPaint(
                    size: const Size(200, 50),
                    painter: StrokePreviewPainter(
                      strokeWidth: newWidth,
                      color: Colors.black,
                    ),
                  ),
                ],
              ),
              actions: <Widget>[
                TextButton(
                  child: const Text('Cancel'),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                TextButton(
                  child: const Text('Apply'),
                  onPressed: () {
                    provider.updateSelectedElementProperties({'strokeWidth': newWidth});
                    Navigator.of(context).pop();
                    
                    // Show confirmation
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Stroke width updated'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                ),
              ],
            );
          }
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Use theme colors for more native look
    final theme = Theme.of(context);
    final surfaceColor = theme.colorScheme.surface;
    final onSurfaceColor = theme.colorScheme.onSurface;
    
    // Get the bottom safe area padding
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    
    return Material(
      elevation: 4,
      color: Colors.transparent,
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(16.0),
        topRight: Radius.circular(16.0),
      ),
      child: GestureDetector(
        onVerticalDragUpdate: _handleDragUpdate,
        onTap: _toggleExpanded,
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: surfaceColor.withOpacity(0.95),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16.0),
              topRight: Radius.circular(16.0),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Pull handle indicator
              Container(
                height: 3,
                width: 36,
                margin: const EdgeInsets.only(top: 4.0, bottom: 2.0),
                decoration: BoxDecoration(
                  color: onSurfaceColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2.0),
                ),
              ),
              
              // Toolbar content
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                height: _isExpanded ? _expandedHeight : _compactHeight,
                child: Consumer<DrawingProvider>(
                  builder: (context, drawingProvider, child) {
                    // If selection is active, show selection tools
                    if (drawingProvider.selectedElementIds.isNotEmpty) {
                      return _buildSelectionTools(context, drawingProvider);
                    }
                    
                    // Otherwise show the regular tools
                    return _buildRegularTools(context, drawingProvider);
                  },
                ),
              ),
              
              // Add padding at the bottom to respect safe area
              SizedBox(height: bottomPadding),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildSelectionTools(BuildContext context, DrawingProvider drawingProvider) {
    // Get theme colors
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final onSurfaceColor = theme.colorScheme.onSurface;
    
    // Get the selected elements
    final selectedElements = drawingProvider.elements
        .where((el) => drawingProvider.selectedElementIds.contains(el.id))
        .toList();
    
    bool isSingleSelection = selectedElements.length == 1;
    DrawingElement? singleElement = isSingleSelection ? selectedElements.first : null;
    
    // Common actions for selections
    List<Widget> commonActions = [
      IconButton(
        icon: Icon(
          Icons.delete_outline, 
          size: 20,
          color: onSurfaceColor.withOpacity(0.8),
        ),
        tooltip: 'Delete',
        onPressed: drawingProvider.deleteSelected,
      ),
      IconButton(
        icon: Icon(
          Icons.flip_to_front_outlined, 
          size: 20,
          color: onSurfaceColor.withOpacity(0.8),
        ),
        tooltip: 'Bring Forward',
        onPressed: drawingProvider.bringSelectedForward,
      ),
      IconButton(
        icon: Icon(
          Icons.flip_to_back_outlined, 
          size: 20,
          color: onSurfaceColor.withOpacity(0.8),
        ),
        tooltip: 'Send Backward',
        onPressed: drawingProvider.sendSelectedBackward,
      ),
    ];
    
    // Element-specific actions
    List<Widget> specificActions = [];
    
    if (isSingleSelection && singleElement != null) {
      switch (singleElement.type) {
        case ElementType.pen:
          final penElement = singleElement as PenElement;
          specificActions.addAll([
            IconButton(
              icon: Icon(Icons.color_lens, color: penElement.color, size: 20),
              tooltip: 'Change Color',
              onPressed: () => _showColorPicker(context, drawingProvider, penElement.color),
            ),
            IconButton(
              icon: const Icon(Icons.line_weight, size: 20),
              tooltip: 'Change Stroke Width',
              onPressed: () => _showStrokeWidthDialog(context, drawingProvider, penElement.strokeWidth),
            ),
          ]);
          break;
          
        case ElementType.text:
          final textElement = singleElement as TextElement;
          specificActions.addAll([
            IconButton(
              icon: Icon(Icons.color_lens, color: textElement.color, size: 20),
              tooltip: 'Change Color',
              onPressed: () => _showColorPicker(context, drawingProvider, textElement.color),
            ),
            IconButton(
              icon: const Icon(Icons.format_size, size: 20),
              tooltip: 'Change Font Size',
              onPressed: () {
                // Font size dialog would go here
              },
            ),
          ]);
          break;
          
        case ElementType.note:
          final noteElement = singleElement as NoteElement;
          specificActions.addAll([
            IconButton(
              icon: Icon(Icons.color_lens, color: noteElement.backgroundColor, size: 20),
              tooltip: 'Change Color',
              onPressed: () => _showColorPicker(context, drawingProvider, noteElement.backgroundColor),
            ),
            IconButton(
              icon: const Icon(Icons.edit_note, size: 20),
              tooltip: 'Edit Note',
              onPressed: () {
                // Note editing dialog would go here
              },
            ),
          ]);
          break;
          
        case ElementType.image:
        case ElementType.video:
        case ElementType.gif:
          // Media-specific tools would go here
          break;
          
        default:
          break;
      }
    }
    
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: commonActions,
          ),
        ),
        
        if (_isExpanded && specificActions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: specificActions,
              ),
            ),
          ),
          
        // Additional tool slots for expanded mode - simplified for minimal design
        if (_isExpanded)
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(8.0),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: 8.0,
                mainAxisSpacing: 8.0,
                childAspectRatio: 1.2,
              ),
              itemCount: 4, // Reduced number of placeholders
              itemBuilder: (context, index) {
                return Container(
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                  child: const Center(
                    child: Icon(Icons.add, color: Colors.grey, size: 16),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
  
  Widget _buildRegularTools(BuildContext context, DrawingProvider drawingProvider) {
    // Get theme colors
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final onSurfaceColor = theme.colorScheme.onSurface;
    
    // Tools in compact mode - using smaller icons for more minimal design
    List<Widget> compactTools = [
      IconButton(
        icon: Icon(
          Icons.edit, 
          size: 20,
          color: drawingProvider.currentTool == ElementType.pen ? primaryColor : onSurfaceColor.withOpacity(0.8),
        ),
        tooltip: 'Pen Tool',
        onPressed: () => drawingProvider.setTool(ElementType.pen),
      ),
      IconButton(
        icon: Icon(
          Icons.text_fields, 
          size: 20,
          color: drawingProvider.currentTool == ElementType.text ? primaryColor : onSurfaceColor.withOpacity(0.8),
        ),
        tooltip: 'Text Tool',
        onPressed: () => drawingProvider.setTool(ElementType.text),
      ),
      IconButton(
        icon: Icon(
          Icons.image, 
          size: 20,
          color: onSurfaceColor.withOpacity(0.8),
        ),
        tooltip: 'Add Image',
        onPressed: () {
          if (widget.transformationController != null) {
            // Mark as edited and not saved when adding media
            Provider.of<DrawingProvider>(context, listen: false)
              .addImageFromGallery(context, widget.transformationController!);
          }
        },
      ),
      // Move grid toggle button to compact toolbar
      IconButton(
        icon: Icon(
          Icons.grid_on, 
          size: 20,
          color: onSurfaceColor.withOpacity(0.8),
        ),
        tooltip: 'Toggle Grid',
        onPressed: () {
          print("Toggling grid via toolbar button");
          if (drawingCanvasKey.currentState != null) {
            drawingCanvasKey.currentState!.toggleGrid();
            HapticFeedback.lightImpact();
          } else {
            print("Error: DrawingCanvas state not found from toolbar");
            // Provide feedback that it didn't work
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Unable to toggle grid. Please try again.'),
                duration: Duration(seconds: 1),
              ),
            );
          }
        },
      ),
    ];
    
    // Additional tools in expanded mode
    List<Widget> expandedTools = [
      // Row 1
      IconButton(
        icon: Icon(
          Icons.videocam, 
          size: 20,
          color: onSurfaceColor.withOpacity(0.8),
        ),
        tooltip: 'Add Video',
        onPressed: () {
          if (widget.transformationController != null) {
            // Mark as edited and not saved when adding media
            Provider.of<DrawingProvider>(context, listen: false)
              .addVideoFromGallery(context, widget.transformationController!);
          }
        },
      ),
      IconButton(
        icon: Icon(
          Icons.gif_box, 
          size: 20,
          color: onSurfaceColor.withOpacity(0.8),
        ),
        tooltip: 'Add GIF',
        onPressed: () {
          if (widget.transformationController != null) {
            // Mark as edited and not saved when adding media
            Provider.of<DrawingProvider>(context, listen: false)
              .searchAndAddGif(context, widget.transformationController!);
          }
        },
      ),
      IconButton(
        icon: Icon(
          Icons.sticky_note_2, 
          size: 20,
          color: onSurfaceColor.withOpacity(0.8),
        ),
        tooltip: 'Add Sticky Note',
        onPressed: () {
          // Create note at center
          // Get the canvas center position with the transformation controller
          final screenSize = MediaQuery.of(context).size;
          final provider = Provider.of<DrawingProvider>(context, listen: false);
          
          if (widget.transformationController != null) {
            try {
              final Matrix4 inverseMatrix = Matrix4.inverted(widget.transformationController!.value);
              final screenCenter = Offset(screenSize.width / 2, screenSize.height / 2);
              final canvasPosition = MatrixUtils.transformPoint(inverseMatrix, screenCenter);
              provider.createStickyNote(canvasPosition);
            } catch (e) {
              // Fallback if matrix inversion fails
              provider.createStickyNote(const Offset(50000, 50000)); // Canvas center
            }
          } else {
            // Fallback without transformation controller
            provider.createStickyNote(const Offset(50000, 50000)); // Canvas center
          }
        },
      ),
    ];
    
    return Column(
      children: [
        // Compact row always visible
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 2.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: compactTools,
          ),
        ),
        
        // Expanded grid when pulled up - simplified layout
        if (_isExpanded)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 0.0),
              child: GridView.count(
                crossAxisCount: 4,
                mainAxisSpacing: 1.0,
                crossAxisSpacing: 8.0,
                childAspectRatio: 2.0,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                children: expandedTools,
              ),
            ),
          ),
      ],
    );
  }
} 