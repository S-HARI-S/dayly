// lib/providers/drawing_provider.dart
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:vector_math/vector_math_64.dart' show Matrix4, MatrixUtils, Vector3;
import 'package:collection/collection.dart';
import 'package:giphy_picker/giphy_picker.dart';
// import 'package:http/http.dart' as http; // Still not needed here
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:uuid/uuid.dart';

// Ensure correct paths for your project structure
import '../models/element.dart';
import '../models/pen_element.dart';
import '../models/text_element.dart';
import '../models/image_element.dart';
import '../models/video_element.dart';
import '../models/gif_element.dart';
import '../models/handles.dart';
import '../services/background_removal_service.dart';
import '../models/note_element.dart'; // Make sure this import is correct

class DrawingProvider extends ChangeNotifier {
  // --- State Properties ---
  List<DrawingElement> elements = [];
  DrawingElement? currentElement;
  ElementType currentTool = ElementType.select;
  Color currentColor = Colors.black;
  double currentStrokeWidth = 2.0;
  List<String> selectedElementIds = [];

  // Add navigatorKey field
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  // Undo/Redo Stacks
  List<List<DrawingElement>> undoStack = [];
  List<List<DrawingElement>> redoStack = [];
  static const int maxUndoSteps = 50;

  // State tracking for move/resize operations
  bool _didMoveOccur = false;
  bool _didResizeOccur = false;
  bool _didRotationOccur = false; // Add rotation state tracking

  // Unique ID generator
  final _uuid = const Uuid();

  // Ensure proper initialization and clearer debug logging
  bool _showContextToolbar = false;
  bool get showContextToolbar {
    final isVisible = _showContextToolbar && selectedElementIds.isNotEmpty;
    // Removed the warning here as the setter logic prevents this state
    // if (_showContextToolbar && selectedElementIds.isEmpty) {
    //   print("WARNING: Context toolbar flag is true but no selected elements");
    // }
    return isVisible;
  }

  set showContextToolbar(bool value) {
    if (_showContextToolbar != value) {
      // Don't enable toolbar if no elements are selected when trying to set true
      if (value && selectedElementIds.isEmpty) {
        print("Warning: Attempting to show toolbar with no selected elements - ignoring");
        _showContextToolbar = false; // Ensure it's false if selection is empty
        notifyListeners(); // Always notify listeners to ensure UI updates
        return; // Don't proceed further
      }

      _showContextToolbar = value;
      print("Context toolbar visibility set to: $value (selected elements: ${selectedElementIds.length})");
      notifyListeners();
    }
  }


  // --- Tool and Style Management ---
  void setTool(ElementType tool) {
    // Hide toolbar when changing tools, unless staying on select
    if (tool != ElementType.select && currentTool == ElementType.select) {
        _showContextToolbar = false;
    }
    // If switching *to* select, don't change toolbar visibility here,
    // let selection logic handle it.

    currentTool = tool;
    // Clear selection ONLY if switching AWAY from the select tool
    if (tool != ElementType.select) {
        clearSelection(); // This will also hide the toolbar and notify
    } else {
        notifyListeners(); // Notify if staying on select tool (e.g., for potential UI updates)
    }
  }

  void setColor(Color color) {
    currentColor = color;
    if (currentTool == ElementType.select && selectedElementIds.isNotEmpty) {
      saveToUndoStack();
      bool changed = false;
      List<DrawingElement> updatedElements = List.from(elements);
      for (int i = 0; i < updatedElements.length; i++) {
        if (selectedElementIds.contains(updatedElements[i].id)) {
          // Update color for elements that support it
          if (updatedElements[i] is PenElement) {
              updatedElements[i] = (updatedElements[i] as PenElement).copyWith(color: color);
              changed = true;
          } else if (updatedElements[i] is TextElement) {
              updatedElements[i] = (updatedElements[i] as TextElement).copyWith(color: color);
              changed = true;
          } else if (updatedElements[i] is NoteElement) { // Add NoteElement color update
              updatedElements[i] = (updatedElements[i] as NoteElement).copyWith(backgroundColor: color);
              changed = true;
          }
          // Add other element types here if they support color changes
        }
      }
      if (changed) {
        elements = updatedElements;
        notifyListeners();
      }
    } else {
        notifyListeners(); // Notify even if no element color changed (e.g., for tool color preview)
    }
  }


  void setStrokeWidth(double width) {
    currentStrokeWidth = width;
    if (currentTool == ElementType.select && selectedElementIds.isNotEmpty) {
      saveToUndoStack();
      bool changed = false;
      List<DrawingElement> updatedElements = List.from(elements);
      for (int i = 0; i < updatedElements.length; i++) {
        if (selectedElementIds.contains(updatedElements[i].id)) {
          if (updatedElements[i] is PenElement) {
              updatedElements[i] = (updatedElements[i] as PenElement).copyWith(strokeWidth: width);
              changed = true;
          }
          // Add other element types if they support stroke width
        }
      }
      if (changed) {
          elements = updatedElements;
          notifyListeners();
      }
    } else {
        notifyListeners(); // Notify for tool preview update
    }
  }


