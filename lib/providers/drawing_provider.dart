// lib/providers/drawing_provider.dart
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show listEquals; // <--- **** ADDED IMPORT for listEquals ****
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:vector_math/vector_math_64.dart' show Matrix4, MatrixUtils;
import 'package:collection/collection.dart';
import 'package:giphy_picker/giphy_picker.dart';
// import 'package:http/http.dart' as http; // Still not needed here
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:uuid/uuid.dart';

import '../models/element.dart';
import '../models/pen_element.dart';
import '../models/text_element.dart';
import '../models/image_element.dart';
import '../models/video_element.dart';
import '../models/gif_element.dart';
import '../models/handles.dart';
import '../services/background_removal_service.dart';

class DrawingProvider extends ChangeNotifier {
  // --- State Properties ---
  List<DrawingElement> elements = [];
  DrawingElement? currentElement;
  ElementType currentTool = ElementType.select;
  Color currentColor = Colors.black;
  double currentStrokeWidth = 2.0;
  List<String> selectedElementIds = [];

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
    if (_showContextToolbar && selectedElementIds.isEmpty) {
      print("WARNING: Context toolbar flag is true but no selected elements");
    }
    return isVisible;
  }
  
  set showContextToolbar(bool value) {
    if (_showContextToolbar != value) {
      _showContextToolbar = value;
      
      // Don't enable toolbar if no elements are selected
      if (value && selectedElementIds.isEmpty) {
        print("Warning: Attempting to show toolbar with no selected elements - ignoring");
        return; // Don't update state or notify listeners
      }
      
      print("Context toolbar visibility set to: $value (selected elements: ${selectedElementIds.length})");
      notifyListeners();
    }
  }

  // --- Tool and Style Management ---
  void setTool(ElementType tool) {
    // Hide toolbar when changing tools
    if (tool != currentTool) {
      _showContextToolbar = false;
    }
    
    currentTool = tool;
    clearSelection();
    notifyListeners();
  }

  void setColor(Color color) {
    currentColor = color;
    if (currentTool == ElementType.select && selectedElementIds.isNotEmpty) {
      saveToUndoStack();
      bool changed = false;
      List<DrawingElement> updatedElements = List.from(elements);
      for (int i = 0; i < updatedElements.length; i++) {
        if (selectedElementIds.contains(updatedElements[i].id)) {
          if (updatedElements[i] is PenElement) {
             updatedElements[i] = (updatedElements[i] as PenElement).copyWith(color: color);
             changed = true;
          } else if (updatedElements[i] is TextElement) {
             updatedElements[i] = (updatedElements[i] as TextElement).copyWith(color: color);
             changed = true;
          }
        }
      }
      if (changed) {
        elements = updatedElements;
        notifyListeners();
      }
    } else {
        notifyListeners();
    }
  }

  void setStrokeWidth(double width) {
    currentStrokeWidth = width;
    notifyListeners();
  }

  // --- Undo/Redo Core ---
  void saveToUndoStack() {
    try {
      final List<DrawingElement> clonedElements = elements.map((el) => el.clone()).toList();
      // Use listEquals here (needs foundation import)
      if (undoStack.isNotEmpty && listEquals(undoStack.last.map((e) => e.hashCode).toList(), clonedElements.map((e) => e.hashCode).toList())) {
         print("State unchanged, not saving duplicate to undo stack.");
         return;
      }
      undoStack.add(clonedElements);
      if (undoStack.length > maxUndoSteps) undoStack.removeAt(0);
      redoStack.clear();
      print("State saved (${undoStack.length} states)");
    } catch (e, s) {
      print("Error cloning for undo: $e\n$s");
    }
  }

  void undo() {
    if(undoStack.isEmpty) {
      print("Undo stack empty");
      return;
    }
    try {
      redoStack.add(elements.map((e) => e.clone()).toList());
      if(redoStack.length > maxUndoSteps) redoStack.removeAt(0);
    } catch(e, s) {
      print("Error cloning for redo state: $e\n$s");
    }
    elements = undoStack.removeLast();
    selectedElementIds.clear();
    notifyListeners();
    print("Undo performed (${undoStack.length} states remain)");
  }

  void redo() {
    if(redoStack.isEmpty) {
      print("Redo stack empty");
      return;
    }
    try {
      undoStack.add(elements.map((e) => e.clone()).toList());
      if(undoStack.length > maxUndoSteps) undoStack.removeAt(0);
    } catch(e, s) {
      print("Error saving current state before redo: $e\n$s");
    }
    elements = redoStack.removeLast();
    selectedElementIds.clear();
    notifyListeners();
    print("Redo performed (${redoStack.length} states remain)");
  }

  // --- Element Creation ---
  Offset _getCanvasCenter(TransformationController controller, BuildContext context) {
    final Size screenSize = MediaQuery.of(context).size;
    final Offset screenCenter = Offset(screenSize.width / 2, screenSize.height / 2);
    try {
      final Matrix4 inverseMatrix = Matrix4.inverted(controller.value);
      return MatrixUtils.transformPoint(inverseMatrix, screenCenter);
    } catch (e) {
      print("Error getting canvas center: $e. Using fallback.");
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
      final bytes = await File(pickedFile.path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      const double desiredWidth = 300;
      final double aspectRatio = image.height == 0 ? 1.0 : image.width / image.height;
      final size = Size(desiredWidth, aspectRatio == 0 ? desiredWidth : desiredWidth / aspectRatio);
      final position = _getCanvasCenter(controller, context) - Offset(size.width / 2, size.height / 2);
      saveToUndoStack();
      final newImageElement = ImageElement(
        id: _uuid.v4(),
        image: image,
        position: position,
        size: size,
      );
      elements.add(newImageElement);
      clearSelection();
      selectElement(newImageElement);
      notifyListeners();
    } catch (e) {
      print('Error adding image: $e');
      if(context.mounted){
         ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text('Error adding image: ${e.toString()}')),
         );
      }
    }
  }

  // --- Video Handling ---
  Future<void> addVideoFromGallery(BuildContext context, TransformationController controller) async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickVideo(source: ImageSource.gallery);
      if (pickedFile == null || !context.mounted) return;
      final videoController = VideoPlayerController.file(File(pickedFile.path));
      await videoController.initialize();
      const double desiredWidth = 320;
      final double aspectRatio = videoController.value.isInitialized && videoController.value.aspectRatio != 0
          ? videoController.value.aspectRatio
          : 16 / 9;
      final size = Size(desiredWidth, desiredWidth / aspectRatio);
      final position = _getCanvasCenter(controller, context) - Offset(size.width / 2, size.height / 2);
      saveToUndoStack();
      final newVideoElement = VideoElement(
        id: _uuid.v4(),
        videoUrl: pickedFile.path,
        controller: videoController,
        position: position,
        size: size,
      );
      elements.add(newVideoElement);
      clearSelection();
      selectElement(newVideoElement);
      notifyListeners();
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
  void addTextElement(String text, Offset position) {
    if (text.trim().isEmpty) return;
    saveToUndoStack();
    final newTextElement = TextElement(
      id: _uuid.v4(),
      position: position,
      text: text.trim(),
      color: currentColor,
      fontSize: 24.0,
    );
    elements.add(newTextElement);
    clearSelection();
    selectElement(newTextElement);
    notifyListeners();
  }

  // --- Drawing Lifecycle (Pen Tool) ---
  void startDrawing(Offset position) {
    if (currentTool != ElementType.pen) return;
    currentElement = PenElement(
      id: _uuid.v4(),
      position: position,
      points: [position],
      color: currentColor,
      strokeWidth: currentStrokeWidth,
    );
    notifyListeners();
  }

  void updateDrawing(Offset position) {
    if (currentElement is! PenElement) return;
    if ((currentElement as PenElement).points.isNotEmpty && (currentElement as PenElement).points.last == position) return;
    final pen = currentElement as PenElement;
    currentElement = pen.copyWith(
      points: List.from(pen.points)..add(position)
    );
    notifyListeners();
  }

  void endDrawing() {
    if (currentElement is! PenElement) {
        currentElement = null;
        return;
    }
    final pen = currentElement as PenElement;
    bool isValid = pen.points.length >= 2;
    if (isValid) {
      saveToUndoStack();
      elements.add(pen);
    } else {
        print("Drawing discarded (too short)");
    }
    currentElement = null;
    notifyListeners();
  }

  void discardDrawing() {
    if (currentElement == null) return;
    print("Drawing discarded");
    currentElement = null;
    notifyListeners();
  }

  // --- Selection and Interaction ---
  void selectElementAt(Offset position) {
    final DrawingElement? hitElement = elements.lastWhereOrNull((e) => e.containsPoint(position));
    bool selectionChanged = false;
    
    if (hitElement != null) {
      // Always show toolbar when selecting an element
      _showContextToolbar = true; 
      
      // Update selection if needed
      if (!(selectedElementIds.length == 1 && selectedElementIds.first == hitElement.id)) {
        clearSelection(notify: false);
        selectedElementIds.add(hitElement.id);
        selectionChanged = true;
        print("Selected element ${hitElement.id} - showing toolbar");
      } else {
        // Force notify even if selection didn't change
        selectionChanged = true;
      }
      
      // Log the z-index of the selected element
      final zIndex = elements.indexOf(hitElement);
      print("Element ${hitElement.id} selected at z-index: $zIndex");
      
    } else {
      if (selectedElementIds.isNotEmpty) {
        clearSelection(notify: false);
        _showContextToolbar = false;
        selectionChanged = true;
        print("Clearing selection - hiding toolbar");
      }
    }
    
    if (selectionChanged) {
      notifyListeners();
    }
  }

  void selectElement(DrawingElement element) {
      clearSelection(notify: false);
      selectedElementIds.add(element.id);
      _showContextToolbar = true;
      notifyListeners();
  }

  // Make the showContextToolbarForElement method more robust
  void showContextToolbarForElement(String elementId) {
    // Check if element exists
    final element = elements.firstWhereOrNull((e) => e.id == elementId);
    if (element != null) {
      // Make sure we set the flag and notify listeners
      if (!_showContextToolbar) {
        _showContextToolbar = true;
        notifyListeners();
        print("Showing context toolbar for element $elementId");
      }
    }
  }

  void clearSelection({bool notify = true}) {
    if (selectedElementIds.isEmpty) return;
    selectedElementIds.clear();
    _showContextToolbar = false;
    if (notify) {
      notifyListeners();
    }
  }

  void deleteSelected() {
    if (selectedElementIds.isEmpty) return;
    saveToUndoStack();
    int count = selectedElementIds.length;
    List<String> idsToDelete = List.from(selectedElementIds);
    selectedElementIds.clear();
    for (String id in idsToDelete) {
      final element = elements.firstWhereOrNull((e) => e.id == id);
      if (element is VideoElement) {
        element.dispose();
        print("Disposed VideoController for element $id");
      }
    }
    elements.removeWhere((e) => idsToDelete.contains(e.id));
    print("Deleted $count elements");
    notifyListeners();
  }

  // --- Move Logic ---
  void startPotentialMove() {
    _didMoveOccur = false;
  }

  void moveSelected(Offset delta) {
    if (selectedElementIds.isEmpty || delta.distanceSquared == 0) return;
    _didMoveOccur = true;
    List<DrawingElement> updatedElements = List.from(elements);
    bool changed = false;
    for (int i = 0; i < updatedElements.length; i++) {
      if (selectedElementIds.contains(updatedElements[i].id)) {
        updatedElements[i] = updatedElements[i].copyWith(
          position: updatedElements[i].position + delta
        );
        changed = true;
      }
    }
    if (changed) {
      elements = updatedElements;
      notifyListeners();
    }
  }

  void endPotentialMove() {
    if (_didMoveOccur) {
      print("Saving move to undo stack");
      saveToUndoStack();
    }
    _didMoveOccur = false;
  }

  // --- Resize Logic ---
  void startPotentialResize() {
    _didResizeOccur = false;
  }

  void resizeSelected(
      String elementId,
      ResizeHandleType handle,
      Offset delta,
      Offset currentPointerPos,
      Offset startPointerPos)
  {
    int index = elements.indexWhere((el) => el.id == elementId);
    if (index == -1) return;
    final currentElement = elements[index];
    Rect currentBounds = currentElement.bounds;
    if (currentBounds.isEmpty) return;

    double left = currentBounds.left;
    double top = currentBounds.top;
    double right = currentBounds.right;
    double bottom = currentBounds.bottom;
    const double minSize = 20.0;

    switch (handle) {
      case ResizeHandleType.bottomRight: right = currentPointerPos.dx; bottom = currentPointerPos.dy; break;
      case ResizeHandleType.bottomLeft: left = currentPointerPos.dx; bottom = currentPointerPos.dy; break;
      case ResizeHandleType.topRight: right = currentPointerPos.dx; top = currentPointerPos.dy; break;
      case ResizeHandleType.topLeft: left = currentPointerPos.dx; top = currentPointerPos.dy; break;
      case ResizeHandleType.bottomMiddle: bottom = currentPointerPos.dy; break;
      case ResizeHandleType.topMiddle: top = currentPointerPos.dy; break;
      case ResizeHandleType.middleRight: right = currentPointerPos.dx; break;
      case ResizeHandleType.middleLeft: left = currentPointerPos.dx; break;
      default: print("Resize handle type $handle not implemented"); return;
    }

    double newWidth = (right - left).clamp(minSize, double.infinity);
    double newHeight = (bottom - top).clamp(minSize, double.infinity);

    if (handle == ResizeHandleType.topLeft || handle == ResizeHandleType.topRight || handle == ResizeHandleType.topMiddle) {
       top = bottom - newHeight;
    }
    if (handle == ResizeHandleType.topLeft || handle == ResizeHandleType.bottomLeft || handle == ResizeHandleType.middleLeft) {
       left = right - newWidth;
    }

    Offset newPosition = Offset(left, top);
    Size newSize = Size(newWidth, newHeight);

    DrawingElement? updatedElement;
    try {
      updatedElement = currentElement.copyWith(position: newPosition, size: newSize);
    } catch (e, s) {
      print("Error resizing element ${currentElement.type}: $e\n$s"); return;
    }

    if (updatedElement != null) {
      _didResizeOccur = true;
      List<DrawingElement> updatedElements = List.from(elements);
      updatedElements[index] = updatedElement;
      elements = updatedElements;
      notifyListeners();
    } else {
      print("Failed to resize element $elementId");
    }
  }

  void endPotentialResize() {
    if (_didResizeOccur) {
      print("Saving resize to undo stack");
      saveToUndoStack();
    }
    _didResizeOccur = false;
  }

  // --- Rotation Logic ---
  void startPotentialRotation() {
    _didRotationOccur = false;
  }

  void rotateSelected(String elementId, double newRotation) {
    int index = elements.indexWhere((el) => el.id == elementId);
    if (index == -1) return;
    
    final currentElement = elements[index];
    
    DrawingElement? updatedElement;
    try {
      updatedElement = currentElement.copyWith(rotation: newRotation);
    } catch (e, s) {
      print("Error rotating element ${currentElement.type}: $e\n$s");
      return;
    }

    if (updatedElement != null) {
      _didRotationOccur = true;
      List<DrawingElement> updatedElements = List.from(elements);
      updatedElements[index] = updatedElement;
      elements = updatedElements;
      notifyListeners();
    } else {
      print("Failed to rotate element $elementId");
    }
  }

  void endPotentialRotation() {
    if (_didRotationOccur) {
      print("Saving rotation to undo stack");
      saveToUndoStack();
    }
    _didRotationOccur = false;
  }

  // --- Video Playback ---
  void toggleVideoPlayback(String id) {
    final element = elements.firstWhereOrNull((e) => e.id == id);
    if (element is VideoElement) {
      element.togglePlayPause();
    }
  }

  // --- Calendar Integration (Example) ---
  void loadElements(List<DrawingElement> loadedElements) {
    for (final element in elements) {
      if (element is VideoElement) element.dispose();
    }
    elements = loadedElements;
    selectedElementIds.clear();
    currentElement = null;
    undoStack.clear();
    redoStack.clear();
    notifyListeners();
    print("Loaded ${elements.length} elements.");
  }

  // --- Background Removal ---
  Future<void> removeImageBackground(String elementId) async {
    // Find the image element by ID
    final index = elements.indexWhere((el) => el.id == elementId);
    if (index == -1) {
      throw Exception('Element not found');
    }
    
    final element = elements[index];
    if (element is! ImageElement) {
      throw Exception('Selected element is not an image');
    }
    
    // Save current state to undo stack
    saveToUndoStack();
    
    try {
      // Use the service to remove background
      final processedImage = await BackgroundRemovalService.removeBackground(element.image);
      
      // Create a new image element with the processed image
      final newElement = ImageElement(
        id: element.id,  // Keep the same ID
        position: element.position,
        isSelected: element.isSelected,
        image: processedImage,
        size: element.size,
        imagePath: element.imagePath,  // Keep the same path reference
      );
      
      // Replace the old element with the new one
      List<DrawingElement> updatedElements = List.from(elements);
      updatedElements[index] = newElement;
      elements = updatedElements;
      
      notifyListeners();
      
    } catch (e) {
      print('Error removing background: $e');
      rethrow;  // Re-throw the error to be handled by the UI
    }
  }

  // Apply brightness and contrast adjustments to an image
  Future<void> applyImageEnhancements(String elementId, double brightness, double contrast) async {
    // Find the image element by ID
    final index = elements.indexWhere((el) => el.id == elementId);
    if (index == -1 || elements[index] is! ImageElement) {
      print("Element not found or not an image");
      return;
    }
    
    final element = elements[index] as ImageElement;
    
    // Save current state to undo stack
    saveToUndoStack();
    
    try {
      // Get the image data
      final image = element.image;
      
      // Apply brightness and contrast adjustments
      // This would typically be done using a ColorFilter or custom shader
      // For this example, we'll just record that the adjustments were requested
      print("Applying brightness: $brightness, contrast: $contrast to image ${element.id}");
      
      // In a real implementation, you would create a modified image here
      // For now, we'll just notify listeners that something changed
      notifyListeners();
      
      // For a complete implementation, you would:
      // 1. Create a new ui.Image with filters applied
      // 2. Create a new ImageElement with the modified image
      // 3. Replace the element in the elements list
      
    } catch (e) {
      print('Error applying image enhancements: $e');
    }
  }

  // --- Element Modification Methods ---

  void updateSelectedElementProperties(Map<String, dynamic> updates) {
    if (selectedElementIds.isEmpty) return;
    saveToUndoStack();
    List<DrawingElement> updatedElements = List.from(elements);
    bool changed = false;

    for (int i = 0; i < updatedElements.length; i++) {
      if (selectedElementIds.contains(updatedElements[i].id)) {
        try {
          // Apply updates using copyWith dynamically
          // This is a simplified example; real implementation might need
          // specific checks per element type or a more robust reflection mechanism.
          var current = updatedElements[i];
          if (current is PenElement && updates.containsKey('color')) {
             updatedElements[i] = current.copyWith(color: updates['color'] as Color);
             changed = true;
          }
          if (current is PenElement && updates.containsKey('strokeWidth')) {
             updatedElements[i] = current.copyWith(strokeWidth: updates['strokeWidth'] as double);
             changed = true;
          }
          if (current is TextElement) {
            updatedElements[i] = current.copyWith(
                text: updates['text'] as String?,
                color: updates['color'] as Color?,
                fontSize: updates['fontSize'] as double?,
                fontFamily: updates['fontFamily'] as String?,
                fontWeight: updates['fontWeight'] as FontWeight?,
                fontStyle: updates['fontStyle'] as FontStyle?,
                textAlign: updates['textAlign'] as TextAlign?,
            );
             changed = true;
          }
          // Add similar blocks for other element types and properties

        } catch (e, s) {
          print("Error updating element ${updatedElements[i].id}: $e\n$s");
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
    }
    elements.clear();
    undoStack.clear();
    redoStack.clear();
    super.dispose();
  }

  // --- Element Order Manipulation ---

  void bringSelectedForward() {
    if (selectedElementIds.isEmpty) return;

    // Create a list of (originalIndex, element) pairs for selected items
    List<MapEntry<int, DrawingElement>> selectedIndexed = [];
    for (int i = 0; i < elements.length; i++) {
      if (selectedElementIds.contains(elements[i].id)) {
        selectedIndexed.add(MapEntry(i, elements[i]));
      }
    }

    if (selectedIndexed.isEmpty) return;

    // Sort by original index to easily find min/max and preserve relative order
    selectedIndexed.sort((a, b) => a.key.compareTo(b.key));

    int maxOriginalIndex = selectedIndexed.last.key;

    // Check if already at the top
    if (maxOriginalIndex == elements.length - 1) {
      print("Selected elements already at the top.");
      return;
    }

    saveToUndoStack(); // Save state *only* if a change is possible

    List<DrawingElement> currentElements = List.from(elements);
    List<DrawingElement> selectedItems = selectedIndexed.map((e) => e.value).toList();

    // Remove selected items from the list (using original indices, descending)
    for (int i = selectedIndexed.length - 1; i >= 0; i--) {
      currentElements.removeAt(selectedIndexed[i].key);
    }

    // Determine the insertion index in the modified list.
    // It should be inserted just *after* the element that was originally at maxOriginalIndex + 1.
    DrawingElement elementOriginallyAbove = elements[maxOriginalIndex + 1];
    int indexOfElementAbove = currentElements.indexOf(elementOriginallyAbove);

    int insertionPoint;
    if (indexOfElementAbove != -1) {
      // Insert *after* the element that was originally above
      insertionPoint = indexOfElementAbove + 1;
    } else {
      // Fallback: calculate based on original index and number removed before it.
      int removedCountBeforeTarget = selectedIndexed.where((e) => e.key < maxOriginalIndex + 1).length;
      insertionPoint = (maxOriginalIndex + 1) - removedCountBeforeTarget;
      print("Warning/Fallback: Using calculated insertion point for bringForward: $insertionPoint");
    }

     // Clamp insertion point to valid range
    insertionPoint = insertionPoint.clamp(0, currentElements.length);

    // Insert the block
    currentElements.insertAll(insertionPoint, selectedItems);

    elements = currentElements;

    // --- Add Logging Here ---
    print("Brought selected elements forward. New order:");
    for(int i = 0; i < elements.length; i++) {
      print("  Index $i: ${elements[i].id} (${elements[i].type})");
    }
    // --- End Logging ---

    notifyListeners();
    print("Brought selected elements forward.");

  }

  void sendSelectedBackward() {
    if (selectedElementIds.isEmpty) return;

     // Create a list of (originalIndex, element) pairs for selected items
    List<MapEntry<int, DrawingElement>> selectedIndexed = [];
    for (int i = 0; i < elements.length; i++) {
      if (selectedElementIds.contains(elements[i].id)) {
        selectedIndexed.add(MapEntry(i, elements[i]));
      }
    }

    if (selectedIndexed.isEmpty) return;

    // Sort by original index
    selectedIndexed.sort((a, b) => a.key.compareTo(b.key));

    int minOriginalIndex = selectedIndexed.first.key;

    // Check if already at the bottom
    if (minOriginalIndex == 0) {
      print("Selected elements already at the bottom.");
      return;
    }

    saveToUndoStack(); // Save state only if change is possible

    List<DrawingElement> currentElements = List.from(elements);
    List<DrawingElement> selectedItems = selectedIndexed.map((e) => e.value).toList();

    // Remove selected items (using original indices, descending)
    for (int i = selectedIndexed.length - 1; i >= 0; i--) {
      currentElements.removeAt(selectedIndexed[i].key);
    }

    // Determine the insertion index in the modified list.
    // It should be inserted *at the position* where the element that was originally at minOriginalIndex - 1 now resides.
    DrawingElement elementOriginallyBelow = elements[minOriginalIndex - 1];
    int indexOfElementBelow = currentElements.indexOf(elementOriginallyBelow);

    int insertionPoint;
    if (indexOfElementBelow != -1) {
      // Insert *at the current index* of the element that was originally below
      insertionPoint = indexOfElementBelow;
    } else {
      // Fallback: calculate based on original index and number removed before it.
       int removedCountBeforeTarget = selectedIndexed.where((e) => e.key < minOriginalIndex).length;
       insertionPoint = minOriginalIndex - removedCountBeforeTarget;
       print("Warning/Fallback: Using calculated insertion point for sendBackward: $insertionPoint");
    }

    // Clamp insertion point to valid range
    insertionPoint = insertionPoint.clamp(0, currentElements.length);

    // Insert the block
    currentElements.insertAll(insertionPoint, selectedItems);

    elements = currentElements;

    // --- Add Logging Here ---
    print("Sent selected elements backward. New order:");
    for(int i = 0; i < elements.length; i++) {
      print("  Index $i: ${elements[i].id} (${elements[i].type})");
    }
    // --- End Logging ---

    notifyListeners();
    print("Sent selected elements backward.");
  }

  void moveElementBackward(String elementId) {
    print("Attempting to move element $elementId backward."); // Debugging output
    saveToUndoStack(); // Save state before changing order
    final index = elements.indexWhere((el) => el.id == elementId);
    if (index > 0) { // Can only move back if not already at the bottom
      final element = elements.removeAt(index);
      elements.insert(index - 1, element);
      notifyListeners();
      print("Moved element $elementId backward to index ${index - 1}");
      // Log the new z-index
      print("Element $elementId new z-index: ${index - 1}");
    } else {
      print("Element $elementId is already at the bottom or not found.");
    }
  }

  void deleteSelectedElements() {
    if (selectedElementIds.isEmpty) return;
    saveToUndoStack(); // Save state before deleting
    elements.removeWhere((el) => selectedElementIds.contains(el.id));
    final deletedIds = List.from(selectedElementIds); // Copy before clearing
    selectedElementIds.clear();
    showContextToolbar = false; // Hide toolbar after deletion
    notifyListeners();
    print("Deleted elements: $deletedIds");
  }
}

// Helper Enum (Make sure this exists in your project, e.g., in models/element.dart)
// enum ElementType { select, pen, text, image, video, gif /*, other shapes */ }