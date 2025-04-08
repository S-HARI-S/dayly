import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:collection/collection.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../providers/drawing_provider.dart';
import '../models/element.dart';
import '../models/image_element.dart';
import '../models/pen_element.dart';
import '../models/text_element.dart';
import '../models/video_element.dart';
import '../models/gif_element.dart';
import '../models/note_element.dart';
import '../services/background_removal_service.dart';
import 'dart:math' as math;

class ContextToolbar extends StatefulWidget {
  final double height;
  final bool isVisible;
  final Function(double)? onHeightChanged;

  const ContextToolbar({
    super.key,
    this.height = 80.0,
    required this.isVisible,
    this.onHeightChanged,
  });

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
      duration: const Duration(milliseconds: 400), // Increase duration for smoother animation
    );
    
    // Initialize slide animation
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),  // Start from bottom
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut, // Use a smoother curve
    ));
    
    // Initialize height animation
    _heightAnimation = Tween<double>(
      begin: 0.0,
      end: widget.height,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut, // Use a smoother curve
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
        curve: Curves.easeInOut,
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
                        return const SizedBox.shrink();
                      }
                      
                      // Toolbar should only show for single selection
                      if (selectedIds.length != 1) {
                         return const SizedBox.shrink(); 
                      }
                      
                      final selectedElementId = selectedIds.first;

                      try {
                        final selectedElement = provider.elements.firstWhere(
                          (element) => element.id == selectedElementId,
                          orElse: () {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                               provider.showContextToolbar = false; 
                             });
                            return throw Exception("Selected element not found");
                          },
                        );
                        
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
                          case ElementType.note:
                            tools = _buildNoteTools(context, provider, selectedElementId);
                            break;
                          default: 
                            tools = _buildDefaultTools(context, provider, selectedElementId);
                            break;
                        }

                        // Use ListView for horizontal scrolling
                        return ListView( 
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          children: tools,
                        );

                      } catch (e) {
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
    return [
      _buildToolButton(
        context: context,
        icon: Icons.flip_to_front,
        label: 'Forward',
        onPressed: () {
          provider.bringSelectedForward();
        },
      ),
      _buildToolButton(
        context: context,
        icon: Icons.flip_to_back,
        label: 'Back',
        onPressed: () {
          provider.sendSelectedBackward();
        },
      ),
      _buildToolButton(
        context: context,
        icon: Icons.delete_outline,
        label: 'Delete',
        color: Colors.redAccent.withOpacity(0.1),
        onPressed: () {
          provider.deleteSelected();
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
      // Add common tools
      ..._buildCommonTools(context, provider, element.id),
    ];
  }
  
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
                    provider.applyImageEnhancements(element.id, brightness, contrast);
                    Navigator.of(context).pop();
                    
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
    return [
      _buildToolButton(
          context: context,
          icon: Icons.play_arrow,
          label: 'Play',
          onPressed: () => provider.toggleVideoPlayback(elementId),
       ),
      // Add common tools
      ..._buildCommonTools(context, provider, elementId),
    ];
  }

  List<Widget> _buildGifTools(BuildContext context, DrawingProvider provider, String elementId) {
    return _buildCommonTools(context, provider, elementId);
  }

  List<Widget> _buildTextTools(BuildContext context, DrawingProvider provider, String elementId) {
    return [
      _buildToolButton(
          context: context,
          icon: Icons.edit,
          label: 'Edit',
          onPressed: () {
            final textElement = provider.elements.firstWhereOrNull(
              (e) => e.id == elementId && e.type == ElementType.text
            );
            if (textElement != null) {
              final controller = TextEditingController(text: (textElement as TextElement).text);
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Edit Text'),
                  content: TextField(
                    controller: controller,
                    decoration: const InputDecoration(hintText: 'Enter text'),
                    maxLines: null,
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('CANCEL'),
                    ),
                    TextButton(
                      onPressed: () {
                        provider.updateSelectedElementProperties({'text': controller.text});
                        Navigator.pop(context);
                      },
                      child: const Text('SAVE'),
                    ),
                  ],
                ),
              );
            }
          },
      ),
      _buildToolButton(
          context: context,
          icon: Icons.palette,
          label: 'Color',
          onPressed: () {
            final textElement = provider.elements.firstWhereOrNull(
              (e) => e.id == elementId && e.type == ElementType.text
            );
            if (textElement != null) {
              _showColorPickerDialog(context, provider);
            }
          },
      ),
      _buildToolButton(
          context: context,
          icon: Icons.format_size,
          label: 'Size',
          onPressed: () {
            final textElement = provider.elements.firstWhereOrNull(
              (e) => e.id == elementId && e.type == ElementType.text
            ) as TextElement?;
            if (textElement != null) {
              _showFontSizeDialog(context, provider, textElement.fontSize);
            }
          },
      ),
      // Add common tools
      ..._buildCommonTools(context, provider, elementId),
    ];
  }

  // Show color picker dialog
  void _showColorPickerDialog(BuildContext context, DrawingProvider provider) {
    Color pickerColor = provider.currentColor;
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Select Color'),
          content: SingleChildScrollView(
            child: ColorPicker(
              pickerColor: pickerColor,
              onColorChanged: (color) {
                pickerColor = color;
              },
              colorPickerWidth: 300,
              pickerAreaHeightPercent: 0.7,
              enableAlpha: true,
              displayThumbColor: true,
              paletteType: PaletteType.hsv,
              labelTypes: const [ColorLabelType.hsl, ColorLabelType.rgb, ColorLabelType.hex],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('CANCEL'),
            ),
            TextButton(
              onPressed: () {
                provider.setColor(pickerColor);
                Navigator.of(context).pop();
              },
              child: const Text('SELECT'),
            ),
          ],
        );
      },
    );
  }

  void _showFontSizeDialog(BuildContext context, DrawingProvider provider, double currentSize) {
    // Calculate the dynamic maximum value - use the larger of the default max or current size
    final double dynamicMax = math.max(TextElement.MAX_FONT_SIZE, currentSize);
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        double tempSize = currentSize;
        return AlertDialog(
          title: const Text('Adjust Font Size'),
          content: StatefulBuilder(
            builder: (context, setState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${tempSize.toStringAsFixed(1)}px', style: const TextStyle(fontSize: 24)),
                  Slider(
                    value: tempSize,
                    min: TextElement.MIN_FONT_SIZE,
                    max: dynamicMax, // Use the dynamic maximum
                    divisions: ((dynamicMax - TextElement.MIN_FONT_SIZE) / 2).round(), // Adjust divisions based on range
                    onChanged: (value) {
                      setState(() {
                        tempSize = value;
                      });
                    },
                  ),
                ],
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
                if (tempSize != currentSize) {
                  provider.updateSelectedElementProperties({'fontSize': tempSize});
                }
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      }
    );
  }

  List<Widget> _buildNoteTools(BuildContext context, DrawingProvider provider, String elementId) {
    final noteElement = provider.elements.firstWhereOrNull((e) => e.id == elementId) as NoteElement?;
    if (noteElement == null) return _buildCommonTools(context, provider, elementId);
    
    return [
      _buildToolButton(
          context: context,
          icon: Icons.edit,
          label: 'Edit',
          onPressed: () {
            _showNoteEditDialog(context, provider, noteElement);
          }
      ),
      _buildToolButton(
          context: context,
          icon: Icons.palette,
          label: 'Color',
          onPressed: () {
            _showNoteColorPicker(context, provider, noteElement);
          }
      ),
      _buildToolButton(
          context: context,
          icon: noteElement.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
          label: noteElement.isPinned ? 'Unpin' : 'Pin',
          onPressed: () {
            provider.toggleNotePin(elementId);
          }
      ),
      // Add common tools
      ..._buildCommonTools(context, provider, elementId),
    ];
  }

  // Add a method to show note edit dialog
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
            height: 250, // Set a reasonable height
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
                provider.updateNoteContent(note.id, titleController.text, contentController.text);
                Navigator.of(context).pop();
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  void _showNoteColorPicker(BuildContext context, DrawingProvider provider, NoteElement note) {
    // Predefined colors for notes
    final noteColors = [
      Colors.white,
      Colors.yellow.shade100,
      Colors.green.shade100,
      Colors.blue.shade100,
      Colors.purple.shade100,
      Colors.pink.shade100,
      Colors.orange.shade100,
    ];
    
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Choose Note Color'),
          content: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: noteColors.map((color) {
              return GestureDetector(
                onTap: () {
                  provider.setNoteColor(note.id, color);
                  Navigator.of(context).pop();
                },
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: color,
                    border: Border.all(
                      color: note.backgroundColor == color 
                          ? Theme.of(context).primaryColor 
                          : Colors.grey,
                      width: note.backgroundColor == color ? 2 : 1,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              );
            }).toList(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  List<Widget> _buildDefaultTools(BuildContext context, DrawingProvider provider, String elementId) {
    // For pen elements, add color picker
    final penElement = provider.elements.firstWhereOrNull(
      (e) => e.id == elementId && e.type == ElementType.pen
    ) as PenElement?;
    
    if (penElement != null) {
      return [
        _buildToolButton(
          context: context,
          icon: Icons.palette,
          label: 'Color',
          onPressed: () => _showColorPickerDialog(context, provider),
        ),
        _buildToolButton(
          context: context,
          icon: Icons.line_weight,
          label: 'Width',
          onPressed: () {
            double currentWidth = penElement.strokeWidth;
            showDialog(
              context: context,
              builder: (BuildContext context) {
                double tempWidth = currentWidth;
                return AlertDialog(
                  title: const Text('Stroke Width'),
                  content: StatefulBuilder(
                    builder: (context, setState) {
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('${tempWidth.round()}px', style: TextStyle(fontSize: 24)),
                          Slider(
                            value: tempWidth,
                            min: 1.0,
                            max: 30.0,
                            divisions: 29,
                            onChanged: (value) {
                              setState(() {
                                tempWidth = value;
                              });
                            },
                          ),
                        ],
                      );
                    },
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('CANCEL'),
                    ),
                    TextButton(
                      onPressed: () {
                        provider.updateSelectedElementProperties({'strokeWidth': tempWidth});
                        Navigator.pop(context);
                      },
                      child: const Text('APPLY'),
                    ),
                  ],
                );
              },
            );
          },
        ),
        ..._buildCommonTools(context, provider, elementId),
      ];
    }
    
    // Just the common tools for other elements
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
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6.0),
      width: 70,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ElevatedButton(
            onPressed: onPressed,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(45, 45),
              shape: const CircleBorder(),
              padding: const EdgeInsets.all(10),
              backgroundColor: color ?? Theme.of(context).colorScheme.surfaceVariant,
              foregroundColor: Theme.of(context).colorScheme.onSurface,
              elevation: 1,
            ),
            child: isLoading 
                ? const SizedBox(
                    width: 20, 
                    height: 20, 
                    child: CircularProgressIndicator(strokeWidth: 2)
                  )
                : Icon(icon, size: 20),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
