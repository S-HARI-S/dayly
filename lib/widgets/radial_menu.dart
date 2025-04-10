import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../models/element.dart';
import '../models/text_element.dart';
import '../models/pen_element.dart'; // Add this missing import
import '../providers/drawing_provider.dart';
import 'package:provider/provider.dart';

// Controller to handle communication between DrawingCanvas and RadialMenu
class RadialMenuController {
  static final RadialMenuController _instance = RadialMenuController._internal();
  static RadialMenuController get instance => _instance;
  
  RadialMenuController._internal();
  
  // Callback for position updates
  Function(Offset)? _onPointerPositionChanged;
  
  // Register the callback from the RadialMenu
  void registerPositionCallback(Function(Offset) callback) {
    _onPointerPositionChanged = callback;
  }
  
  // Clear the callback when menu is dismissed
  void clearPositionCallback() {
    _onPointerPositionChanged = null;
  }
  
  // Update pointer position - called from DrawingCanvas
  void updatePointerPosition(Offset position) {
    if (_onPointerPositionChanged != null) {
      _onPointerPositionChanged!(position);
    }
  }
  
  // Callback for triggering action
  Function()? _onTriggerAction;
  
  // Register action trigger callback
  void registerActionTrigger(Function() callback) {
    _onTriggerAction = callback;
  }
  
  // Clear action trigger
  void clearActionTrigger() {
    _onTriggerAction = null;
  }
  
  // Trigger the selected action
  void triggerAction() {
    if (_onTriggerAction != null) {
      _onTriggerAction!();
    }
  }
}

class RadialMenu extends StatefulWidget {
  final Offset position;
  final DrawingElement element;
  final DrawingProvider provider;
  final VoidCallback onDismiss;
  final BuildContext parentContext;

  const RadialMenu({
    Key? key,
    required this.position,
    required this.element,
    required this.provider,
    required this.onDismiss,
    required this.parentContext,
  }) : super(key: key);

  @override
  State<RadialMenu> createState() => _RadialMenuState();
}

