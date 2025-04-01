// lib/main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'providers/drawing_provider.dart';
import 'widgets/drawing_canvas.dart';
import 'models/element.dart'; // Base element type

void main() {
  runApp(
    MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => DrawingProvider())],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Drawing App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
        // Define visual density for consistent spacing
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const DrawingBoard(),
      debugShowCheckedModeBanner: false, // Hide debug banner
    );
  }
}

class DrawingBoard extends StatefulWidget {
  const DrawingBoard({super.key});

  @override
  State<DrawingBoard> createState() => _DrawingBoardState();
}

class _DrawingBoardState extends State<DrawingBoard> {
  int _pointerCount = 0;
  late TransformationController _transformationController;

  @override
  void initState() {
    super.initState();
    _transformationController = TransformationController();
    // Optional: Add listener to transformationController to update other UI if needed
    // _transformationController.addListener(_onTransformUpdate);
  }

  // void _onTransformUpdate() {
  //   // Example: Update scale display somewhere
  //   // setState(() { _currentScale = _transformationController.value.getMaxScaleOnAxis(); });
  // }

  @override
  void dispose() {
    // _transformationController.removeListener(_onTransformUpdate);
    _transformationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Access provider once here if needed for multiple actions, but prefer Consumer/Selector
    // final drawingProvider = Provider.of<DrawingProvider>(context, listen: false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Flutter Drawing App'),
        actions: [
          // Select Tool (Moved to Tool Palette)
          // IconButton(
          //   icon: const Icon(Icons.pan_tool_alt_outlined),
          //   onPressed: () => Provider.of<DrawingProvider>(context, listen: false).setTool(ElementType.select),
          //   tooltip: 'Select / Move',
          // ),
          IconButton(
            icon: const Icon(Icons.undo),
            onPressed: () => Provider.of<DrawingProvider>(context, listen: false).undo(),
            tooltip: 'Undo',
          ),
          IconButton(
            icon: const Icon(Icons.redo),
            onPressed: () => Provider.of<DrawingProvider>(context, listen: false).redo(),
            tooltip: 'Redo',
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () => Provider.of<DrawingProvider>(context, listen: false).deleteSelected(),
            tooltip: 'Delete Selected',
          ),
          // Grouping not implemented yet
          // IconButton(
          //   icon: const Icon(Icons.group_work),
          //   onPressed: () => Provider.of<DrawingProvider>(context, listen: false).groupSelected(),
          //   tooltip: 'Group Selected',
          // ),
          // IconButton(
          //   icon: const Icon(Icons.call_split),
          //   onPressed: () => Provider.of<DrawingProvider>(context, listen: false).ungroupSelected(),
          //   tooltip: 'Ungroup Selected',
          // ),
        ],
      ),
      body: Stack(
        children: [
          // Listener to track pointer count for enabling/disabling InteractiveViewer pan/zoom
          Listener(
            onPointerDown: (PointerDownEvent event) {
              setState(() { _pointerCount++; });
            },
            onPointerUp: (PointerUpEvent event) {
              setState(() { _pointerCount = _pointerCount > 0 ? _pointerCount - 1 : 0; });
            },
            onPointerCancel: (PointerCancelEvent event) {
              setState(() { _pointerCount = _pointerCount > 0 ? _pointerCount - 1 : 0; });
            },
            // Make this listener transparent to interactions intended for the canvas
            behavior: HitTestBehavior.translucent,
            child: InteractiveViewer(
              transformationController: _transformationController,
              boundaryMargin: const EdgeInsets.all(double.infinity), // Infinite panning
              minScale: 0.05,
              maxScale: 10.0,
              // Only enable pan and zoom with 2+ fingers (or ctrl+scroll/alt+scroll on web/desktop)
              panEnabled: _pointerCount >= 2,
              scaleEnabled: _pointerCount >= 2,
              constrained: false, // Allow panning beyond initial viewport
              child: Container(
                // Define a large but finite canvas area
                // Using double.infinity can cause layout issues in some cases
                width: 100000,
                height: 100000,
                color: Colors.white, // Background color of the canvas area
                alignment: Alignment.center, // Center the DrawingCanvas initially
                // Pass the controller down for coordinate transformations
                child: DrawingCanvas(
                  transformationController: _transformationController,
                  // Let the canvas know if panning/scaling is active
                  isInteracting: _pointerCount >= 2,
                ),
              ),
            ),
          ),

          // Tool palette using Consumer for efficient updates
          Positioned(
            left: 16,
            top: 16,
            child: Card( // Wrap palette in a Card for better visuals
              elevation: 4.0,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Consumer<DrawingProvider>(
                  builder: (context, drawingProvider, child) {
                    return Column(
                      mainAxisSize: MainAxisSize.min, // Fit content
                      children: [
                        // --- Tools ---
                        ToolButton(
                          icon: Icons.pan_tool_alt_outlined, // Or Icons.mouse
                          isSelected: drawingProvider.currentTool == ElementType.select,
                          onPressed: () => drawingProvider.setTool(ElementType.select),
                          tooltip: 'Select / Move / Resize',
                        ),
                        ToolButton(
                          icon: Icons.edit,
                          isSelected: drawingProvider.currentTool == ElementType.pen,
                          onPressed: () => drawingProvider.setTool(ElementType.pen),
                          tooltip: 'Pen Tool',
                        ),
                        ToolButton(
                          icon: Icons.text_fields,
                          isSelected: drawingProvider.currentTool == ElementType.text,
                          onPressed: () => drawingProvider.setTool(ElementType.text),
                          tooltip: 'Text Tool',
                        ),
                        // Add buttons for shapes when implemented
                        // ToolButton(... ElementType.rectangle ...),
                        // ToolButton(... ElementType.circle ...),
                        // ToolButton(... ElementType.arrow ...),

                        const Divider(height: 16), // Separator

                        // --- Media ---
                        ToolButton(
                          icon: Icons.image,
                          isSelected: false, // Not a persistent tool
                          onPressed: () => Provider.of<DrawingProvider>(context, listen: false).addImageFromGallery(context, _transformationController), // Pass controller
                          tooltip: 'Add Image',
                        ),
                        ToolButton(
                          icon: Icons.videocam,
                          isSelected: false, // Not a persistent tool
                          onPressed: () => Provider.of<DrawingProvider>(context, listen: false).addVideoFromGallery(context, _transformationController), // Pass controller
                          tooltip: 'Add Video',
                        ),

                        const Divider(height: 16), // Separator

                        // --- Color Picker ---
                        GestureDetector(
                          onTap: () => _showColorPicker(context, drawingProvider),
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: drawingProvider.currentColor,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.grey.shade400, width: 1.5),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.grey.withOpacity(0.5),
                                  spreadRadius: 1,
                                  blurRadius: 3,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),

          // Optional: Debug info display
          Positioned(
            bottom: 10,
            right: 10,
            child: Container(
              padding: const EdgeInsets.all(8),
              color: Colors.black.withOpacity(0.6),
              child: Text(
                'Pointers: $_pointerCount\nInteraction: ${_pointerCount >= 2}',
                style: const TextStyle(color: Colors.white, fontSize: 10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Helper method for Color Picker Dialog
  void _showColorPicker(BuildContext context, DrawingProvider provider) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Pick a color'),
          content: SingleChildScrollView(
            child: ColorPicker(
              pickerColor: provider.currentColor,
              onColorChanged: provider.setColor, // Directly use the provider method
              enableAlpha: true, // Allow transparency
              labelTypes: const [ColorLabelType.rgb, ColorLabelType.hex, ColorLabelType.hsv],
              pickerAreaHeightPercent: 0.8,
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Done'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
  }
}

// Reusable Tool Button Widget
class ToolButton extends StatelessWidget {
  final IconData icon;
  final bool isSelected;
  final VoidCallback onPressed;
  final String tooltip;

  const ToolButton({
    super.key,
    required this.icon,
    required this.isSelected,
    required this.onPressed,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Tooltip(
        message: tooltip,
        child: Material(
          // Use theme colors for selection
          color: isSelected ? Theme.of(context).primaryColorLight : Colors.transparent,
          shape: const CircleBorder(),
          elevation: isSelected ? 4 : 0, // More elevation when selected
          child: InkWell(
            onTap: onPressed,
            customBorder: const CircleBorder(), // Ensure ripple effect is circular
            child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              child: Icon(
                icon,
                // Use theme colors
                color: isSelected ? Theme.of(context).primaryColorDark : Colors.black54,
                size: 20, // Slightly smaller icon
              ),
            ),
          ),
        ),
      ),
    );
  }
}