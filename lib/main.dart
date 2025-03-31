// lib/main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'providers/drawing_provider.dart';
import 'widgets/drawing_canvas.dart';
import 'models/element.dart';

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
      title: 'Flutter TLDraw Clone',
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: const DrawingBoard(),
    );
  }
}

class DrawingBoard extends StatefulWidget {
  const DrawingBoard({super.key});

  @override
  State<DrawingBoard> createState() => _DrawingBoardState();
}

class _DrawingBoardState extends State<DrawingBoard> {
  // Track the number of active pointers
  int _pointerCount = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Flutter TLDraw Clone'),
        actions: [
          IconButton(
            icon: const Icon(Icons.undo),
            onPressed:
                () =>
                    Provider.of<DrawingProvider>(context, listen: false).undo(),
            tooltip: 'Undo',
          ),
          IconButton(
            icon: const Icon(Icons.redo),
            onPressed:
                () =>
                    Provider.of<DrawingProvider>(context, listen: false).redo(),
            tooltip: 'Redo',
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed:
                () =>
                    Provider.of<DrawingProvider>(
                      context,
                      listen: false,
                    ).deleteSelected(),
            tooltip: 'Delete Selected',
          ),
          IconButton(
            icon: const Icon(Icons.group_work),
            onPressed:
                () =>
                    Provider.of<DrawingProvider>(
                      context,
                      listen: false,
                    ).groupSelected(),
            tooltip: 'Group Selected',
          ),
          IconButton(
            icon: const Icon(Icons.call_split),
            onPressed:
                () =>
                    Provider.of<DrawingProvider>(
                      context,
                      listen: false,
                    ).ungroupSelected(),
            tooltip: 'Ungroup Selected',
          ),
        ],
      ),
      body: Stack(
        children: [
          // Use a stack of listeners to properly manage pointer events
          Stack(
            children: [
              // This listener only tracks pointer counts
              Listener(
                onPointerDown: (PointerDownEvent event) {
                  setState(() {
                    _pointerCount++;
                  });
                },
                onPointerUp: (PointerUpEvent event) {
                  setState(() {
                    _pointerCount = _pointerCount > 0 ? _pointerCount - 1 : 0;
                  });
                },
                onPointerCancel: (PointerCancelEvent event) {
                  setState(() {
                    _pointerCount = _pointerCount > 0 ? _pointerCount - 1 : 0;
                  });
                },
                // Make this listener transparent to user interaction
                behavior: HitTestBehavior.translucent,
                child: InteractiveViewer(
                  boundaryMargin: const EdgeInsets.all(0),
                  minScale: 0.1,
                  maxScale: 5.0,
                  // Only enable pan and zoom with 2+ fingers
                  panEnabled: _pointerCount >= 2,
                  scaleEnabled: _pointerCount >= 2,
                  constrained: false,
                  child: Container(
                    width: 100000,
                    height: 100000,
                    alignment: Alignment.center,
                    color: Colors.white,
                    child: DrawingCanvas(isPanning: _pointerCount >= 2),
                  ),
                ),
              ),
            ],
          ),

          // Tool palette
          Positioned(
            left: 16,
            top: 16,
            child: Consumer<DrawingProvider>(
              builder: (context, drawingProvider, child) {
                return Column(
                  children: [
                    // Update in lib/main.dart

                    // Add these lines in the toolbar Column in _DrawingBoardState
                    ToolButton(
                      icon: Icons.image,
                      isSelected: false,
                      onPressed:
                          () => Provider.of<DrawingProvider>(
                            context,
                            listen: false,
                          ).addImageFromGallery(context),
                      tooltip: 'Add Image',
                    ),
                    ToolButton(
                      icon: Icons.videocam,
                      isSelected: false,
                      onPressed:
                          () => Provider.of<DrawingProvider>(
                            context,
                            listen: false,
                          ).addVideoFromGallery(context),
                      tooltip: 'Add Video',
                    ),
                    ToolButton(
                      icon: Icons.edit,
                      isSelected:
                          drawingProvider.currentTool == ElementType.pen,
                      onPressed: () => drawingProvider.setTool(ElementType.pen),
                      tooltip: 'Pen Tool',
                    ),
                    ToolButton(
                      icon: Icons.rectangle_outlined,
                      isSelected:
                          drawingProvider.currentTool == ElementType.rectangle,
                      onPressed:
                          () => drawingProvider.setTool(ElementType.rectangle),
                      tooltip: 'Rectangle Tool',
                    ),
                    ToolButton(
                      icon: Icons.circle_outlined,
                      isSelected:
                          drawingProvider.currentTool == ElementType.circle,
                      onPressed:
                          () => drawingProvider.setTool(ElementType.circle),
                      tooltip: 'Circle Tool',
                    ),
                    ToolButton(
                      icon: Icons.arrow_forward,
                      isSelected:
                          drawingProvider.currentTool == ElementType.arrow,
                      onPressed:
                          () => drawingProvider.setTool(ElementType.arrow),
                      tooltip: 'Arrow Tool',
                    ),
                    ToolButton(
                      icon: Icons.text_fields,
                      isSelected:
                          drawingProvider.currentTool == ElementType.text,
                      onPressed:
                          () => drawingProvider.setTool(ElementType.text),
                      tooltip: 'Text Tool',
                    ),
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (BuildContext context) {
                            return AlertDialog(
                              title: const Text('Pick a color'),
                              content: SingleChildScrollView(
                                child: ColorPicker(
                                  pickerColor: drawingProvider.currentColor,
                                  onColorChanged: drawingProvider.setColor,
                                  enableAlpha: true,
                                  labelTypes: const [ColorLabelType.rgb],
                                ),
                              ),
                              actions: <Widget>[
                                TextButton(
                                  child: const Text('Done'),
                                  onPressed: () {
                                    Navigator.of(context).pop();
                                  },
                                ),
                              ],
                            );
                          },
                        );
                      },
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: drawingProvider.currentColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.grey),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),

          // Add debug info for testing
          Positioned(
            bottom: 10,
            right: 10,
            child: Container(
              padding: const EdgeInsets.all(8),
              color: Colors.black.withOpacity(0.7),
              child: Text(
                'Pointers: $_pointerCount\nPan enabled: ${_pointerCount >= 2}',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

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
          color: isSelected ? Colors.blue.withOpacity(0.2) : Colors.white,
          shape: const CircleBorder(),
          elevation: isSelected ? 4 : 1,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              child: Icon(
                icon,
                color: isSelected ? Colors.blue : Colors.black54,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