class _RadialMenuState extends State<RadialMenu> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  
  // Track the current pointer position for selection
  Offset? _currentPointerPosition;
  int? _hoveredItemIndex;
  int? _lastHoveredItemIndex; // Track previous hover for haptic feedback
  bool _actionTriggered = false;
  static const double _menuRadius = 100.0;
  static const double _itemRadius = 24.0;
  
  // Add a flag to track whether we're in touch or mouse mode
  bool _isTouchInteraction = false;
  
  @override
  void initState() {
    super.initState();
    print("RadialMenu initializing at position: ${widget.position}");
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    
    _scaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutQuad)
    );
    
    // Set initial pointer position to the center for touch-based interactions
    _currentPointerPosition = widget.position;
    
    // Register with the controller to receive position updates
    RadialMenuController.instance.registerPositionCallback(_handlePointerPositionUpdate);
    
    // Register action trigger
    RadialMenuController.instance.registerActionTrigger(_triggerSelectedAction);
    
    _controller.forward();
  }

  @override
  void dispose() {
    // Clear the callback when disposing
    RadialMenuController.instance.clearPositionCallback();
    RadialMenuController.instance.clearActionTrigger();
    _controller.dispose();
    super.dispose();
  }
  
  // Handler for pointer position updates from the DrawingCanvas
  void _handlePointerPositionUpdate(Offset position) {
    setState(() {
      _currentPointerPosition = position;
      _checkForSelection(position);
    });
  }

  // Determine which menu items to show based on element type
  List<RadialMenuItem> _buildMenuItems() {
    final List<RadialMenuItem> items = [];
    
    // Common actions for all elements
    items.add(RadialMenuItem(
      icon: Icons.delete_outline,
      color: Colors.red,
      onSelected: () {
        // First select the element
        widget.provider.selectElement(widget.element);
        // Then force delete it directly using its ID
        widget.provider.deleteElement(widget.element.id);
        // Clear any selections
        widget.provider.clearSelection();
      },
      tooltip: 'Delete',
    ));
    
    items.add(RadialMenuItem(
      icon: Icons.flip_to_front,
      color: Colors.blue,
      onSelected: () {
        widget.provider.bringSelectedForward();
      },
      tooltip: 'Bring Forward',
    ));
    
    items.add(RadialMenuItem(
      icon: Icons.flip_to_back,
      color: Colors.blue,
      onSelected: () {
        widget.provider.sendSelectedBackward();
      },
      tooltip: 'Send Backward',
    ));
    
    // Element-specific actions
    switch (widget.element.type) {
      case ElementType.text:
        final textElement = widget.element as TextElement;
        items.add(RadialMenuItem(
          icon: Icons.edit,
          color: Colors.green,
          onSelected: () {
            _showTextEditDialog(textElement);
          },
          tooltip: 'Edit Text',
        ));
        items.add(RadialMenuItem(
          icon: Icons.palette,
          color: Colors.purple,
          onSelected: () {
            _showColorPicker(textElement.color);
          },
          tooltip: 'Change Color',
        ));
        break;
        
      case ElementType.pen:
        final penElement = widget.element as PenElement;
        items.add(RadialMenuItem(
          icon: Icons.palette,
          color: Colors.purple,
          onSelected: () {
            _showColorPicker(penElement.color);
          },
          tooltip: 'Change Color',
        ));
        items.add(RadialMenuItem(
          icon: Icons.line_weight,
          color: Colors.orange,
          onSelected: () {
            _showStrokeWidthDialog(penElement.strokeWidth);
          },
          tooltip: 'Stroke Width',
        ));
        break;
        
      case ElementType.image:
        items.add(RadialMenuItem(
          icon: Icons.crop,
          color: Colors.teal,
          onSelected: () {
            ScaffoldMessenger.of(widget.parentContext).showSnackBar(
              const SnackBar(content: Text('Crop feature not implemented'))
            );
          },
          tooltip: 'Crop Image',
        ));
        break;
        
      default:
        // No specific actions for other element types
        break;
    }
    
    return items;
  }
  
  void _showColorPicker(Color initialColor) {
    showDialog(
      context: widget.parentContext,
      builder: (BuildContext context) {
        Color selectedColor = initialColor;
        return AlertDialog(
          title: const Text('Select Color'),
          content: SingleChildScrollView(
            child: ColorPicker(
              pickerColor: initialColor,
              onColorChanged: (color) => selectedColor = color,
              showLabel: true,
              pickerAreaHeightPercent: 0.8,
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: const Text('OK'),
              onPressed: () {
                widget.provider.updateSelectedElementProperties({'color': selectedColor});
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  // Update the method signature to accept an initial width parameter
  void _showStrokeWidthDialog([double? initialWidth]) {
    double currentWidth = initialWidth ?? 2.0;
    
    showDialog(
      context: widget.parentContext,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Select Stroke Width'),
          content: StatefulBuilder(
            builder: (context, setState) {
              return Slider(
                value: currentWidth,
                min: 1.0,
                max: 50.0,
                divisions: 49,
                label: currentWidth.toStringAsFixed(1),
                onChanged: (value) {
                  setState(() {
                    currentWidth = value;
                  });
                },
              );
            }
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: const Text('OK'),
              onPressed: () {
                widget.provider.updateSelectedElementProperties({'strokeWidth': currentWidth});
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      }
    );
  }
  
  void _showTextEditDialog(TextElement textElement) {
    final TextEditingController textController = TextEditingController(text: textElement.text);
    showDialog(
      context: widget.parentContext,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Edit Text'),
          content: TextField(
            controller: textController,
            autofocus: true,
            maxLines: null,
            decoration: const InputDecoration(hintText: 'Enter text'),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: const Text('OK'),
              onPressed: () {
                if (textController.text.trim() != textElement.text) {
                  widget.provider.updateSelectedElementProperties({'text': textController.text.trim()});
                }
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }
  
  void _checkForSelection(Offset pointerPosition) {
    final List<RadialMenuItem> items = _buildMenuItems();
    final int itemCount = items.length;
    _lastHoveredItemIndex = _hoveredItemIndex;
    
    // Debug log for pointer position
    print("Checking selection at pointer position: $pointerPosition (menu center: ${widget.position})");
    
    // Calculate distances from pointer to each item center
    for (int i = 0; i < itemCount; i++) {
      final double angle = (2 * math.pi * i / itemCount) - math.pi / 2;
      final Offset itemCenter = Offset(
        widget.position.dx + _menuRadius * math.cos(angle),
        widget.position.dy + _menuRadius * math.sin(angle)
      );
      
      final double distance = (pointerPosition - itemCenter).distance;
      
      // If pointer is within the item radius, mark it as hovered
      // Use a larger touch area for finger selection
      final double selectionRadius = _isTouchInteraction ? _itemRadius * 3.0 : _itemRadius * 1.5;
      
      if (distance < selectionRadius) {
        if (_hoveredItemIndex != i) {
          print("HOVER DETECTED on item $i at distance $distance (radius: $selectionRadius)");
          setState(() {
            _hoveredItemIndex = i;
          });
          // Add haptic feedback when hovering over a new item
          if (_lastHoveredItemIndex != i) {
            HapticFeedback.selectionClick();
          }
        }
        return;
      }
    }
    
    // If not hovering over any item
    if (_hoveredItemIndex != null) {
      print("HOVER CLEARED - no item under pointer");
      setState(() {
        _hoveredItemIndex = null;
      });
    }
  }
  
  void _triggerSelectedAction() {
    // Add debug log to see if this method is being called
    print("_triggerSelectedAction called, _hoveredItemIndex: $_hoveredItemIndex, _actionTriggered: $_actionTriggered");
    
    if (_hoveredItemIndex != null && !_actionTriggered) {
      _actionTriggered = true;
      final items = _buildMenuItems();
      if (_hoveredItemIndex! < items.length) {
        // Strong haptic feedback when selecting an item
        HapticFeedback.heavyImpact();
        print("Executing action for item at index: $_hoveredItemIndex");
        items[_hoveredItemIndex!].onSelected();
      }
      widget.onDismiss();
    } else {
      // Get the item at the current pointer position if no hover index
      if (_currentPointerPosition != null && !_actionTriggered) {
        final items = _buildMenuItems();
        final itemCount = items.length;
        
        // Try to determine the closest item
        for (int i = 0; i < itemCount; i++) {
          final double angle = (2 * math.pi * i / itemCount) - math.pi / 2;
          final Offset itemCenter = Offset(
            widget.position.dx + _menuRadius * math.cos(angle),
            widget.position.dy + _menuRadius * math.sin(angle)
          );
          
          final double distance = (_currentPointerPosition! - itemCenter).distance;
          final double selectionRadius = _isTouchInteraction ? _itemRadius * 2.5 : _itemRadius * 1.5;
          
          if (distance < selectionRadius) {
            _actionTriggered = true;
            HapticFeedback.heavyImpact();
            print("Directly executing action for item at index: $i");
            items[i].onSelected();
            widget.onDismiss();
            return;
          }
        }
      }
      
      widget.onDismiss();
    }
  }

  // Helper function to check if a point is inside a circle
  bool _isInside(Offset center, double radius, Offset position) {
    return (position - center).distance <= radius;
  }

  // Get the menu item index at a position
  int? _getItemIndexFromPosition(Offset position) {
    if (!_isInside(widget.position, _menuRadius, position)) return null;
    if (_isInside(widget.position, _itemRadius, position)) return null;

    // Calculate the angle of the position relative to center
    final angle = (math.atan2(
      position.dy - widget.position.dy,
      position.dx - widget.position.dx,
    ) + math.pi * 2) % (math.pi * 2);

    // Calculate which segment the angle falls into
    final segmentCount = _buildMenuItems().length;
    if (segmentCount == 0) return null;

    final segmentAngle = 2 * math.pi / segmentCount;
    // Adjust the angle by half a segment to align with our rendering
    final adjustedAngle = (angle + segmentAngle / 2) % (math.pi * 2);
    
    // Calculate which segment this position falls into
    return (adjustedAngle ~/ segmentAngle) % segmentCount;
  }

  @override
  Widget build(BuildContext context) {
    final List<RadialMenuItem> items = _buildMenuItems();
    final int itemCount = items.length;
    print("RadialMenu building with ${items.length} items at ${widget.position}");

    // Return Stack directly, not Positioned
    return Stack(
      children: [
        // Semi-transparent overlay with higher opacity for better visibility
        GestureDetector(
          onTap: widget.onDismiss,
          child: Container(color: Colors.black.withOpacity(0.2)), // More visible overlay
        ),
        
        // Radial menu
        MouseRegion(
          onHover: (details) {
            _isTouchInteraction = false;
            setState(() {
              _currentPointerPosition = details.position;
              _checkForSelection(_currentPointerPosition!);
            });
          },
          child: GestureDetector(
            // Handle touch events
            onPanStart: (details) {
              _isTouchInteraction = true;
              setState(() {
                _currentPointerPosition = details.globalPosition;
                _checkForSelection(_currentPointerPosition!);
              });
            },
            onPanUpdate: (details) {
              _isTouchInteraction = true;
              setState(() {
                _currentPointerPosition = details.globalPosition;
                _checkForSelection(_currentPointerPosition!);
              });
            },
            onPanEnd: (details) {
              _triggerSelectedAction();
            },
            // Add tap handler to trigger action on direct tap
            onTap: () {
              if (_hoveredItemIndex != null) {
                _triggerSelectedAction();
              }
            },
            
            child: AnimatedBuilder(
              animation: _scaleAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: _scaleAnimation.value,
                  alignment: Alignment(
                    (widget.position.dx / MediaQuery.of(context).size.width) * 2 - 1,
                    (widget.position.dy / MediaQuery.of(context).size.height) * 2 - 1
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Add a visible circular background behind the menu for debugging
                      Positioned(
                        left: widget.position.dx - _menuRadius - 10,
                        top: widget.position.dy - _menuRadius - 10,
                        width: (_menuRadius + 10) * 2, 
                        height: (_menuRadius + 10) * 2,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.15),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withOpacity(0.2),
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                      
                      // Center marker with increased visibility
                      Positioned(
                        left: widget.position.dx - 10, // Larger marker
                        top: widget.position.dy - 10, // Larger marker
                        child: Container(
                          width: 20, // Larger marker
                          height: 20, // Larger marker
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.black, width: 2), // Thicker border
                            boxShadow: [BoxShadow(
                              color: Colors.black.withOpacity(0.5),
                              blurRadius: 4,
                              spreadRadius: 1,
                            )], // Add shadow for visibility
                          ),
                        ),
                      ),
                      
                      // Menu items with improved visibility and size
                      ...List.generate(itemCount, (index) {
                        final double angle = (2 * math.pi * index / itemCount) - math.pi / 2;
                        final bool isHovered = _hoveredItemIndex == index;
                        
                        // Calculate position - make items larger
                        final itemSize = _itemRadius * 3.0; // Even larger item size for better touch targets
                        
                        return Positioned(
                          left: widget.position.dx + _menuRadius * math.cos(angle) - itemSize/2,
                          top: widget.position.dy + _menuRadius * math.sin(angle) - itemSize/2,
                          width: itemSize,
                          height: itemSize,
                          child: Material(
                            color: Colors.transparent,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              decoration: BoxDecoration(
                                color: isHovered 
                                  ? items[index].color
                                  : items[index].color.withOpacity(0.9),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.6), // Darker shadow
                                    blurRadius: isHovered ? 15 : 8, // Bigger blur
                                    spreadRadius: isHovered ? 3 : 2, // Bigger spread
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Tooltip(
                                  message: items[index].tooltip,
                                  child: Icon(
                                    items[index].icon,
                                    color: Colors.white,
                                    size: isHovered ? 36 : 32, // Larger icons
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                      
                      // Connecting lines with improved visibility
                      if (_currentPointerPosition != null && _hoveredItemIndex != null)
                        CustomPaint(
                          size: Size.infinite,
                          painter: LinePainter(
                            start: widget.position,
                            end: _currentPointerPosition!,
                            color: items[_hoveredItemIndex!].color,
                            strokeWidth: 6.0, // Even thicker line
                          ),
                        ),

                      // Debug outline to verify render area 
                      Positioned(
                        left: widget.position.dx - _menuRadius - 50,
                        top: widget.position.dy - _menuRadius - 50,
                        width: (_menuRadius + 50) * 2,
                        height: (_menuRadius + 50) * 2,
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.red.withOpacity(0.0), width: 2), // Invisible border in production
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

// Model class for menu items
class RadialMenuItem {
  final IconData icon;
  final Color color;
  final VoidCallback onSelected;
  final String tooltip;

  RadialMenuItem({
    required this.icon,
    required this.color, 
    required this.onSelected,
    required this.tooltip,
  });
}

// Line painter for selection indication
class LinePainter extends CustomPainter {
  final Offset start;
  final Offset end;
  final Color color;
  final double strokeWidth;
  
  LinePainter({
    required this.start, 
    required this.end, 
    required this.color, 
    this.strokeWidth = 2.0
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.7)
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;
      
    canvas.drawLine(start, end, paint);
  }
  
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
