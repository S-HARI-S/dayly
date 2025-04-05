import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/drawing_provider.dart';
import '../models/element.dart';
import '../models/image_element.dart';
import '../services/background_removal_service.dart';

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
                        print("No selected elements for toolbar");
                        return const SizedBox.shrink();
                      }
                      
                      try {
                        // Get first selected element to determine tools to show
                        final selectedElement = provider.elements.firstWhere(
                          (element) => element.id == selectedIds.first,
                          orElse: () {
                            print("Selected element not found in elements list");
                            return throw Exception("Selected element not found");
                          },
                        );
                        
                        print("Building tools for element type: ${selectedElement.type}");
                        
                        // Show specific tools based on element type
                        switch (selectedElement.type) {
                          case ElementType.image:
                            return _buildImageTools(context, provider, selectedElement as ImageElement);
                          case ElementType.video:
                            return _buildVideoTools(context);
                          case ElementType.gif:
                            return _buildGifTools(context);
                          case ElementType.text:
                            return _buildTextTools(context);
                          default:
                            return _buildDefaultTools(context);
                        }
                      } catch (e) {
                        print("Error building toolbar: $e");
                        return Center(
                          child: Text("Error: $e", 
                            style: const TextStyle(color: Colors.red),
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

  Widget _buildImageTools(BuildContext context, DrawingProvider provider, ImageElement element) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildToolButton(
          context: context,
          icon: Icons.auto_fix_high,
          label: 'Enhance',
          onPressed: () {
            // Image enhancement feature placeholder
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Image enhancement coming soon!')),
            );
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
              const SnackBar(content: Text('Filters coming soon!')),
            );
          },
        ),
      ],
    );
  }

  Widget _buildVideoTools(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildToolButton(
          context: context,
          icon: Icons.color_lens,
          label: 'Effects',
          onPressed: () {},
        ),
        _buildToolButton(
          context: context,
          icon: Icons.volume_up,
          label: 'Audio',
          onPressed: () {},
        ),
        _buildToolButton(
          context: context,
          icon: Icons.speed,
          label: 'Speed',
          onPressed: () {},
        ),
      ],
    );
  }

  Widget _buildGifTools(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildToolButton(
          context: context,
          icon: Icons.speed,
          label: 'Speed',
          onPressed: () {},
        ),
        _buildToolButton(
          context: context,
          icon: Icons.repeat,
          label: 'Loop',
          onPressed: () {},
        ),
      ],
    );
  }

  Widget _buildTextTools(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildToolButton(
          context: context,
          icon: Icons.format_size,
          label: 'Font Size',
          onPressed: () {},
        ),
        _buildToolButton(
          context: context,
          icon: Icons.format_bold,
          label: 'Bold',
          onPressed: () {},
        ),
        _buildToolButton(
          context: context,
          icon: Icons.format_italic,
          label: 'Italic',
          onPressed: () {},
        ),
        _buildToolButton(
          context: context,
          icon: Icons.format_align_center,
          label: 'Align',
          onPressed: () {},
        ),
      ],
    );
  }

  Widget _buildDefaultTools(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildToolButton(
          context: context,
          icon: Icons.copy,
          label: 'Duplicate',
          onPressed: () {},
        ),
        _buildToolButton(
          context: context,
          icon: Icons.delete_outline,
          label: 'Delete',
          onPressed: () {
            Provider.of<DrawingProvider>(context, listen: false).deleteSelected();
          },
        ),
      ],
    );
  }

  Widget _buildToolButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
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
            backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
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
