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

  // Unique ID generator
  final _uuid = const Uuid();

  // --- Tool and Style Management ---
  void setTool(ElementType tool) {
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
// In lib/providers/drawing_provider.dart

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
      if (!(selectedElementIds.length == 1 && selectedElementIds.first == hitElement.id)) {
         clearSelection(notify: false);
         selectedElementIds.add(hitElement.id);
         selectionChanged = true;
         print("Selected element ${hitElement.id}");
      }
    } else {
      if (selectedElementIds.isNotEmpty) {
         clearSelection(notify: false);
         selectionChanged = true;
         print("Clearing selection");
      }
    }
    if (selectionChanged) {
       notifyListeners();
    }
  }

  void selectElement(DrawingElement element) {
      clearSelection(notify: false);
      selectedElementIds.add(element.id);
      notifyListeners();
  }

  void clearSelection({bool notify = true}) {
    if (selectedElementIds.isEmpty) return;
    selectedElementIds.clear();
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
}

// Helper Enum (Make sure this exists in your project, e.g., in models/element.dart)
// enum ElementType { select, pen, text, image, video, gif /*, other shapes */ }