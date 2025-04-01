// lib/main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'providers/drawing_provider.dart';
import 'providers/calendar_provider.dart';
import 'widgets/drawing_canvas.dart';
import 'screens/calendar_screen.dart';
import 'models/element.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => DrawingProvider()),
        ChangeNotifierProvider(create: (_) => CalendarProvider()),
      ],
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
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const DrawingBoard(),
      debugShowCheckedModeBanner: false,
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
  bool _isNewCanvas = true;

  @override
  void initState() {
    super.initState();
    _transformationController = TransformationController();
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Consumer<CalendarProvider>(
          builder: (context, provider, child) {
            final entry = provider.currentEntry;
            if (entry != null) {
              return Text(
                entry.title.isNotEmpty
                    ? entry.title
                    : 'Canvas - ${entry.date.month}/${entry.date.day}'
              );
            }
            return const Text('New Canvas');
          },
        ),
        actions: [
          // Calendar View Button
          IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: () => _navigateToCalendar(),
            tooltip: 'Calendar View',
          ),
          // Save Button
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: () => _saveCurrentCanvas(),
            tooltip: 'Save Canvas',
          ),
          // Add button to name/rename canvas
          IconButton(
            icon: const Icon(Icons.edit_note),
            onPressed: () => _showNameCanvasDialog(),
            tooltip: 'Name Canvas',
          ),
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
        ],
      ),
      body: Stack(
        children: [
          // Listener to track pointer count for enabling/disabling InteractiveViewer pan/zoom
          Listener(
            onPointerDown: (PointerDownEvent event) {
              setState(() {
                _pointerCount++;
              });
              // Mark as edited once user interacts with canvas
              if (_isNewCanvas) {
                _isNewCanvas = false;
              }
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
            child: Card(
              // Wrap palette in a Card for better visuals
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
                          onPressed: () { 
                            _isNewCanvas = false; // Mark as edited when adding media
                            Provider.of<DrawingProvider>(context, listen: false)
                              .addImageFromGallery(context, _transformationController); 
                          },
                          tooltip: 'Add Image',
                        ),
                        ToolButton(
                          icon: Icons.videocam,
                          isSelected: false, // Not a persistent tool
                          onPressed: () {
                            _isNewCanvas = false; // Mark as edited when adding media
                            Provider.of<DrawingProvider>(context, listen: false)
                              .addVideoFromGallery(context, _transformationController);
                          },
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

          // Status indicator - show if this is a new or edited canvas
          Positioned(
            top: 10,
            right: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _isNewCanvas ? Icons.fiber_new : Icons.edit,
                    color: Colors.white,
                    size: 16,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _isNewCanvas ? 'New Canvas' : 'Edited',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),

          // Debug info display
          Positioned(
            bottom: 10,
            right: 10,
            child: Container(
              padding: const EdgeInsets.all(8),
              color: Colors.black.withOpacity(0.6),
              child: Consumer<CalendarProvider>(
                builder: (context, calendarProvider, child) {
                  final currentEntry = calendarProvider.currentEntry;
                  final canvasInfo = currentEntry != null
                      ? 'Canvas: ${currentEntry.title.isNotEmpty ? currentEntry.title : 'Untitled'}'
                      : 'New Canvas';

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        canvasInfo,
                        style: const TextStyle(color: Colors.white, fontSize: 10),
                      ),
                      Text(
                        'Pointers: $_pointerCount\nInteraction: ${_pointerCount >= 2}',
                        style: const TextStyle(color: Colors.white, fontSize: 10),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () => _createNewCanvas(),
        tooltip: 'Create New Canvas',
      ),
    );
  }

  // Navigate to calendar screen
  void _navigateToCalendar() async {
    // If there are changes, ask to save first
    final drawingProvider = Provider.of<DrawingProvider>(context, listen: false);
    if (!_isNewCanvas && drawingProvider.elements.isNotEmpty) {
      // Prompt to save
      final shouldSave = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Save Changes?'),
          content: const Text('Do you want to save your changes before viewing the calendar?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('NO'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('YES'),
            ),
          ],
        ),
      );
      
      if (shouldSave == true) {
        await _saveCurrentCanvas();
      }
    }
    
    // Navigate to calendar
    if (mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => const CalendarScreen(),
        ),
      );
    }
  }

  // Create a new blank canvas
  void _createNewCanvas() async {
    final drawingProvider = Provider.of<DrawingProvider>(context, listen: false);
    final calendarProvider = Provider.of<CalendarProvider>(context, listen: false);
    
    // If there are changes in the current canvas, ask to save first
    if (!_isNewCanvas && drawingProvider.elements.isNotEmpty) {
      // Prompt to save
      final shouldSave = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Save Current Canvas?'),
          content: const Text('Do you want to save your current canvas before creating a new one?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('NO'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('YES'),
            ),
          ],
        ),
      );
      
      if (shouldSave == true) {
        await _saveCurrentCanvas();
      }
    }
    
    // Clear current drawing and reset tools
    drawingProvider.elements = [];
    drawingProvider.currentElement = null;
    drawingProvider.setTool(ElementType.select);
    
    // Reset selection in calendar provider to today but don't select any specific entry
    calendarProvider.selectDate(DateTime.now());
    
    // Mark as new canvas
    setState(() {
      _isNewCanvas = true;
    });
  }

  // Show dialog to name or rename the current canvas
  void _showNameCanvasDialog() {
    final calendarProvider = Provider.of<CalendarProvider>(context, listen: false);
    final drawingProvider = Provider.of<DrawingProvider>(context, listen: false);

    // Get a default title for the new canvas
    String defaultTitle = calendarProvider.generateDefaultTitle(calendarProvider.selectedDate);
    
    final titleController = TextEditingController(text: defaultTitle);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Name Canvas'),
        content: TextField(
          controller: titleController,
          decoration: const InputDecoration(
            labelText: 'Canvas Title',
            hintText: 'Enter a title for this canvas',
          ),
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () async {
              final title = titleController.text;

              // Always save as a new entry
              final entry = await calendarProvider.saveCurrentDrawing(
                drawingProvider,
                title: title,
              );
              
              if (entry != null) {
                // No longer a new canvas
                setState(() {
                  _isNewCanvas = false;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('New canvas "$title" saved')),
                );
              }

              if (mounted) Navigator.of(context).pop();
            },
            child: const Text('SAVE'),
          ),
        ],
      ),
    );
  }

  // Save current canvas to calendar
  Future<void> _saveCurrentCanvas() async {
    final drawingProvider = Provider.of<DrawingProvider>(context, listen: false);
    final calendarProvider = Provider.of<CalendarProvider>(context, listen: false);

    // Check if there's anything to save
    if (drawingProvider.elements.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nothing to save - canvas is empty')),
      );
      return;
    }

    // Always save as a new entry to allow multiple canvases per day
    final defaultTitle = calendarProvider.generateDefaultTitle(calendarProvider.selectedDate);
    final entry = await calendarProvider.saveCurrentDrawing(drawingProvider, title: defaultTitle);
    
    if (entry != null) {
      // No longer a new canvas
      setState(() {
        _isNewCanvas = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('New canvas "${entry.title}" saved')),
      );
    }
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