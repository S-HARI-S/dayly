import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart'; // Import color picker

import '../providers/drawing_provider.dart';
import '../models/element.dart';
import '../models/image_element.dart';
import '../models/text_element.dart';
import '../models/pen_element.dart'; // Import PenElement
import '../models/note_element.dart';
import '../models/video_element.dart';
import '../models/gif_element.dart';

class ContextualToolbar extends StatelessWidget {
  const ContextualToolbar({super.key});

  // --- Helper Methods for Actions ---

  void _showColorPicker(BuildContext context, DrawingProvider provider, Color initialColor) {
    showDialog(
      context: context,
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
                provider.updateSelectedElementProperties({'color': selectedColor});
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  void _showStrokeWidthDialog(BuildContext context, DrawingProvider provider, double initialWidth) {
    showDialog(
        context: context,
        builder: (BuildContext context) {
          double currentWidth = initialWidth;
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
                  provider.updateSelectedElementProperties({'strokeWidth': currentWidth});
                  Navigator.of(context).pop();
                },
              ),
            ],
          );
        });
  }

  // --- TODO: Implement Dialogs/Functions for these ---
  void _showTextEditDialog(BuildContext context, DrawingProvider provider, TextElement element) {
    final TextEditingController textController = TextEditingController(text: element.text);
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Edit Text'),
          content: TextField(
            controller: textController,
            autofocus: true,
            maxLines: null, // Allow multiline text
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
                if (textController.text.trim() != element.text) {
                   provider.updateSelectedElementProperties({'text': textController.text.trim()});
                }
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  void _showFontSelection(BuildContext context, DrawingProvider provider, String currentFont) {
      print("TODO: Show font selection UI");
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Font selection not implemented.')));
      // Example: provider.updateSelectedElementProperties({'fontFamily': newFont});
  }

  void _showFontSizeDialog(BuildContext context, DrawingProvider provider, double currentSize) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        double tempSize = currentSize;
        return AlertDialog(
          title: const Text('Adjust Font Size'),
          content: StatefulBuilder(
            builder: (context, setState) {
              return Slider(
                value: tempSize,
                min: 8.0, // Minimum font size
                max: 150.0, // Maximum font size
                divisions: 142, // Granularity
                label: tempSize.toStringAsFixed(1),
                onChanged: (value) {
                  setState(() {
                    tempSize = value;
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

 void _showImageCropRotateUI(BuildContext context, DrawingProvider provider, ImageElement element) {
     print("TODO: Show image crop/rotate UI for ${element.id}");
     ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Image crop/rotate not implemented.')));
     // This would likely involve a new screen or a complex overlay
 }

 void _showImageFilterAdjustUI(BuildContext context, DrawingProvider provider, ImageElement element) {
     print("TODO: Show image filter/adjustment UI for ${element.id}");
     ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Image filters/adjustments not implemented.')));
     // Could use predefined filters or sliders for brightness/contrast
 }

  @override
  Widget build(BuildContext context) {
    return Consumer<DrawingProvider>(
      builder: (context, drawingProvider, child) {
        if (!drawingProvider.showContextToolbar || drawingProvider.selectedElementIds.isEmpty) {
          // Return an empty container if the toolbar shouldn't be visible
          return const SizedBox.shrink(); 
        }

        // Get the selected elements
        final selectedElements = drawingProvider.elements
            .where((el) => drawingProvider.selectedElementIds.contains(el.id))
            .toList();

        // Determine the context based on selected elements
        bool isSingleSelection = selectedElements.length == 1;
        DrawingElement? singleElement = isSingleSelection ? selectedElements.first : null;
        ElementType? commonType;
        bool isMixedSelection = false;

        if (!isSingleSelection && selectedElements.isNotEmpty) {
            commonType = selectedElements.first.type;
            for (var element in selectedElements.skip(1)) {
                if (element.type != commonType) {
                    isMixedSelection = true;
                    commonType = null; // No common type
                    break;
                }
            }
        } else if (isSingleSelection) {
            commonType = singleElement?.type;
        }


        // Build the list of actions based on context
        List<Widget> actions = [];

        // --- Common Actions ---
        actions.add(
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete',
            onPressed: drawingProvider.deleteSelected,
          ),
        );
        actions.add(
          IconButton(
            icon: const Icon(Icons.flip_to_front_outlined), // Or Icons.arrow_upward
            tooltip: 'Bring Forward',
            onPressed: drawingProvider.bringSelectedForward, // We'll add this method
          ),
        );
         actions.add(
          IconButton(
            icon: const Icon(Icons.flip_to_back_outlined), // Or Icons.arrow_downward
            tooltip: 'Send Backward',
            onPressed: drawingProvider.sendSelectedBackward, // We'll add this method
          ),
        );

        // Add Duplicate later if needed

        // --- Specific Actions ---
        if (isSingleSelection && singleElement != null) {
          switch (singleElement.type) {
            case ElementType.pen:
              final penElement = singleElement as PenElement;
              actions.addAll([
                IconButton(
                  icon: Icon(Icons.color_lens, color: penElement.color),
                  tooltip: 'Change Color',
                  onPressed: () => _showColorPicker(context, drawingProvider, penElement.color),
                ),
                IconButton(
                  icon: const Icon(Icons.line_weight),
                  tooltip: 'Change Stroke Width',
                  onPressed: () => _showStrokeWidthDialog(context, drawingProvider, penElement.strokeWidth),
                ),
              ]);
              break;

            case ElementType.text:
              final textElement = singleElement as TextElement;
              actions.addAll([
                IconButton(
                  icon: const Icon(Icons.edit),
                  tooltip: 'Edit Text',
                  onPressed: () => _showTextEditDialog(context, drawingProvider, textElement),
                ),
                 IconButton(
                  icon: Icon(Icons.color_lens, color: textElement.color),
                  tooltip: 'Change Color',
                  onPressed: () => _showColorPicker(context, drawingProvider, textElement.color),
                ),
                 IconButton(
                  icon: const Icon(Icons.font_download_outlined),
                  tooltip: 'Change Font',
                  onPressed: () => _showFontSelection(context, drawingProvider, textElement.fontFamily),
                ),
                 IconButton(
                  icon: const Icon(Icons.format_size),
                  tooltip: 'Change Font Size',
                  onPressed: () => _showFontSizeDialog(context, drawingProvider, textElement.fontSize),
                ),
                 // Add buttons for Bold, Italic, Underline (Toggle)
                 IconButton(
                   icon: Icon(Icons.format_bold, color: textElement.fontWeight == FontWeight.bold ? Theme.of(context).primaryColor : null),
                   tooltip: 'Bold',
                   onPressed: () => drawingProvider.updateSelectedElementProperties({
                      'fontWeight': textElement.fontWeight == FontWeight.bold ? FontWeight.normal : FontWeight.bold
                   }),
                 ),
                 IconButton(
                   icon: Icon(Icons.format_italic, color: textElement.fontStyle == FontStyle.italic ? Theme.of(context).primaryColor : null),
                   tooltip: 'Italic',
                   onPressed: () => drawingProvider.updateSelectedElementProperties({
                      'fontStyle': textElement.fontStyle == FontStyle.italic ? FontStyle.normal : FontStyle.italic
                   }),
                 ),
                 // Add buttons for Alignment (Cycle through Left, Center, Right)
                 IconButton(
                   icon: Icon(_getAlignmentIcon(textElement.textAlign)),
                   tooltip: 'Align Text',
                   onPressed: () {
                      TextAlign nextAlign;
                      if (textElement.textAlign == TextAlign.left) {
                        nextAlign = TextAlign.center;
                      } else if (textElement.textAlign == TextAlign.center) nextAlign = TextAlign.right;
                      else nextAlign = TextAlign.left;
                      drawingProvider.updateSelectedElementProperties({'textAlign': nextAlign});
                   },
                 ),
              ]);
              break;

            case ElementType.image:
              final imageElement = singleElement as ImageElement;
              actions.addAll([
                IconButton(
                  icon: const Icon(Icons.auto_fix_high),
                  tooltip: 'Remove Background',
                  onPressed: () async {
                    try {
                      await drawingProvider.removeImageBackground(imageElement.id);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Background removal processing...')),
                      );
                    } catch (e) {
                       ScaffoldMessenger.of(context).showSnackBar(
                         SnackBar(content: Text('Error removing background: ${e.toString()}')),
                       );
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.crop_rotate),
                  tooltip: 'Crop / Rotate',
                  onPressed: () => _showImageCropRotateUI(context, drawingProvider, imageElement),
                ),
                IconButton(
                  icon: const Icon(Icons.filter_vintage_outlined), // Or other filter icon
                  tooltip: 'Filters / Adjustments',
                  onPressed: () => _showImageFilterAdjustUI(context, drawingProvider, imageElement),
                ),
              ]);
              break;
            // Add cases for Video, Gif if they have specific actions
            default:
              // No specific actions for this type or mixed selection
              break;
          }
        }

        // Build the actual toolbar widget
        return BottomAppBar(
          // Wrap the content in a SingleChildScrollView for horizontal scrolling
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Padding(
               padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0), // Added vertical padding
               child: Wrap(
                 alignment: WrapAlignment.start, // Align items to the start
                 spacing: 8.0, // Increased spacing between buttons
                 runSpacing: 4.0, // Keep run spacing if needed, though less likely with horizontal scroll
                 children: actions,
               ),
            ),
          )
        );
      },
    );
  }

  // Helper to get alignment icon
  IconData _getAlignmentIcon(TextAlign align) {
    switch (align) {
      case TextAlign.left:
      case TextAlign.start:
        return Icons.format_align_left;
      case TextAlign.center:
        return Icons.format_align_center;
      case TextAlign.right:
      case TextAlign.end:
        return Icons.format_align_right;
      case TextAlign.justify:
        return Icons.format_align_justify;
    }
  }
}