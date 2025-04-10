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
import '../models/note_element.dart';

class DrawingProvider extends ChangeNotifier {
  // --- State Properties ---
  List<DrawingElement> elements = [];
  DrawingElement? currentElement;
  ElementType currentTool = ElementType.none; // Default to none instead of select
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
    // Never show the context toolbar - removed from the UI
    return false;
  }

  set showContextToolbar(bool value) {
    // No-op - context toolbar has been removed
  }

  // --- Tool and Style Management ---
  void setTool(ElementType tool) {
    // Hide toolbar when changing tools
    if (tool != ElementType.none && currentTool == ElementType.none) {
        _showContextToolbar = false;
    }

    currentTool = tool;
    
    // Clear selection when switching tools, unless we're staying in none mode
    if (tool != ElementType.none) {
        clearSelection();
    } else {
        notifyListeners();
    }
  }

  // Add method to reset the current tool
  void resetTool() {
    setTool(ElementType.none);
  }

  void setColor(Color color) {
    currentColor = color;
    if (currentTool == ElementType.none && selectedElementIds.isNotEmpty) {
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
          } else if (updatedElements[i] is NoteElement) {
              updatedElements[i] = (updatedElements[i] as NoteElement).copyWith(backgroundColor: color);
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
    if (currentTool == ElementType.none && selectedElementIds.isNotEmpty) {
      saveToUndoStack();
      bool changed = false;
      List<DrawingElement> updatedElements = List.from(elements);
      for (int i = 0; i < updatedElements.length; i++) {
        if (selectedElementIds.contains(updatedElements[i].id)) {
          if (updatedElements[i] is PenElement) {
              updatedElements[i] = (updatedElements[i] as PenElement).copyWith(strokeWidth: width);
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

  // --- Undo/Redo Core ---
  void saveToUndoStack() {
    try {
      final List<DrawingElement> clonedElements = elements.map((el) => el.clone()).toList();
      
      if (undoStack.isNotEmpty && 
          listEquals(undoStack.last.map((e) => e.hashCode).toList(), 
                    clonedElements.map((e) => e.hashCode).toList())) {
        return;
      }
      
      undoStack.add(clonedElements);
      
      if (undoStack.length > maxUndoSteps) {
        undoStack.removeAt(0);
      }
      
      redoStack.clear();
    } catch (e, s) {
      print("Error saving to undo stack: $e\n$s");
    }
  }

  void undo() {
    if (undoStack.isEmpty) return;
    
    try {
      final List<DrawingElement> currentState = elements.map((e) => e.clone()).toList();
      redoStack.add(currentState);
      
      if (redoStack.length > maxUndoSteps) {
        redoStack.removeAt(0);
      }
      
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
      undoStack.add(elements.map((e) => e.clone()).toList());
      if(undoStack.length > maxUndoSteps) undoStack.removeAt(0);
    } catch(e, s) {
      print("Error saving current state before redo: $e\n$s");
    }
    elements = redoStack.removeLast();
    selectedElementIds.clear();
    _showContextToolbar = false;
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
        showPreviewPage: false,
        lang: GiphyLanguage.english,
        fullScreenDialog: true,
        searchHintText: 'Search for GIFs...',
      );

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

      if (!context.mounted) {
          print("Context became invalid after picking GIF.");
          return;
      }

      print("Calling _addGifToCanvas...");
      _addGifToCanvas(gif, controller, context);
      
      // Reset to interaction mode after adding GIF
      setTool(ElementType.none);

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
    print("--- Starting _addGifToCanvas ---");
    try {
      final gifUrl = gif.images.original?.url;
      final previewUrl = gif.images.previewGif?.url ?? gif.images.fixedWidth?.url;
      print("    GIF URL: $gifUrl");
      print("    Preview URL: $previewUrl");

      if (gifUrl == null) {
        throw Exception('Could not retrieve a valid GIF URL');
      }

      const double desiredWidth = 250.0;
      final double? imgWidth = double.tryParse(gif.images.original?.width ?? '0');
      final double? imgHeight = double.tryParse(gif.images.original?.height ?? '0');
      double aspectRatio = 1.0;
      if (imgWidth != null && imgHeight != null && imgWidth > 0 && imgHeight > 0) {
          aspectRatio = imgWidth / imgHeight;
      }
      final size = Size(desiredWidth, desiredWidth / aspectRatio);
      print("    Calculated Size: $size (Aspect Ratio: $aspectRatio)");

      final Offset canvasCenter = _getCanvasCenter(controller, context);
      final position = canvasCenter - Offset(size.width / 2, size.height / 2);
      print("    Calculated Position: $position (Canvas Center: $canvasCenter)");

      print("    Saving state to undo stack...");
      saveToUndoStack();

      final newGifElement = GifElement(
        id: _uuid.v4(),
        position: position,
        size: size,
        gifUrl: gifUrl,
        previewUrl: previewUrl,
      );
      print("    Created GifElement with ID: ${newGifElement.id}");

      elements.add(newGifElement);
      print("    Added GifElement to list. Total elements now: ${elements.length}");

      clearSelection(); // Don't select the newly added GIF
      print("    Calling notifyListeners()...");
      notifyListeners();

      print("    Showing SnackBar confirmation...");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('GIF added to canvas')),
      );

    } catch (e, s) {
      print('!!! Error adding GIF to canvas: $e');
      print('!!! Stack trace: $s');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error adding GIF: ${e.toString()}')),
      );
    }
    print("--- Finished _addGifToCanvas ---");
  }

  // --- Image Handling ---
  Future<void> addImageFromGallery(BuildContext context, TransformationController controller) async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);
      if (pickedFile == null || !context.mounted) return;

      saveToUndoStack();

      final File imageFile = File(pickedFile.path);
      final Uint8List imageBytes = await imageFile.readAsBytes();
      final ui.Image image = await decodeImageFromList(imageBytes);

      final aspectRatio = image.width / image.height;
      const width = 300.0;
      final height = width / aspectRatio;

      final position = _getCanvasCenter(controller, context) - Offset(width / 2, height / 2);

      final newImage = ImageElement(
        id: _uuid.v4(),
        position: position,
        image: image,
        size: Size(width, height),
        imagePath: pickedFile.path,
      );

      elements.add(newImage);
      clearSelection(); // Don't select the newly added image
      
      // Reset to interaction mode after adding image
      setTool(ElementType.none);

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
      clearSelection(); // Don't select the newly added video
      
      // Reset to interaction mode after adding video
      setTool(ElementType.none);

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
    saveToUndoStack();

    final tempText = TextElement(
      position: position,
      text: text,
      color: currentColor,
      fontSize: 24.0,
    );

    final textSize = tempText.bounds.size;
    final centeredPosition = position - Offset(textSize.width / 2, textSize.height / 2);

    final newText = TextElement(
      id: _uuid.v4(),
      position: centeredPosition,
      text: text,
      color: currentColor,
      fontSize: 24.0,
    );

    // Add with a small delay to ensure UI is ready
    Future.microtask(() {
      elements.add(newText);
      clearSelection(); // Remove selection of the new element
      
      // Reset to interaction mode after adding text
      setTool(ElementType.none);
      
      notifyListeners();
      print("Added text element ${newText.id} at $centeredPosition");
    });
  }

  // --- Drawing Lifecycle (Pen Tool) ---
  void startDrawing(Offset position) {
    if (currentTool != ElementType.pen) return;
    
    // Clear any previous drawing to avoid conflicts
    if (currentElement != null) {
      currentElement = null;
    }
    
    saveToUndoStack();
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
      elements.add(pen);
      currentElement = null; // Clear the current element
      
      // Reset to interaction mode after drawing
      setTool(ElementType.none);
      clearSelection(); // Ensure nothing is selected after drawing
      
      print("Drawing completed and added to elements");
    } else {
        if (undoStack.isNotEmpty) {
          undoStack.removeLast();
          print("Drawing discarded (too short), reverted undo state.");
        } else {
          print("Drawing discarded (too short), undo stack was empty.");
        }
        currentElement = null; // Make sure to clear the element even if invalid
    }
    
    notifyListeners();
  }

  void discardDrawing() {
    if (currentElement == null) return;
    
    if (currentElement is PenElement) {
        if (undoStack.isNotEmpty) {
          undoStack.removeLast();
          print("Drawing discarded, reverted undo state.");
        } else {
          print("Drawing discarded, undo stack was empty.");
        }
    }
    
    print("Drawing discarded");
    currentElement = null;
    
    // Always reset to selection mode when discarding
    setTool(ElementType.none);
    notifyListeners();
  }

  // --- Selection and Interaction ---
  void selectElementAt(Offset position) {
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

  // Direct delete method that doesn't require selection
  void deleteElement(String elementId) {
    print("Attempting to delete element with ID: $elementId");
    
    // Save current state to undo stack
    saveToUndoStack();
    
    // Find and remove the element directly
    final int index = elements.indexWhere((element) => element.id == elementId);
    if (index >= 0) {
      // Get the element information before deleting
      final element = elements[index];
      print("Found element to delete: ${element.type} at index $index");
      
      // Check if it's a video or other element that needs disposal
      if (element is VideoElement) {
        element.dispose();
      }
      
      // Remove the element
      elements.removeAt(index);
      
      // Also clear from selection if it's selected
      if (selectedElementIds.contains(elementId)) {
        selectedElementIds.remove(elementId);
      }
      
      // Notify listeners about the change
      notifyListeners();
      print("Element $elementId deleted successfully");
    } else {
      print("ERROR: Could not find element $elementId to delete");
    }
  }

  // --- Move Logic ---
  void startPotentialMove() {
    _didMoveOccur = false;
  }

  void moveSelected(Offset delta) {
    if (selectedElementIds.isEmpty || (delta.dx == 0 && delta.dy == 0)) return;
    
    _didMoveOccur = true;
    final List<DrawingElement> updatedElements = List.from(elements);
    
    for (int i = 0; i < updatedElements.length; i++) {
      if (selectedElementIds.contains(updatedElements[i].id)) {
        updatedElements[i] = updatedElements[i].copyWith(
          position: updatedElements[i].position + delta,
        );
      }
    }
    
    elements = updatedElements;
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

    if (currentElement is NoteElement) {
      final note = currentElement;
      double newFontSize = note.fontSize;

      const double minNoteWidth = NoteElement.MIN_WIDTH;
      const double minNoteHeight = NoteElement.MIN_HEIGHT;
      const double minFontSize = 8.0;
      const double maxFontSize = 100.0;

      Offset fixedPoint = Offset.zero;
      bool isHorizontalHandle = (handle == ResizeHandleType.middleLeft || handle == ResizeHandleType.middleRight);

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

      if (isHorizontalHandle) {
        newFontSize = note.fontSize;

        if (handle == ResizeHandleType.middleLeft) {
          calculatedWidth = fixedPoint.dx - currentPointerPos.dx;
        } else {
          calculatedWidth = currentPointerPos.dx - fixedPoint.dx;
        }
        calculatedWidth = calculatedWidth.clamp(minNoteWidth, double.infinity);

        Size contentFitSize = NoteElement.calculateSizeForContent(
          note.title,
          note.content,
          newFontSize,
          targetWidth: calculatedWidth,
          minHeight: minNoteHeight
        );
        calculatedHeight = contentFitSize.height;

      } else {
        double scaleY = 1.0;
        if (currentBounds.height > 1e-6) {
          double potentialHeight = (handle == ResizeHandleType.topMiddle || handle == ResizeHandleType.topLeft || handle == ResizeHandleType.topRight)
              ? (fixedPoint.dy - currentPointerPos.dy).abs()
              : (currentPointerPos.dy - fixedPoint.dy).abs();
          scaleY = potentialHeight / currentBounds.height;
        }

        newFontSize = (note.fontSize * scaleY).clamp(minFontSize, maxFontSize);

        calculatedWidth = (currentBounds.width * scaleY).clamp(minNoteWidth, double.infinity);

        Size contentFitSize = NoteElement.calculateSizeForContent(
          note.title,
          note.content,
          newFontSize,
          targetWidth: calculatedWidth,
          minHeight: minNoteHeight
        );
        calculatedHeight = contentFitSize.height;
      }

      newSize = Size(calculatedWidth, calculatedHeight);

      switch (handle) {
        case ResizeHandleType.topLeft: newPosition = fixedPoint - Offset(newSize.width, newSize.height); break;
        case ResizeHandleType.topRight: newPosition = Offset(fixedPoint.dx, fixedPoint.dy - newSize.height); break;
        case ResizeHandleType.bottomLeft: newPosition = Offset(fixedPoint.dx - newSize.width, fixedPoint.dy); break;
        case ResizeHandleType.bottomRight: newPosition = fixedPoint; break;
        case ResizeHandleType.topMiddle: newPosition = Offset(fixedPoint.dx - newSize.width / 2, fixedPoint.dy - newSize.height); break;
        case ResizeHandleType.bottomMiddle: newPosition = Offset(fixedPoint.dx - newSize.width / 2, fixedPoint.dy); break;
        case ResizeHandleType.middleLeft: newPosition = Offset(fixedPoint.dx - newSize.width, fixedPoint.dy - newSize.height / 2); break;
        case ResizeHandleType.middleRight: newPosition = Offset(fixedPoint.dx, fixedPoint.dy - newSize.height / 2); break;
        case ResizeHandleType.rotate:
          print("Rotation handle triggered in position calculation - ignoring.");
          return;
      }

      try {
        updatedElement = currentElement.copyWith(
            position: newPosition,
            size: newSize,
            fontSize: newFontSize,
        );
      } catch (e, s) {
        print("Error resizing NoteElement: $e\n$s");
        return;
      }

    } else {
      double left = currentBounds.left;
      double top = currentBounds.top;
      double right = currentBounds.right;
      double bottom = currentBounds.bottom;
      const double minOtherSizeDimension = 20.0;

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

      double newWidth = (right - left).clamp(minOtherSizeDimension, double.infinity);
      double newHeight = (bottom - top).clamp(minOtherSizeDimension, double.infinity);

      if (handle == ResizeHandleType.topLeft || handle == ResizeHandleType.topRight || handle == ResizeHandleType.topMiddle) {
          top = bottom - newHeight;
      }
      if (handle == ResizeHandleType.topLeft || handle == ResizeHandleType.bottomLeft || handle == ResizeHandleType.middleLeft) {
          left = right - newWidth;
      }

      newPosition = Offset(left, top);
      newSize = Size(newWidth, newHeight);

      try {
        updatedElement = currentElement.copyWith(position: newPosition, size: newSize);
      } catch (e, s) {
        print("Error resizing element ${currentElement.type}: $e\n$s");
        return;
      }
    }

    if (!_didResizeOccur) {
        print("Resize started, saving pre-resize state to undo stack.");
        saveToUndoStack();
        _didResizeOccur = true;
    }
    List<DrawingElement> updatedElements = List.from(elements);
    updatedElements[index] = updatedElement;
    elements = updatedElements;
    notifyListeners();
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

  void rotateSelectedImmediate(String elementId, double newRotation) {
    final element = elements.firstWhereOrNull((e) => e.id == elementId);
    if (element == null) return;

    _didRotationOccur = true;
    final index = elements.indexOf(element);
    
    if ((element.rotation - newRotation).abs() < 0.0001) return;
    
    final updatedElement = element.copyWith(
      rotation: newRotation,
    );
    
    List<DrawingElement> updatedElements = List.from(elements);
    updatedElements[index] = updatedElement;
    elements = updatedElements;
    
    notifyListeners();
  }

  void rotateSelected(String elementId, double newRotation) {
    rotateSelectedImmediate(elementId, newRotation);
  }

  void endPotentialRotation() {
    if (_didRotationOccur) {
      saveToUndoStack();
    }
  }

  // --- Scaling Logic ---
  void scaleSelected(String elementId, double scaleFactor, Offset scaleCenter) {
    final element = elements.firstWhereOrNull((e) => e.id == elementId);
    if (element == null) return;
    
    _didResizeOccur = true;
    final index = elements.indexOf(element);
    
    if ((scaleFactor - 1.0).abs() < 0.001) return;
    
    final Rect currentBounds = element.bounds;
    final Offset elementCenter = currentBounds.center;
    
    // Scale from the center
    final double newWidth = currentBounds.width * scaleFactor;
    final double newHeight = currentBounds.height * scaleFactor;
    
    // Calculate the new position to keep the center fixed
    final Offset newPosition = elementCenter - Offset(newWidth / 2, newHeight / 2);
    
    final updatedElement = element.copyWith(
      position: newPosition,
      size: Size(newWidth, newHeight),
    );
    
    List<DrawingElement> updatedElements = List.from(elements);
    updatedElements[index] = updatedElement;
    elements = updatedElements;
    
    notifyListeners();
  }

  // Add this method to handle starting transformation operations
  void startPotentialTransformation() {
    // Store the original elements state for undo/redo
    saveToUndoStack();
    _didRotationOccur = false;
    _didResizeOccur = false;
  }

  // Add this method to handle ending transformation operations
  void endPotentialTransformation() {
    // Finalize the transform operation
    if (_didRotationOccur || _didResizeOccur) {
      saveToUndoStack();
    }
    notifyListeners();
  }

  // Implement the scaleSelectedImmediate method to handle scaling
  void scaleSelectedImmediate(String elementId, double scaleFactor, Size initialSize) {
    final element = elements.firstWhereOrNull((el) => el.id == elementId);
    if (element == null) return;
    
    // Calculate new size while maintaining aspect ratio
    final newWidth = initialSize.width * scaleFactor;
    final newHeight = initialSize.height * scaleFactor;
    
    // Get the center position (to scale from center)
    final centerX = element.bounds.center.dx;
    final centerY = element.bounds.center.dy;
    
    // Calculate new bounds that keep the element centered at the same position
    final newPosition = Offset(
      centerX - newWidth / 2,
      centerY - newHeight / 2
    );
    
    // Create an updated element with new position and size
    final updatedElement = element.copyWith(
      position: newPosition,
      size: Size(newWidth, newHeight)
    );
    
    // Update the element in the list
    final index = elements.indexOf(element);
    List<DrawingElement> updatedElements = List.from(elements);
    updatedElements[index] = updatedElement;
    elements = updatedElements;
    
    // Mark that a resize occurred
    _didResizeOccur = true;
    
    // Notify listeners for UI update
    notifyListeners();
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
    selectedElementIds.clear();
    currentElement = null;
    undoStack.clear();
    redoStack.clear();
    _showContextToolbar = false;
    notifyListeners();
    print("Loaded ${elements.length} elements.");
  }

  // --- Background Removal ---
  Future<void> removeImageBackground(String elementId) async {
    final element = elements.firstWhere((e) => e.id == elementId);
    if (element is ImageElement) {
      notifyListeners();
    }
  }

  // --- Image Enhancements ---
  Future<void> applyImageEnhancements(String elementId, double brightness, double contrast) async {
    final element = elements.firstWhere((e) => e.id == elementId);
    if (element is ImageElement) {
      print("Image enhancement not implemented yet: brightness=$brightness, contrast=$contrast");
      notifyListeners();
    }
  }

  // --- General Property Updates ---
  void updateSelectedElementProperties(Map<String, dynamic> updates) {
    if (selectedElementIds.isEmpty || updates.isEmpty) return;

    saveToUndoStack();
    List<DrawingElement> updatedElements = List.from(elements);
    bool changed = false;

    for (int i = 0; i < updatedElements.length; i++) {
      if (selectedElementIds.contains(updatedElements[i].id)) {
        try {
          var current = updatedElements[i];
          DrawingElement newElement = current;

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
          } else if (current is NoteElement) {
              newElement = current.copyWith(
                  backgroundColor: updates['backgroundColor'] as Color?,
                  isPinned: updates['isPinned'] as bool?,
                  fontSize: updates['fontSize'] as double?,
              );
              if(updates.containsKey('title') || updates.containsKey('content')) {
                 print("Warning: Updating Note title/content via generic method. Size might not auto-adjust. Use updateNoteContent for size calculation.");
              }
              if (updates.containsKey('fontSize') && newElement is NoteElement) {
                  final updatedNote = newElement;
                  final Size contentSize = NoteElement.calculateSizeForContent(
                      updatedNote.title,
                      updatedNote.content,
                      updatedNote.fontSize,
                      targetWidth: updatedNote.size.width,
                      minHeight: NoteElement.MIN_HEIGHT
                  );
                  newElement = updatedNote.copyWith(size: Size(updatedNote.size.width, contentSize.height));
              }
          }

          if (newElement != current) {
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
    }
    elements.clear();
    undoStack.clear();
    redoStack.clear();
    super.dispose();
  }

  // --- Element Order Manipulation ---
  void bringSelectedForward() {
    if (selectedElementIds.isEmpty) return;
    
    saveToUndoStack();
    final selectedElements = elements.where((e) => selectedElementIds.contains(e.id)).toList();
    elements.removeWhere((e) => selectedElementIds.contains(e.id));
    elements.addAll(selectedElements);
    notifyListeners();
  }

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

    const Size defaultSize = Size(200.0, NoteElement.MIN_HEIGHT);
    
    final newNote = NoteElement(
      id: _uuid.v4(),
      position: position,
      size: defaultSize,
      title: 'New Note',
      content: 'Click to edit',
      backgroundColor: const Color(0xFFFFFA99),
      fontSize: 16.0,
    );

    elements.add(newNote);
    clearSelection();
    showContextToolbar = false; // Make sure toolbar is hidden
    
    // Reset to interaction mode after creating note
    setTool(ElementType.none);

    print("Created sticky note ${newNote.id} at $position");
  }

  void updateNoteContent(String elementId, String? title, String? content) {
    final index = elements.indexWhere((el) => el.id == elementId && el is NoteElement);
    if (index == -1) return;

    final currentNote = elements[index] as NoteElement;
    final newTitle = title?.trim();
    final newContent = content?.trim();

    if (currentNote.title == newTitle && currentNote.content == newContent) {
      print("Note content unchanged.");
      return;
    }

    saveToUndoStack();

    final Size newSize = NoteElement.calculateSizeForContent(
      newTitle,
      newContent,
      currentNote.fontSize,
      targetWidth: currentNote.size.width,
      minHeight: NoteElement.MIN_HEIGHT
    );

    final updatedNote = currentNote.copyWith(
      title: newTitle,
      content: newContent,
      size: newSize,
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

    if (currentNote.backgroundColor == color) return;

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

    final controller = VideoPlayerController.file(File(videoPath));
    await controller.initialize();

    final newVideo = VideoElement(
      id: _uuid.v4(),
      position: const Offset(100, 100),
      videoUrl: videoPath,
      controller: controller,
      size: const Size(320, 240),
    );

    elements.add(newVideo);
    clearSelection();
    selectElement(newVideo);

    print("Added video element ${newVideo.id} with path: $videoPath");
  }

  void addPenElement(Offset position) {
    saveToUndoStack();

    final newPen = PenElement(
      id: _uuid.v4(),
      position: position,
      points: [position],
      color: currentColor,
      strokeWidth: currentStrokeWidth,
    );

    elements.add(newPen);
    clearSelection();
    selectElement(newPen);

    print("Added pen element ${newPen.id} at $position");
  }

  void updatePenElement(String elementId, Offset newPoint) {
    final elementIndex = elements.indexWhere((e) => e.id == elementId);
    if (elementIndex == -1) return;

    final element = elements[elementIndex];
    if (element is! PenElement) return;

    final updatedPoints = List<Offset>.from(element.points)..add(newPoint);

    final updatedPen = element.copyWith(points: updatedPoints);

    elements[elementIndex] = updatedPen;
    notifyListeners();
  }
}