  // --- Undo/Redo Core ---
  void saveToUndoStack() {
    try {
      final List<DrawingElement> clonedElements = elements.map((el) => el.clone()).toList();
      
      // Skip if state is unchanged (avoid duplicate entries)
      if (undoStack.isNotEmpty && 
          listEquals(undoStack.last.map((e) => e.hashCode).toList(), 
                    clonedElements.map((e) => e.hashCode).toList())) {
        return;
      }
      
      undoStack.add(clonedElements);
      
      // Keep undo stack within size limit
      if (undoStack.length > maxUndoSteps) {
        undoStack.removeAt(0);
      }
      
      redoStack.clear(); // Clear redo stack on new action
    } catch (e, s) {
      print("Error saving to undo stack: $e\n$s");
    }
  }

  void undo() {
    if (undoStack.isEmpty) return;
    
    try {
      // Save current state to redo stack
      final List<DrawingElement> currentState = elements.map((e) => e.clone()).toList();
      redoStack.add(currentState);
      
      // Keep redo stack within size limit
      if (redoStack.length > maxUndoSteps) {
        redoStack.removeAt(0);
      }
      
      // Restore previous state
      elements = undoStack.removeLast();
    } catch (e, s) {
      print("Error restoring from undo stack: $e\n$s");
    }
    notifyListeners();
  }

  void redo() {
    if(redoStack.isEmpty) {
      print("Redo stack empty");
      return;
    }
    try {
      // Save current state to undo stack BEFORE applying redo state
      undoStack.add(elements.map((e) => e.clone()).toList());
      if(undoStack.length > maxUndoSteps) undoStack.removeAt(0);
    } catch(e, s) {
      print("Error saving current state before redo: $e\n$s");
    }
    // Restore the next state from redo stack
    elements = redoStack.removeLast();
    selectedElementIds.clear(); // Clear selection after undo/redo
    _showContextToolbar = false; // Hide toolbar
    notifyListeners();
    print("Redo performed (${redoStack.length} states remain)");
  }


  // --- Element Creation ---
  Offset _getCanvasCenter(TransformationController controller, BuildContext context) {
    final Size screenSize = MediaQuery.of(context).size;
    // Approximate center considering potential padding/app bars might be needed for perfect center
    final Offset screenCenter = Offset(screenSize.width / 2, screenSize.height / 2);
    try {
      final Matrix4 inverseMatrix = Matrix4.inverted(controller.value);
      return MatrixUtils.transformPoint(inverseMatrix, screenCenter);
    } catch (e) {
      print("Error getting canvas center: $e. Using fallback.");
      // Fallback to a large coordinate in case matrix is non-invertible
      return const Offset(50000, 50000);
    }
  }

   // --- GIF Handling ---

  Future<void> searchAndAddGif(BuildContext context, TransformationController controller) async {
    print("--- Starting searchAndAddGif ---");
    try {
      final apiKey = dotenv.env['GIPHY_API_KEY'] ?? '';
      if (apiKey.isEmpty) {
        throw Exception('Giphy API key not found in .env file');
      }

      print("Showing Giphy Picker...");
      final gif = await GiphyPicker.pickGif(
        context: context,
        apiKey: apiKey,
        showPreviewPage: false, // <--- ***** MAKE SURE THIS LINE IS PRESENT AND SET TO false *****
        lang: GiphyLanguage.english,
        fullScreenDialog: true,
        searchHintText: 'Search for GIFs...',
      );

      // --- Check the result ---
      if (gif == null) {
        print("<<< GiphyPicker.pickGif returned NULL >>>");
        if (context.mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
             const SnackBar(content: Text('GIF selection cancelled or failed.')),
           );
        }
        return;
      } else {
        print(">>> GiphyPicker.pickGif returned a GiphyGif object! <<<");
        print("    GIF Title: ${gif.title}");
        print("    GIF Original URL: ${gif.images.original?.url}");
      }
      // --- End Check ---

      if (!context.mounted) {
          print("Context became invalid after picking GIF.");
          return;
      }

      print("Calling _addGifToCanvas...");
      _addGifToCanvas(gif, controller, context); // This should now be called

    } catch (e, s) {
      print('!!! Error during GIF search/pick: $e');
      print('!!! Stack trace: $s');
      if(context.mounted){
         ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text('Error adding GIF: ${e.toString()}')),
         );
      }
    }
    print("--- Finished searchAndAddGif ---");
  }

