import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:collection/collection.dart';
import '../providers/drawing_provider.dart';
import '../models/element.dart';
import '../models/image_element.dart';
import '../services/background_removal_service.dart';
import 'dart:math' as math;

class ContextToolbar extends StatefulWidget {
  final double height;
  final bool isVisible;
  final Function(double)? onHeightChanged;  // Add callback for height changes

  const ContextToolbar({
    Key? key,
    this.height = 80.0,
    required this.isVisible,
    this.onHeightChanged,
  }) : super(key: key);

  @override
  State<ContextToolbar> createState() => _ContextToolbarState();
}

class _ContextToolbarState extends State<ContextToolbar> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _heightAnimation;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250), // Slightly faster animation
    );
    
    // Initialize slide animation
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),  // Start from bottom
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic, // Smoother curve
    ));
    
    // Initialize height animation
    _heightAnimation = Tween<double>(
      begin: 0.0,
      end: widget.height,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));

    // Initialize animation state based on visibility
    if (widget.isVisible) {
      _animationController.value = 1.0; // Start visible if needed
      _notifyHeightChange(widget.height);
    }
    
    print("ContextToolbar initialized with isVisible=${widget.isVisible}");
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }
  
  // Helper method to notify parent of height changes
  void _notifyHeightChange(double height) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onHeightChanged?.call(height);
    });
  }

  @override
  void didUpdateWidget(ContextToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // Update height animation if height changed
    if (widget.height != oldWidget.height) {
      _heightAnimation = Tween<double>(
        begin: 0.0,
        end: widget.height,
      ).animate(CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOutCubic,
      ));
    }
    
    if (widget.isVisible != oldWidget.isVisible) {
      print("ContextToolbar visibility changed: ${oldWidget.isVisible} -> ${widget.isVisible}");
      
      if (widget.isVisible) {
        _animationController.forward().then((_) {
          _notifyHeightChange(widget.height);
        });
      } else {
        _animationController.reverse().then((_) {
          _notifyHeightChange(0);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return Visibility(
          visible: _animationController.value > 0,
          maintainState: true,
          maintainAnimation: true,
          child: Material(
            elevation: 8.0 * _animationController.value, // Animated elevation
            color: Colors.transparent,
            child: SlideTransition(
              position: _slideAnimation,
              child: SizedBox(
                height: _heightAnimation.value,
                width: double.infinity,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2 * _animationController.value),
                        offset: Offset(0, -3 * _animationController.value),
                        blurRadius: 6 * _animationController.value,
                      ),
                    ],
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                  child: Consumer<DrawingProvider>(
                    builder: (context, provider, _) {
                      final selectedIds = provider.selectedElementIds;
                      
                      if (selectedIds.isEmpty) {
                        // print("No selected elements for toolbar"); // Already prints in provider setter
                        return const SizedBox.shrink(); // Don't build if no selection
                      }
                      
                      // Toolbar should only show for single selection
                      if (selectedIds.length != 1) {
                         print("Toolbar only supports single selection for now.");
                         // Optionally hide the toolbar immediately if multiple are selected
                         // WidgetsBinding.instance.addPostFrameCallback((_) {
                         //   provider.showContextToolbar = false; 
                         // });
                         return const SizedBox.shrink(); 
                      }
                      
                      final selectedElementId = selectedIds.first;

                      try {
                        final selectedElement = provider.elements.firstWhere(
                          (element) => element.id == selectedElementId,
                          orElse: () {
                            print("Selected element $selectedElementId not found in elements list for toolbar");
                            // Hide toolbar if element disappears
                             WidgetsBinding.instance.addPostFrameCallback((_) {
                               provider.showContextToolbar = false; 
                             });
                            return throw Exception("Selected element not found");
                          },
                        );
                        
                        // print("Building tools for element type: ${selectedElement.type}");
                        
                        // Show specific tools based on element type
                        List<Widget> tools;
                        switch (selectedElement.type) {
                          case ElementType.image:
                            tools = _buildImageTools(context, provider, selectedElement as ImageElement);
                            break;
                          case ElementType.video:
                            tools = _buildVideoTools(context, provider, selectedElementId);
                            break;
                          case ElementType.gif:
                            tools = _buildGifTools(context, provider, selectedElementId);
                            break;
                          case ElementType.text:
                            tools = _buildTextTools(context, provider, selectedElementId);
                            break;
                          default: // Pen etc.
                            tools = _buildDefaultTools(context, provider, selectedElementId);
                            break;
                        }
                        // Use ListView for horizontal scrolling if too many items
                        return ListView( 
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 8.0), // Add some padding
                          children: tools,
                        );

                      } catch (e) {
                        print("Error building toolbar content: $e");
                        return Center(
                          child: Text("Error: ${e.toString()}", 
                            style: const TextStyle(color: Colors.red, fontSize: 10),
                          ),
                        );
                      }
                    },
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // --- Tool Building Methods ---
  
  // Helper to build common buttons
  List<Widget> _buildCommonTools(BuildContext context, DrawingProvider provider, String elementId) {
    // Note: elementId is less relevant here as the provider methods operate on selectedElementIds
    return [
      _buildToolButton(
        context: context,
        icon: Icons.flip_to_front_outlined, // Icon for bring forward
        label: 'Bring Fwd',
        onPressed: () {
          provider.bringSelectedForward(); // Call provider method
        },
      ),
      _buildToolButton(
        context: context,
        icon: Icons.flip_to_back_outlined, // Icon for send backward
        label: 'Send Back',
        onPressed: () {
          provider.sendSelectedBackward(); // Call provider method
        },
      ),
      _buildToolButton(
        context: context,
        icon: Icons.rotate_90_degrees_ccw, // Add rotation button
        label: 'Rotate',
        onPressed: () {
          // Rotate the selected element by 90 degrees (π/2 radians)
          final element = provider.elements.firstWhereOrNull((e) => e.id == elementId);
          if (element != null) {
            // Add π/2 to current rotation (90 degrees clockwise)
            final newRotation = element.rotation + math.pi/2;
            provider.rotateSelected(element.id, newRotation);
            provider.endPotentialRotation();
          }
        },
      ),
      _buildToolButton(
        context: context,
        icon: Icons.delete_outline,
        label: 'Delete',
        color: Colors.redAccent, // Make delete stand out
        onPressed: () {
          provider.deleteSelected(); // Use the method that deletes all selected
        },
      ),
    ];
  }

  List<Widget> _buildImageTools(BuildContext context, DrawingProvider provider, ImageElement element) {
    return [
      _buildToolButton(
        context: context,
        icon: Icons.auto_fix_high,
        label: 'Enhance',
        onPressed: () {
          // Show image enhancement dialog instead of just a message
          _showImageEnhancementDialog(context, provider, element);
        },
      ),
      _buildToolButton(
        context: context,
        icon: Icons.crop,
        label: 'Crop',
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Crop feature coming soon!')),
          );
        },
      ),
      _buildToolButton(
        context: context,
        icon: Icons.hide_image,
        label: 'Remove BG',
        isLoading: _isProcessing,
        onPressed: _isProcessing ? null : () async {
          setState(() {
            _isProcessing = true;
          });

          try {
            await provider.removeImageBackground(element.id);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Background removed successfully!')),
              );
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Failed to remove background: ${e.toString()}')),
              );
            }
          } finally {
            if (mounted) {
              setState(() {
                _isProcessing = false;
              });
            }
          }
        },
      ),
      _buildToolButton(
        context: context,
        icon: Icons.filter,
        label: 'Filters',
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Filter feature coming soon!')),
          );
        },
      ),
      // Add common tools
      ..._buildCommonTools(context, provider, element.id),
    ];
  }
  
  // New method to show image enhancement dialog
  void _showImageEnhancementDialog(BuildContext context, DrawingProvider provider, ImageElement element) {
    double brightness = 0.0; // Range: -1.0 to 1.0
    double contrast = 0.0;   // Range: -1.0 to 1.0
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Image Enhancement'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Brightness'),
                  Slider(
                    value: brightness,
                    min: -1.0,
                    max: 1.0,
                    divisions: 20,
                    label: brightness.toStringAsFixed(1),
                    onChanged: (value) {
                      setState(() {
                        brightness = value;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  const Text('Contrast'),
                  Slider(
                    value: contrast,
                    min: -1.0,
                    max: 1.0,
                    divisions: 20,
                    label: contrast.toStringAsFixed(1),
                    onChanged: (value) {
                      setState(() {
                        contrast = value;
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  child: const Text('Cancel'),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                TextButton(
                  child: const Text('Apply'),
                  onPressed: () {
                    // Call provider method to apply enhancements
                    provider.applyImageEnhancements(element.id, brightness, contrast);
                    Navigator.of(context).pop();
                    
                    // Show confirmation message
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Image enhancements applied')),
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

  List<Widget> _buildVideoTools(BuildContext context, DrawingProvider provider, String elementId) {
    // Example: Add common tools here too if needed
    return [
      _buildToolButton(
          context: context,
          icon: Icons.play_arrow, // Placeholder
          label: 'Play/Pause',
          onPressed: () => provider.toggleVideoPlayback(elementId),
       ),
      // Add common tools
      ..._buildCommonTools(context, provider, elementId),
    ];
  }

  List<Widget> _buildGifTools(BuildContext context, DrawingProvider provider, String elementId) {
    // Add common tools
    return _buildCommonTools(context, provider, elementId);
  }

  List<Widget> _buildTextTools(BuildContext context, DrawingProvider provider, String elementId) {
    // Example: Add common tools here too if needed
    return [
      _buildToolButton(
          context: context,
          icon: Icons.edit, // Placeholder
          label: 'Edit Text',
          onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Edit text feature coming soon!')),
              );
          }
       ),
      // Add common tools
      ..._buildCommonTools(context, provider, elementId),
    ];
  }

  List<Widget> _buildDefaultTools(BuildContext context, DrawingProvider provider, String elementId) {
    // Just the common tools for Pen, etc.
    return _buildCommonTools(context, provider, elementId);
  }

  // --- Individual Tool Button Widget ---
  Widget _buildToolButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    Color? color,
    bool isLoading = false,
  }) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            shape: const CircleBorder(),
            padding: const EdgeInsets.all(12),
            backgroundColor: color ?? Theme.of(context).primaryColor.withOpacity(0.1),
            foregroundColor: Theme.of(context).primaryColor,
          ),
          child: isLoading 
              ? const SizedBox(
                  width: 24, 
                  height: 24, 
                  child: CircularProgressIndicator(strokeWidth: 2)
                )
              : Icon(icon, size: 24),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 12),
        ),
      ],
    );
  }
}
