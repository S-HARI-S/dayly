// lib/providers/drawing_provider.dart
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:vector_math/vector_math_64.dart' show Matrix4, MatrixUtils;
import 'package:collection/collection.dart';

import '../models/element.dart';
import '../models/pen_element.dart';
import '../models/text_element.dart';
import '../models/image_element.dart';
import '../models/video_element.dart';
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

  // State tracking
  bool _didMoveOccur = false;
  bool _didResizeOccur = false;

  // --- Tool and Style Management ---
  void setTool(ElementType tool) {
    currentTool = tool;
    clearSelection();
    notifyListeners();
  }
  
  void setColor(Color color) {
    currentColor = color;
    notifyListeners();
  }
  
  void setStrokeWidth(double width) {
    currentStrokeWidth = width;
    notifyListeners();
  }

  // --- Undo/Redo Core ---
  void saveToUndoStack() {
    try {
      final List<DrawingElement> clonedElements = elements.map((el) => el.clone()).toList();
      undoStack.add(clonedElements);
      if (undoStack.length > maxUndoSteps) undoStack.removeAt(0);
      redoStack.clear();
      print("State saved (${undoStack.length} states)");
    } catch (e) { 
      print("Error cloning for undo: $e");
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
    } catch(e) {
      print("Error creating redo state: $e");
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
    } catch(e) {
      print("Error saving current state: $e");
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
      print("Error getting canvas center: $e. Using default.");
      return const Offset(50000, 50000);
    }
  }
  
  Future<void> addImageFromGallery(BuildContext context, TransformationController controller) async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);
      
      if (pickedFile == null) return;
      
      saveToUndoStack();
      
      final bytes = await File(pickedFile.path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      
      const double width = 300;
      final double aspectRatio = image.height == 0 ? 1.0 : image.width / image.height;
      final size = Size(width, aspectRatio == 0 ? width : width / aspectRatio);
      
      final position = _getCanvasCenter(controller, context) - Offset(size.width / 2, size.height / 2);
      
      elements.add(ImageElement(
        image: image,
        position: position,
        size: size,
      ));
      
      clearSelection();
      notifyListeners();
      
    } catch (e) {
      print('Error adding image: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error adding image: ${e.toString()}')),
      );
    }
  }
  
  Future<void> addVideoFromGallery(BuildContext context, TransformationController controller) async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickVideo(source: ImageSource.gallery);
      
      if (pickedFile == null) return;
      
      saveToUndoStack();
      
      final videoController = VideoPlayerController.file(File(pickedFile.path));
      await videoController.initialize();
      
      const double width = 320;
      final double aspectRatio = videoController.value.aspectRatio == 0 ? 1.0 : videoController.value.aspectRatio;
      final size = Size(width, aspectRatio == 0 ? width : width / aspectRatio);
      
      final position = _getCanvasCenter(controller, context) - Offset(size.width / 2, size.height / 2);
      
      elements.add(VideoElement(
        videoUrl: pickedFile.path,
        controller: videoController,
        position: position,
        size: size,
      ));
      
      clearSelection();
      notifyListeners();
      
    } catch (e) {
      print('Error adding video: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error adding video: ${e.toString()}')),
      );
    }
  }
  
  void addTextElement(String text, Offset position) {
    if (text.trim().isEmpty) return;
    
    saveToUndoStack();
    
    elements.add(TextElement(
      position: position,
      text: text,
      color: currentColor,
      fontSize: 24.0,
    ));
    
    clearSelection();
    notifyListeners();
  }

  // --- Drawing Lifecycle (Pen Tool) ---
  void startDrawing(Offset position) {
    if (currentTool != ElementType.pen) return;
    
    currentElement = PenElement(
      position: position,
      points: [position],
      color: currentColor,
      strokeWidth: currentStrokeWidth,
    );
    
    notifyListeners();
  }
  
  void updateDrawing(Offset position) {
    if (currentElement is! PenElement) return;
    
    final pen = currentElement as PenElement;
    currentElement = pen.copyWith(
      points: List.from(pen.points)..add(position)
    );
    
    notifyListeners();
  }
  
  void endDrawing() {
    if (currentElement == null) return;
    
    bool valid = true;
    if (currentElement is PenElement) {
      valid = (currentElement as PenElement).points.length >= 2;
    }
    
    if (valid) {
      saveToUndoStack();
      elements.add(currentElement!);
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
    final DrawingElement? element = elements.lastWhereOrNull((e) => e.containsPoint(position));
    
    if (element != null) {
      if (!(selectedElementIds.length == 1 && selectedElementIds.first == element.id)) {
        clearSelection(notify: false);
        selectedElementIds.add(element.id);
        
        int index = elements.indexWhere((e) => e.id == element.id);
        if (index != -1) {
          elements[index] = elements[index].copyWith(isSelected: true);
          print("Selected element ${element.id}");
        }
        
        notifyListeners();
      }
    } else if (selectedElementIds.isNotEmpty) {
      print("Clearing selection");
      clearSelection();
    }
  }
  
  void clearSelection({bool notify = true}) {
    if (selectedElementIds.isEmpty) return;
    
    bool changed = false;
    List<DrawingElement> updatedElements = List.from(elements);
    List<String> ids = List.from(selectedElementIds);
    selectedElementIds.clear();
    
    for (int i = 0; i < updatedElements.length; i++) {
      if (ids.contains(updatedElements[i].id) && updatedElements[i].isSelected) {
        updatedElements[i] = updatedElements[i].copyWith(isSelected: false);
        changed = true;
      }
    }
    
    if (changed) {
      elements = updatedElements;
    }
    
    if (notify) {
      notifyListeners();
    }
  }
  
  void deleteSelected() {
    if (selectedElementIds.isEmpty) return;
    
    saveToUndoStack();
    
    int count = selectedElementIds.length;
    List<String> ids = List.from(selectedElementIds);
    selectedElementIds.clear();
    
    // Dispose video controllers
    for (String id in ids) {
      final element = elements.firstWhereOrNull((e) => e.id == id);
      if (element is VideoElement) {
        element.dispose();
      }
    }
    
    elements.removeWhere((e) => ids.contains(e.id));
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

    Offset newPosition = currentBounds.topLeft;
    Size newSize = currentBounds.size;

    // Calculate new bounds based on handle type and pointer position
    switch (handle) {
      case ResizeHandleType.bottomRight:
        newPosition = currentBounds.topLeft;
        newSize = Size(
          (currentPointerPos.dx - currentBounds.left).clamp(10.0, double.infinity),
          (currentPointerPos.dy - currentBounds.top).clamp(10.0, double.infinity)
        );
        break;
      case ResizeHandleType.bottomLeft:
        newPosition = Offset(currentPointerPos.dx, currentBounds.top);
        newSize = Size(
          (currentBounds.right - currentPointerPos.dx).clamp(10.0, double.infinity),
          (currentPointerPos.dy - currentBounds.top).clamp(10.0, double.infinity)
        );
        break;
      case ResizeHandleType.topRight:
        newPosition = Offset(currentBounds.left, currentPointerPos.dy);
        newSize = Size(
          (currentPointerPos.dx - currentBounds.left).clamp(10.0, double.infinity),
          (currentBounds.bottom - currentPointerPos.dy).clamp(10.0, double.infinity)
        );
        break;
      case ResizeHandleType.topLeft:
        newPosition = currentPointerPos;
        newSize = Size(
          (currentBounds.right - currentPointerPos.dx).clamp(10.0, double.infinity),
          (currentBounds.bottom - currentPointerPos.dy).clamp(10.0, double.infinity)
        );
        break;
      case ResizeHandleType.bottomMiddle:
        newPosition = currentBounds.topLeft;
        newSize = Size(
          currentBounds.width,
          (currentPointerPos.dy - currentBounds.top).clamp(10.0, double.infinity)
        );
        break;
      case ResizeHandleType.topMiddle:
        newPosition = Offset(currentBounds.left, currentPointerPos.dy);
        newSize = Size(
          currentBounds.width,
          (currentBounds.bottom - currentPointerPos.dy).clamp(10.0, double.infinity)
        );
        break;
      case ResizeHandleType.middleRight:
        newPosition = currentBounds.topLeft;
        newSize = Size(
          (currentPointerPos.dx - currentBounds.left).clamp(10.0, double.infinity),
          currentBounds.height
        );
        break;
      case ResizeHandleType.middleLeft:
        newPosition = Offset(currentPointerPos.dx, currentBounds.top);
        newSize = Size(
          (currentBounds.right - currentPointerPos.dx).clamp(10.0, double.infinity),
          currentBounds.height
        );
        break;
      default:
        print("Resize handle type $handle not implemented");
        return;
    }

    DrawingElement? updatedElement;
    try {
      updatedElement = currentElement.copyWith(
        position: newPosition,
        size: newSize,
      );
    } catch (e, s) {
      print("Error resizing element ${currentElement.type}: $e");
      print("Stack trace: $s");
      return;
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

  // --- Cleanup ---
  @override
  void dispose() {
    print("Disposing DrawingProvider");
    
    for (final element in elements) {
      if (element is VideoElement) {
        element.dispose();
      }
    }
    
    undoStack.clear();
    redoStack.clear();
    super.dispose();
  }
}