void _addGifToCanvas(GiphyGif gif, TransformationController controller, BuildContext context) {
  print("--- Starting _addGifToCanvas ---"); // DEBUG
  try {
    // --- 1. Get URLs ---
    final gifUrl = gif.images.original?.url;
    final previewUrl = gif.images.previewGif?.url ?? gif.images.fixedWidth?.url;
    print("    GIF URL: $gifUrl"); // DEBUG
    print("    Preview URL: $previewUrl"); // DEBUG

    if (gifUrl == null) {
      throw Exception('Could not retrieve a valid GIF URL');
    }

    // --- 2. Calculate Size ---
    const double desiredWidth = 250.0;
    final double? imgWidth = double.tryParse(gif.images.original?.width ?? '0');
    final double? imgHeight = double.tryParse(gif.images.original?.height ?? '0');
    double aspectRatio = 1.0;
    if (imgWidth != null && imgHeight != null && imgWidth > 0 && imgHeight > 0) {
        aspectRatio = imgWidth / imgHeight;
    }
    final size = Size(desiredWidth, desiredWidth / aspectRatio);
    print("    Calculated Size: $size (Aspect Ratio: $aspectRatio)"); // DEBUG

    // --- 3. Calculate Position (Center of View) ---
    final Offset canvasCenter = _getCanvasCenter(controller, context);
    final position = canvasCenter - Offset(size.width / 2, size.height / 2);
    print("    Calculated Position: $position (Canvas Center: $canvasCenter)"); // DEBUG

    // --- 4. Save Undo State ---
    print("    Saving state to undo stack..."); // DEBUG
    saveToUndoStack();

    // --- 5. Create GifElement ---
    final newGifElement = GifElement(
      id: _uuid.v4(),
      position: position,
      size: size,
      gifUrl: gifUrl,
      previewUrl: previewUrl,
    );
    print("    Created GifElement with ID: ${newGifElement.id}"); // DEBUG

    // --- 6. Add to List ---
    elements.add(newGifElement);
    print("    Added GifElement to list. Total elements now: ${elements.length}"); // DEBUG

    // --- 7. Finalize ---
    print("    Clearing selection and selecting new GIF..."); // DEBUG
    clearSelection();
    selectElement(newGifElement);
    print("    Calling notifyListeners()..."); // DEBUG
    notifyListeners();

    print("    Showing SnackBar confirmation..."); // DEBUG
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('GIF added to canvas')),
    );

  } catch (e, s) { // Catch errors and print stack trace
    print('!!! Error adding GIF to canvas: $e'); // DEBUG
    print('!!! Stack trace: $s'); // DEBUG
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Error adding GIF: ${e.toString()}')),
    );
  }
  print("--- Finished _addGifToCanvas ---"); // DEBUG
}

  // --- Image Handling ---
  Future<void> addImageFromGallery(BuildContext context, TransformationController controller) async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);
      if (pickedFile == null || !context.mounted) return;

      saveToUndoStack();

      // Load the image file
      final File imageFile = File(pickedFile.path);
      final Uint8List imageBytes = await imageFile.readAsBytes();
      final ui.Image image = await decodeImageFromList(imageBytes);

      // Calculate size maintaining aspect ratio
      final aspectRatio = image.width / image.height;
      const width = 300.0; // Default width
      final height = width / aspectRatio;

      // Calculate position to center the image on the canvas
      final position = _getCanvasCenter(controller, context) - Offset(width / 2, height / 2);

      final newImage = ImageElement(
        id: _uuid.v4(),
        position: position,
        image: image,
        size: Size(width, height),
        imagePath: pickedFile.path,
      );

      elements.add(newImage);
      clearSelection();
      selectElement(newImage); // Select the newly added image

      print("Added image element ${newImage.id} with path: ${pickedFile.path}");
    } catch (e) {
      print("Error adding image: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error adding image: $e')),
      );
    }
  }


  // --- Video Handling ---
  Future<void> addVideoFromGallery(BuildContext context, TransformationController controller) async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickVideo(source: ImageSource.gallery);
      if (pickedFile == null || !context.mounted) return;

      // It's crucial to create the controller BEFORE calculating size/position
      final videoController = VideoPlayerController.file(File(pickedFile.path));
      await videoController.initialize(); // Initialize to get aspect ratio

      const double desiredWidth = 320;
      final double aspectRatio = videoController.value.isInitialized && videoController.value.aspectRatio != 0
          ? videoController.value.aspectRatio
          : 16 / 9; // Default to 16:9 if initialization fails or aspect ratio is zero
      final size = Size(desiredWidth, desiredWidth / aspectRatio);

      final position = _getCanvasCenter(controller, context) - Offset(size.width / 2, size.height / 2);

      saveToUndoStack();

      final newVideoElement = VideoElement(
        id: _uuid.v4(),
        videoUrl: pickedFile.path,
        controller: videoController, // Pass the initialized controller
        position: position,
        size: size,
      );

      elements.add(newVideoElement);
      clearSelection();
      selectElement(newVideoElement); // Selects and notifies

    } catch (e) {
      print('Error adding video: $e');
      if(context.mounted){
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error adding video: ${e.toString()}')),
          );
      }
    }
  }

  // --- Text Handling ---
  // Updated to accept position parameter
  void addTextElement(String text, Offset position) {
    saveToUndoStack();

    // Create a temporary TextElement to calculate its size
    final tempText = TextElement(
      position: position,
      text: text,
      color: currentColor,
      fontSize: 24.0,
    );

    // Calculate the center position based on the text size
    final textSize = tempText.bounds.size;
    final centeredPosition = position - Offset(textSize.width / 2, textSize.height / 2);

    // Create the actual TextElement with the centered position
    final newText = TextElement(
      id: _uuid.v4(),
      position: centeredPosition,
      text: text,
      color: currentColor,
      fontSize: 24.0,
    );

    elements.add(newText);
    clearSelection();
    selectElement(newText); // Select the newly added text

    print("Added text element ${newText.id} at $centeredPosition");
  }


  // --- Drawing Lifecycle (Pen Tool) ---
  void startDrawing(Offset position) {
    if (currentTool != ElementType.pen) return;
    saveToUndoStack(); // Save state *before* starting a new element
    currentElement = PenElement(
      id: _uuid.v4(), // Assign ID at start
      position: position, // Initial position (used for bounds calculation)
      points: [position], // Start with the first point
      color: currentColor,
      strokeWidth: currentStrokeWidth,
    );
    notifyListeners(); // Update UI to show the start of the line
  }

  void updateDrawing(Offset position) {
    if (currentElement is! PenElement) return;
    // Avoid adding duplicate points
    if ((currentElement as PenElement).points.isNotEmpty && (currentElement as PenElement).points.last == position) return;

    final pen = currentElement as PenElement;
    // Use copyWith to update points immutably
    currentElement = pen.copyWith(
      points: List.from(pen.points)..add(position)
    );
    notifyListeners(); // Update UI to show the line extending
  }


  void endDrawing() {
    if (currentElement is! PenElement) {
        currentElement = null; // Clear if not a pen element for some reason
        return;
    }
    final pen = currentElement as PenElement;

    // Only add the element if it has enough points to be visible
    bool isValid = pen.points.length >= 2;

    if (isValid) {
      // No need to saveToUndoStack here, it was saved at startDrawing
      elements.add(pen); // Add the final element to the main list
    } else {
        // If invalid, we need to revert the state saved at startDrawing
        if (undoStack.isNotEmpty) {
          undoStack.removeLast(); // Remove the state saved at startDrawing
          print("Drawing discarded (too short), reverted undo state.");
        } else {
          print("Drawing discarded (too short), undo stack was empty.");
        }
    }
    currentElement = null; // Clear the temporary drawing element
    notifyListeners();
  }


  void discardDrawing() {
    if (currentElement == null) return;
    if (currentElement is PenElement) {
        // Revert the state saved at startDrawing
        if (undoStack.isNotEmpty) {
          undoStack.removeLast(); // Remove the state saved at startDrawing
          print("Drawing discarded, reverted undo state.");
        } else {
          print("Drawing discarded, undo stack was empty.");
        }
    }
    print("Drawing discarded");
    currentElement = null; // Clear the temporary drawing element
    notifyListeners();
  }

  // --- Selection and Interaction ---
  void selectElementAt(Offset position) {
    // Find the topmost element at the given position
    for (int i = elements.length - 1; i >= 0; i--) {
      final element = elements[i];
      if (element.containsPoint(position)) {
        selectElement(element);
        return;
      }
    }
    clearSelection();
  }


  void selectElement(DrawingElement element) {
    clearSelection(notify: false);
    selectedElementIds.add(element.id);
    _showContextToolbar = true;
    notifyListeners();
  }

  void showContextToolbarForElement(String elementId) {
    if (!selectedElementIds.contains(elementId)) {
      selectElement(elements.firstWhere((e) => e.id == elementId));
    }
    _showContextToolbar = true;
    notifyListeners();
  }


  void clearSelection({bool notify = true}) {
    selectedElementIds.clear();
    _showContextToolbar = false;
    if (notify) notifyListeners();
  }


  void deleteSelected() {
    if (selectedElementIds.isEmpty) return;
    
    saveToUndoStack();
    elements.removeWhere((element) => selectedElementIds.contains(element.id));
    clearSelection();
    notifyListeners();
  }


  // --- Move Logic ---
  void startPotentialMove() {
    _didMoveOccur = false;
  }

  void moveSelected(Offset delta) {
    if (selectedElementIds.isEmpty || (delta.dx == 0 && delta.dy == 0)) return;
    
    _didMoveOccur = true;
    // Create a new list instead of modifying elements in-place
    // This ensures the change is recognized by shouldRebuild checks
    final List<DrawingElement> updatedElements = List.from(elements);
    
    for (int i = 0; i < updatedElements.length; i++) {
      if (selectedElementIds.contains(updatedElements[i].id)) {
        updatedElements[i] = updatedElements[i].copyWith(
          position: updatedElements[i].position + delta,
        );
      }
    }
    
    elements = updatedElements; // Replace entire list to trigger rebuild
    
    // Instantly notify listeners to ensure UI updates immediately
    notifyListeners();
  }

  void endPotentialMove() {
    if (_didMoveOccur) {
      saveToUndoStack();
    }
  }


  // --- Resize Logic ---
  void startPotentialResize() {
    _didResizeOccur = false;
  }

  void resizeSelected(String elementId, ResizeHandleType handle, Offset delta, Offset currentPointerPos, Offset startPointerPos) {
    int index = elements.indexWhere((el) => el.id == elementId);
    if (index == -1) return;
    final currentElement = elements[index];
    Rect currentBounds = currentElement.bounds;
    if (currentBounds.isEmpty) return;

    Offset newPosition = currentElement.position;
    Size newSize = currentBounds.size;
    DrawingElement? updatedElement;

    // --- Specific Logic for NoteElement ---
    if (currentElement is NoteElement) {
      final note = currentElement;
      double newFontSize = note.fontSize; // Start with current font size

      const double minNoteWidth = NoteElement.MIN_WIDTH;
      const double minNoteHeight = NoteElement.MIN_HEIGHT;
      const double minFontSize = 8.0;
      const double maxFontSize = 100.0;

      Offset fixedPoint = Offset.zero; // The corner/point opposite the dragged handle
      bool isHorizontalHandle = (handle == ResizeHandleType.middleLeft || handle == ResizeHandleType.middleRight);

      // Determine fixed point
      switch (handle) {
        case ResizeHandleType.topLeft: fixedPoint = currentBounds.bottomRight; break;
        case ResizeHandleType.topRight: fixedPoint = currentBounds.bottomLeft; break;
        case ResizeHandleType.bottomLeft: fixedPoint = currentBounds.topRight; break;
        case ResizeHandleType.bottomRight: fixedPoint = currentBounds.topLeft; break;
        case ResizeHandleType.topMiddle: fixedPoint = currentBounds.bottomCenter; break;
        case ResizeHandleType.bottomMiddle: fixedPoint = currentBounds.topCenter; break;
        case ResizeHandleType.middleLeft: fixedPoint = currentBounds.centerRight; break;
        case ResizeHandleType.middleRight: fixedPoint = currentBounds.centerLeft; break;
        case ResizeHandleType.rotate:
          print("Rotation handle triggered in resizeSelected - ignoring.");
          return;
      }

      double calculatedWidth = currentBounds.width;
      double calculatedHeight = currentBounds.height;

      // 1. Calculate new dimensions and potentially font size based on handle type
      if (isHorizontalHandle) {
        // --- Horizontal Middle Handles: Adjust Width, Keep Font Size, Calculate Height ---
        newFontSize = note.fontSize; // Font size does NOT change

        // Calculate new width based on pointer relative to the opposite side
        if (handle == ResizeHandleType.middleLeft) {
          calculatedWidth = fixedPoint.dx - currentPointerPos.dx;
        } else { // middleRight
          calculatedWidth = currentPointerPos.dx - fixedPoint.dx;
        }
        calculatedWidth = calculatedWidth.clamp(minNoteWidth, double.infinity);

        // Calculate required height based on the *new* width and *current* font size
        Size contentFitSize = NoteElement.calculateSizeForContent(
          note.title,
          note.content,
          newFontSize,
          targetWidth: calculatedWidth, // Use the calculated width
          minHeight: minNoteHeight
        );
        calculatedHeight = contentFitSize.height; // Height is determined by content flow

      } else {
        // --- Corner & Vertical Handles: Scale Width & Font Size, Calculate Height ---
        double scaleY = 1.0;
        if (currentBounds.height > 1e-6) { // Avoid division by zero
          double potentialHeight = (handle == ResizeHandleType.topMiddle || handle == ResizeHandleType.topLeft || handle == ResizeHandleType.topRight)
              ? (fixedPoint.dy - currentPointerPos.dy).abs()
              : (currentPointerPos.dy - fixedPoint.dy).abs();
          scaleY = potentialHeight / currentBounds.height;
        }

        // Calculate scaled font size (clamped)
        newFontSize = (note.fontSize * scaleY).clamp(minFontSize, maxFontSize);

        // Calculate scaled width (clamped to min)
        calculatedWidth = (currentBounds.width * scaleY).clamp(minNoteWidth, double.infinity);

        // Calculate required height based on the *scaled* width and *scaled* font size
        Size contentFitSize = NoteElement.calculateSizeForContent(
          note.title,
          note.content,
          newFontSize, // Use the newly calculated font size
          targetWidth: calculatedWidth, // Use the scaled width
          minHeight: minNoteHeight
        );
        calculatedHeight = contentFitSize.height;
      }

      // 2. Finalize new size
      newSize = Size(calculatedWidth, calculatedHeight);

      // 3. Recalculate position based on fixed point and FINAL new size
      switch (handle) {
        case ResizeHandleType.topLeft: newPosition = fixedPoint - Offset(newSize.width, newSize.height); break;
        case ResizeHandleType.topRight: newPosition = Offset(fixedPoint.dx, fixedPoint.dy - newSize.height); break;
        case ResizeHandleType.bottomLeft: newPosition = Offset(fixedPoint.dx - newSize.width, fixedPoint.dy); break;
        case ResizeHandleType.bottomRight: newPosition = fixedPoint; break; // Top-left remains fixed
        case ResizeHandleType.topMiddle: newPosition = Offset(fixedPoint.dx - newSize.width / 2, fixedPoint.dy - newSize.height); break;
        case ResizeHandleType.bottomMiddle: newPosition = Offset(fixedPoint.dx - newSize.width / 2, fixedPoint.dy); break;
        case ResizeHandleType.middleLeft: newPosition = Offset(fixedPoint.dx - newSize.width, fixedPoint.dy - newSize.height / 2); break;
        case ResizeHandleType.middleRight: newPosition = Offset(fixedPoint.dx, fixedPoint.dy - newSize.height / 2); break;
        case ResizeHandleType.rotate:
          // Rotation is handled separately, this case should never be reached
          print("Rotation handle triggered in position calculation - ignoring.");
          return;
      }

      // 4. Create the updated element
      try {
        updatedElement = currentElement.copyWith(
            position: newPosition,
            size: newSize,
            fontSize: newFontSize, // Apply potentially scaled font size
            // No aspectRatioType needed here anymore for resizing
        );
      } catch (e, s) {
        print("Error resizing NoteElement: $e\n$s");
        return;
      }

    }
    // --- Default Resizing for other element types ---
    else {
      double left = currentBounds.left;
      double top = currentBounds.top;
      double right = currentBounds.right;
      double bottom = currentBounds.bottom;
      const double minOtherSizeDimension = 20.0; // Min size for non-notes

      // Adjust bounds based on the handle being dragged
      switch (handle) {
          case ResizeHandleType.bottomRight: right = currentPointerPos.dx; bottom = currentPointerPos.dy; break;
          case ResizeHandleType.bottomLeft: left = currentPointerPos.dx; bottom = currentPointerPos.dy; break;
          case ResizeHandleType.topRight: right = currentPointerPos.dx; top = currentPointerPos.dy; break;
          case ResizeHandleType.topLeft: left = currentPointerPos.dx; top = currentPointerPos.dy; break;
          case ResizeHandleType.bottomMiddle: bottom = currentPointerPos.dy; break;
          case ResizeHandleType.topMiddle: top = currentPointerPos.dy; break;
          case ResizeHandleType.middleRight: right = currentPointerPos.dx; break;
          case ResizeHandleType.middleLeft: left = currentPointerPos.dx; break;
          case ResizeHandleType.rotate:
            print("Rotation handle triggered in resizeSelected - ignoring.");
            return;
      }

      // Calculate new width and height, ensuring minimum size
      double newWidth = (right - left).clamp(minOtherSizeDimension, double.infinity);
      double newHeight = (bottom - top).clamp(minOtherSizeDimension, double.infinity);

      // Adjust position based on which handle was dragged to keep the opposite side fixed
      if (handle == ResizeHandleType.topLeft || handle == ResizeHandleType.topRight || handle == ResizeHandleType.topMiddle) {
          top = bottom - newHeight;
      }
      if (handle == ResizeHandleType.topLeft || handle == ResizeHandleType.bottomLeft || handle == ResizeHandleType.middleLeft) {
          left = right - newWidth;
      }

      newPosition = Offset(left, top);
      newSize = Size(newWidth, newHeight);

      // --- Apply the calculated changes for non-note elements ---
      try {
        // Use copyWith, passing size. Internal logic (like in PenElement) might handle scaling.
        updatedElement = currentElement.copyWith(position: newPosition, size: newSize);
      } catch (e, s) {
        print("Error resizing element ${currentElement.type}: $e\n$s");
        return;
      }
    }

    // --- Apply Update and Notify ---
      if (!_didResizeOccur) {
          // This is the first actual resize delta after PointerDown
          print("Resize started, saving pre-resize state to undo stack.");
          saveToUndoStack(); // Save the state *before* the first resize delta is applied
          _didResizeOccur = true; // Mark that resize is happening
      }
      List<DrawingElement> updatedElements = List.from(elements);
      updatedElements[index] = updatedElement;
      elements = updatedElements;
      notifyListeners(); // Update the UI
    }


  void endPotentialResize() {
    if (_didResizeOccur) {
      saveToUndoStack();
    }
  }


  // --- Rotation Logic ---
  void startPotentialRotation() {
    _didRotationOccur = false;
  }

  // This method is called during rotation interaction to provide immediate updates
  void rotateSelectedImmediate(String elementId, double newRotation) {
    final element = elements.firstWhereOrNull((e) => e.id == elementId);
    if (element == null) return;

    _didRotationOccur = true;
    final index = elements.indexOf(element);
    
    // Skip tiny rotation increments for performance (but don't accumulate errors)
    if ((element.rotation - newRotation).abs() < 0.0001) return;
    
    final updatedElement = element.copyWith(
      rotation: newRotation,
    );
    
    // Create a new list to trigger UI updates
    List<DrawingElement> updatedElements = List.from(elements);
    updatedElements[index] = updatedElement;
    elements = updatedElements;
    
    // CRITICAL: Must notify listeners immediately for visual synchronization
    notifyListeners();
  }

  // Main rotation method can simply delegate to the immediate version
  void rotateSelected(String elementId, double newRotation) {
    rotateSelectedImmediate(elementId, newRotation);
  }

  void endPotentialRotation() {
    if (_didRotationOccur) {
      saveToUndoStack();
    }
  }

  // --- Video Playback ---
  void toggleVideoPlayback(String elementId) {
    final element = elements.firstWhere((e) => e.id == elementId);
    if (element is VideoElement) {
      saveToUndoStack();
      element.togglePlayPause();
      notifyListeners();
    }
  }


  // --- Loading/Saving State ---
  void loadElements(List<DrawingElement> loadedElements) {
    elements = loadedElements;
    selectedElementIds.clear(); // Reset selection
    currentElement = null; // Reset any temporary element
    undoStack.clear(); // Clear history for the new state
    redoStack.clear();
    _showContextToolbar = false; // Ensure toolbar is hidden initially
    notifyListeners();
    print("Loaded ${elements.length} elements.");
  }

  // You would typically have a `saveElements` method here too,
  // which converts `elements` to a serializable format (e.g., List<Map<String, dynamic>>)
  // List<Map<String, dynamic>> saveElements() {
  //  return elements.map((e) => e.toMap()).toList();
  // }


  // --- Background Removal ---
  Future<void> removeImageBackground(String elementId) async {
    final element = elements.firstWhere((e) => e.id == elementId);
    if (element is ImageElement) {
      // Implementation depends on your background removal service
      // This is a placeholder for the actual implementation
      notifyListeners();
    }
  }

  // --- Image Enhancements ---
  Future<void> applyImageEnhancements(String elementId, double brightness, double contrast) async {
    final element = elements.firstWhere((e) => e.id == elementId);
    if (element is ImageElement) {
      // This is a placeholder for actual image enhancement implementation
      // In a real implementation, you would:
      // 1. Create a new ui.Image with the brightness/contrast applied
      // 2. Update the element with the new image
      print("Image enhancement not implemented yet: brightness=$brightness, contrast=$contrast");
      notifyListeners();
    }
  }


  // --- General Property Updates ---
  // Generic method to update properties based on a map
  void updateSelectedElementProperties(Map<String, dynamic> updates) {
    if (selectedElementIds.isEmpty || updates.isEmpty) return;

    saveToUndoStack();
    List<DrawingElement> updatedElements = List.from(elements);
    bool changed = false;

    for (int i = 0; i < updatedElements.length; i++) {
      if (selectedElementIds.contains(updatedElements[i].id)) {
        try {
          // Apply updates using copyWith dynamically
          // This requires careful type checking and casting
          var current = updatedElements[i];
          DrawingElement newElement = current; // Start with current

          // Example updates (add more as needed)
          if (current is PenElement) {
              newElement = current.copyWith(
                  color: updates['color'] as Color? ?? current.color,
                  strokeWidth: updates['strokeWidth'] as double? ?? current.strokeWidth,
              );
          } else if (current is TextElement) {
              newElement = current.copyWith(
                  text: updates['text'] as String? ?? current.text,
                  color: updates['color'] as Color? ?? current.color,
                  fontSize: updates['fontSize'] as double? ?? current.fontSize,
                  fontFamily: updates['fontFamily'] as String? ?? current.fontFamily,
                  fontWeight: updates['fontWeight'] as FontWeight? ?? current.fontWeight,
                  fontStyle: updates['fontStyle'] as FontStyle? ?? current.fontStyle,
                  textAlign: updates['textAlign'] as TextAlign? ?? current.textAlign,
              );
              // Recalculate size if text content changes might affect bounds
          } else if (current is NoteElement) {
              // Note: Size update based on text is handled by updateNoteContent
              // This generic method should primarily handle style/metadata changes
              newElement = current.copyWith(
                  // title: updates['title'] as String?, // Prefer updateNoteContent for title/content changes
                  // content: updates['content'] as String?,
                  backgroundColor: updates['backgroundColor'] as Color?,
                  isPinned: updates['isPinned'] as bool?,
                  fontSize: updates['fontSize'] as double?, // Allow font size update here
                  // Avoid updating size directly here, let resize or content update handle it
              );
              // If title/content changed, size needs recalculation - prefer updateNoteContent
              if(updates.containsKey('title') || updates.containsKey('content')) {
                 print("Warning: Updating Note title/content via generic method. Size might not auto-adjust. Use updateNoteContent for size calculation.");
              }
              // If font size changed here, we should recalculate height based on current width
              if (updates.containsKey('fontSize') && newElement is NoteElement) {
                  final updatedNote = newElement;
                  final Size contentSize = NoteElement.calculateSizeForContent(
                      updatedNote.title,
                      updatedNote.content,
                      updatedNote.fontSize,
                      targetWidth: updatedNote.size.width, // Use current width
                      minHeight: NoteElement.MIN_HEIGHT
                  );
                  newElement = updatedNote.copyWith(size: Size(updatedNote.size.width, contentSize.height));
              }

          }
          // Add other element types...

          if (newElement != current) { // Check if copyWith actually changed something
             updatedElements[i] = newElement;
             changed = true;
          }

        } catch (e, s) {
          print("Error updating element ${updatedElements[i].id} generically: $e\n$s");
        }
      }
    }

    if (changed) {
      elements = updatedElements;
      notifyListeners();
    }
  }


  // --- Cleanup ---
  @override
  void dispose() {
    print("Disposing DrawingProvider");
    for (final element in elements) {
      if (element is VideoElement) element.dispose();
      // Dispose other resources here
    }
    elements.clear();
    undoStack.clear();
    redoStack.clear();
    super.dispose();
  }

  // --- Element Order Manipulation ---
  // Bring selected elements one step forward in the Z-order
  void bringSelectedForward() {
    if (selectedElementIds.isEmpty) return;
    
    saveToUndoStack();
    final selectedElements = elements.where((e) => selectedElementIds.contains(e.id)).toList();
    elements.removeWhere((e) => selectedElementIds.contains(e.id));
    elements.addAll(selectedElements);
    notifyListeners();
  }

  // Send selected elements one step backward in the Z-order
  void sendSelectedBackward() {
    if (selectedElementIds.isEmpty) return;
    
    saveToUndoStack();
    final selectedElements = elements.where((e) => selectedElementIds.contains(e.id)).toList();
    elements.removeWhere((e) => selectedElementIds.contains(e.id));
    elements.insertAll(0, selectedElements);
    notifyListeners();
  }

  // --- Sticky Note Specific Methods ---

  void createStickyNote(Offset position) {
    saveToUndoStack();

    // Define a default size for the sticky note
    const Size defaultSize = Size(200.0, NoteElement.MIN_HEIGHT);
    
    // Ensure the note is created at the specified position
    // This position should typically be in canvas coordinates, not screen coordinates
    final newNote = NoteElement(
      id: _uuid.v4(),
      position: position,
      size: defaultSize,
      title: 'New Note',
      content: 'Click to edit',
      backgroundColor: const Color(0xFFFFFA99), // Default yellow
      fontSize: 16.0,
    );

    elements.add(newNote);
    clearSelection(notify: false); // Clear selection without notification
    selectElement(newNote); // Select the newly created note
    showContextToolbar = true; // Ensure toolbar is visible

    print("Created sticky note ${newNote.id} at $position");
  }

  void updateNoteContent(String elementId, String? title, String? content) {
    final index = elements.indexWhere((el) => el.id == elementId && el is NoteElement);
    if (index == -1) return;

    final currentNote = elements[index] as NoteElement;
    final newTitle = title?.trim();
    final newContent = content?.trim();

    // Only proceed if content actually changed
    if (currentNote.title == newTitle && currentNote.content == newContent) {
      print("Note content unchanged.");
      return;
    }

    saveToUndoStack();

    // Recalculate size based on new content and current font size/width
    final Size newSize = NoteElement.calculateSizeForContent(
      newTitle,
      newContent,
      currentNote.fontSize,
      targetWidth: currentNote.size.width, // Maintain current width when content changes
      minHeight: NoteElement.MIN_HEIGHT
    );

    final updatedNote = currentNote.copyWith(
      title: newTitle,
      content: newContent,
      size: newSize, // Update size based on content
    );

    List<DrawingElement> updatedElements = List.from(elements);
    updatedElements[index] = updatedNote;
    elements = updatedElements;
    notifyListeners();
    print("Updated note $elementId content and size.");
  }

  void setNoteColor(String elementId, Color color) {
    final index = elements.indexWhere((el) => el.id == elementId && el is NoteElement);
    if (index == -1) return;

    final currentNote = elements[index] as NoteElement;

    if (currentNote.backgroundColor == color) return; // No change

    saveToUndoStack();

    final updatedNote = currentNote.copyWith(backgroundColor: color);

    List<DrawingElement> updatedElements = List.from(elements);
    updatedElements[index] = updatedNote;
    elements = updatedElements;
    notifyListeners();
    print("Set note $elementId color.");
  }

  void toggleNotePin(String elementId) {
    final index = elements.indexWhere((el) => el.id == elementId && el is NoteElement);
    if (index == -1) return;

    final currentNote = elements[index] as NoteElement;

    saveToUndoStack();

    final updatedNote = currentNote.copyWith(isPinned: !currentNote.isPinned);

    List<DrawingElement> updatedElements = List.from(elements);
    updatedElements[index] = updatedNote;
    elements = updatedElements;
    notifyListeners();
    print("Toggled note $elementId pin status to ${updatedNote.isPinned}.");
  }

  Future<void> addVideoElement(String videoPath) async {
    saveToUndoStack();

    // Create a VideoPlayerController for the video
    final controller = VideoPlayerController.file(File(videoPath));
    await controller.initialize();

    final newVideo = VideoElement(
      id: _uuid.v4(),
      position: const Offset(100, 100), // Default position
      videoUrl: videoPath,
      controller: controller,
      size: const Size(320, 240), // Default size
    );

    elements.add(newVideo);
    clearSelection();
    selectElement(newVideo); // Select the newly added video

    print("Added video element ${newVideo.id} with path: $videoPath");
  }

  void addPenElement(Offset position) {
    saveToUndoStack();

    final newPen = PenElement(
      id: _uuid.v4(),
      position: position,
      points: [position], // Initialize with the first point
      color: currentColor,
      strokeWidth: currentStrokeWidth,
    );

    elements.add(newPen);
    clearSelection();
    selectElement(newPen); // Select the newly added pen stroke

    print("Added pen element ${newPen.id} at $position");
  }

  void updatePenElement(String elementId, Offset newPoint) {
    final elementIndex = elements.indexWhere((e) => e.id == elementId);
    if (elementIndex == -1) return;

    final element = elements[elementIndex];
    if (element is! PenElement) return;

    // Create a new list with all points plus the new one
    final updatedPoints = List<Offset>.from(element.points)..add(newPoint);

    // Create a new PenElement with the updated points
    final updatedPen = element.copyWith(points: updatedPoints);

    // Replace the old element with the updated one
    elements[elementIndex] = updatedPen;
    notifyListeners();
  }
}