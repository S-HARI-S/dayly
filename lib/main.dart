// lib/main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart'; // Add this import
import 'providers/drawing_provider.dart';
import 'providers/calendar_provider.dart';
import 'widgets/drawing_canvas.dart';
import 'screens/calendar_screen.dart';
import 'models/element.dart';
import 'models/calendar_entry.dart';
import 'widgets/context_toolbar.dart'; // Update to match the actual file name

// Load environment variables before running the app
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized(); // Add this line to ensure Flutter is initialized
  
  try {
    await dotenv.load(fileName: ".env"); // Specify the file name if needed
    print("Environment variables loaded successfully");
  } catch (e) {
    print("Warning: Error loading .env file: $e");
    // Create a default .env if it doesn't exist
    // This allows the app to run without the .env file during development
    dotenv.env['GIPHY_API_KEY'] = 'your_api_key_here'; // Use a placeholder
    print("Using default environment variables");
  }
  
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
  bool _isSaved = false; // Add a new flag to track if the canvas is saved

  @override
  void initState() {
    super.initState();
    _transformationController = TransformationController();
    
    // Center the canvas initially by setting the transform to translate to the center
    // Schedule this for after the initial layout is complete
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _centerCanvas();
    });
  }
  
  // Helper method to center the canvas
  void _centerCanvas() {
    // Get the canvas center coordinates (half of our large canvas size)
    const canvasCenter = Offset(50000, 50000);
    
    // Get the screen size to determine where the viewport center is
    final Size screenSize = MediaQuery.of(context).size;
    
    // Create a translation matrix that positions the center of the canvas
    // at the center of the screen
    final Matrix4 matrix = Matrix4.identity()
      ..translate(
        screenSize.width / 2 - canvasCenter.dx,
        screenSize.height / 2 - canvasCenter.dy,
      );
      
    // Set the transformation
    _transformationController.value = matrix;
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
              _isSaved = false; // Mark as unsaved when user interacts with canvas
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
              boundaryMargin: const EdgeInsets.all(0),
              maxScale: 10.0,
              minScale: 0.05, // Add this parameter to allow zooming out much further
              // Only enable pan and zoom with 2+ fingers (or ctrl+scroll/alt+scroll on web/desktop)
              panEnabled: _pointerCount >= 2,
              scaleEnabled: _pointerCount >= 2,
              constrained: false, // Allow panning beyond initial viewport
              child: Container(
                // Define a large but finite canvas area
                // Using double.infinity can cause layout issues in some cases
                width: 100000 ,
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
                        // Only show actual content creation tools
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
                        const Divider(height: 16), // Separator

                        // --- Media ---
                        ToolButton(
                          icon: Icons.image,
                          isSelected: false, // Not a persistent tool
                          onPressed: () { 
                            _isNewCanvas = false; // Mark as edited when adding media
                            _isSaved = false; // Mark as unsaved when adding media
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
                            _isSaved = false; // Mark as unsaved when adding media
                            Provider.of<DrawingProvider>(context, listen: false)
                              .addVideoFromGallery(context, _transformationController);
                          },
                          tooltip: 'Add Video',
                        ),
                        ToolButton(
                          icon: Icons.gif_box,
                          isSelected: false, // Not a persistent tool
                          onPressed: () {
                            _isNewCanvas = false; // Mark as edited when adding media
                            _isSaved = false; // Mark as unsaved when adding media
                            Provider.of<DrawingProvider>(context, listen: false)
                              .searchAndAddGif(context, _transformationController);
                          },
                          tooltip: 'Search & Add GIF',
                        ),
                        // Add a dedicated button for Sticky Notes in the main toolbar
                        ToolButton(
                          icon: Icons.sticky_note_2,
                          isSelected: false,
                          onPressed: () {
                            _isNewCanvas = false; // Mark as edited
                            _isSaved = false; // Mark as unsaved
                            // Get the canvas center position
                            final Size screenSize = MediaQuery.of(context).size;
                            final Offset screenCenter = Offset(screenSize.width / 2, screenSize.height / 2);
                            try {
                              final Matrix4 inverseMatrix = Matrix4.inverted(_transformationController.value);
                              final canvasPosition = MatrixUtils.transformPoint(inverseMatrix, screenCenter);
                              // Create sticky note at the canvas center
                              Provider.of<DrawingProvider>(context, listen: false)
                                .createStickyNote(canvasPosition);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Sticky note created!'))
                              );
                            } catch (e) {
                              // Fallback if matrix inversion fails
                              Provider.of<DrawingProvider>(context, listen: false)
                                .createStickyNote(const Offset(50000, 50000));
                            }
                          },
                          tooltip: 'Add Sticky Note',
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
      // Add the toolbar to the main drawing screen
      // Show toolbar only if an element is selected
      bottomNavigationBar: Consumer<DrawingProvider>(
        builder: (context, provider, _) {
          return ContextToolbar(
            height: 80.0, 
            isVisible: provider.showContextToolbar,
            onHeightChanged: (height) {
              // Optional: can add UI adjustments when toolbar height changes
            },
          );
        },
      ),
    );
  }

  // Navigate to calendar screen
  void _navigateToCalendar() async {
    // If there are changes, ask to save first
    final drawingProvider = Provider.of<DrawingProvider>(context, listen: false);
    if (!_isNewCanvas && drawingProvider.elements.isNotEmpty && !_isSaved) {
      // Prompt to save only if not saved yet
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
    if (!_isNewCanvas && drawingProvider.elements.isNotEmpty && !_isSaved) {
      // Prompt to save
      final shouldSave = await showDialog<bool>(        context: context,
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
      _isSaved = false; // Reset saved flag
    });
  }

  // Show dialog to name or rename the current canvas
  void _showNameCanvasDialog() {
    final calendarProvider = Provider.of<CalendarProvider>(context, listen: false);
    final drawingProvider = Provider.of<DrawingProvider>(context, listen: false);
    
    // Check if there's a selected entry ID, which means we're working with an existing canvas
    final currentEntry = calendarProvider.currentEntry;
    final currentEntryId = calendarProvider.selectedEntryId;
    
    // It's a rename operation if:
    // 1. There's a selected entry ID (we're working with an existing canvas)
    // 2. The current entry exists
    final isRename = currentEntryId != null && currentEntry != null;
    
    // Get existing title for rename or generate a default title for a new canvas
    String initialTitle = isRename 
        ? currentEntry.title
        : calendarProvider.generateDefaultTitle(calendarProvider.selectedDate);
    
    final titleController = TextEditingController(text: initialTitle);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isRename ? 'Rename Canvas' : 'Name Canvas'),
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

              if (isRename) {
                // Update existing entry with new title
                await calendarProvider.updateEntry(
                  currentEntry.id, 
                  drawingProvider,
                  title: title
                );
                
                setState(() {
                  _isSaved = true; // Mark as saved
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Canvas renamed to "$title"')),
                );
              } else {
                // Create new entry
                final entry = await calendarProvider.saveCurrentDrawing(
                  drawingProvider,
                  title: title,
                );
                
                if (entry != null) {
                  // No longer a new canvas
                  setState(() {
                    _isNewCanvas = false;
                    _isSaved = true; // Mark as saved
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('New canvas "$title" saved')),
                  );
                }
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

    CalendarEntry? entry;
    final currentEntryId = calendarProvider.selectedEntryId;
    
    // If we have a current entry selected and it's not a new canvas, update it
    if (!_isNewCanvas && currentEntryId != null) {
      // Update existing entry
      await calendarProvider.updateEntry(
        currentEntryId, 
        drawingProvider,
        title: calendarProvider.currentEntry?.title ?? 'Canvas'
      );
      entry = calendarProvider.currentEntry;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Canvas "${entry?.title}" updated')),
      );
    } else {
      // Create new entry with default title
      final defaultTitle = calendarProvider.generateDefaultTitle(calendarProvider.selectedDate);
      entry = await calendarProvider.saveCurrentDrawing(drawingProvider, title: defaultTitle);
      
      if (entry != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('New canvas "${entry.title}" saved')),
        );
      }
    }
    
    // No longer a new canvas
    setState(() {
      _isNewCanvas = false;
      _isSaved = true; // Mark as saved
    });
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

// Reusable Tool Button Widget with improved touch target and accessibility
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
    const double buttonSize = 44.0; // Increased button size for better touch target
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Tooltip(
        message: tooltip,
        waitDuration: const Duration(milliseconds: 500), // Show tooltip after a short delay
        child: Material(
          color: isSelected ? Theme.of(context).primaryColorLight : Colors.transparent,
          shape: const CircleBorder(),
          elevation: isSelected ? 4 : 0, // More elevation when selected
          child: InkWell(
            onTap: onPressed,
            customBorder: const CircleBorder(),
            child: Container(
              width: buttonSize,
              height: buttonSize,
              alignment: Alignment.center,
              child: Icon(
                icon,
                color: isSelected ? Theme.of(context).primaryColorDark : Colors.black54,
                size: 22, // Slightly larger icon
                semanticLabel: tooltip, // Add semantic label for accessibility
              ),
            ),
          ),
        ),
      ),
    );
  }
}