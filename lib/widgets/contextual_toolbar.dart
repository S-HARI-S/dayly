import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/drawing_provider.dart';
import '../models/element.dart';
import '../models/image_element.dart';
import '../models/text_element.dart';
// Import other element types as needed

class ContextualToolbar extends StatelessWidget {
  const ContextualToolbar({super.key});

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
            onPressed: () {
              drawingProvider.deleteSelected();
              // Optionally show a confirmation or handle errors
            },
          ),
        );
        
        // Add Duplicate, Bring Forward, Send Backward later if needed

        // --- Specific Actions ---
        if (isSingleSelection && singleElement is ImageElement) {
          actions.add(
            IconButton(
              icon: const Icon(Icons.auto_fix_high), // Example icon for BG removal
              tooltip: 'Remove Background',
              onPressed: () async {
                try {
                  await drawingProvider.removeImageBackground(singleElement.id);
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
          );
        } else if (isSingleSelection && singleElement is TextElement) {
           actions.add(
             IconButton(
               icon: const Icon(Icons.edit),
               tooltip: 'Edit Text',
               onPressed: () {
                 // TODO: Implement text editing functionality
                 // Might involve showing a dialog or navigating to an edit screen
                 print("Edit Text action Tapped for ${singleElement.id}");
                 ScaffoldMessenger.of(context).showSnackBar(
                   const SnackBar(content: Text('Text editing not yet implemented.')),
                 );
               },
             ),
           );
        }
        // Add actions for other types (Video, GIF, Pen) or mixed selections as needed


        // Build the actual toolbar widget
        return BottomAppBar(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: actions,
          ),
        );
      },
    );
  }
} 