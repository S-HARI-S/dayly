// lib/providers/drawing_provider.dart
import 'package:flutter/material.dart';
import '../models/element.dart';
import '../models/pen_element.dart';
import '../models/text_element.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import '../models/image_element.dart';
import '../models/video_element.dart';

class DrawingProvider extends ChangeNotifier {
Future<void> addImageFromGallery(BuildContext context) async {
  try {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    
    if (pickedFile != null) {
      try {
        final bytes = await pickedFile.readAsBytes();
        final codec = await ui.instantiateImageCodec(bytes);
        final frameInfo = await codec.getNextFrame();
        
        saveToUndoStack();
        
        // Calculate a reasonable size (maintain aspect ratio)
        final imageWidth = frameInfo.image.width.toDouble();
        final imageHeight = frameInfo.image.height.toDouble();
        
        // Default size (can be adjusted)
        double width = 300;
        double height = (imageHeight / imageWidth) * width;
        
        final center = Offset(
          MediaQuery.of(context).size.width / 2,
          MediaQuery.of(context).size.height / 2,
        );
        
        final imageElement = ImageElement(
          image: frameInfo.image,
          position: Offset(center.dx - width / 2, center.dy - height / 2),
          size: Size(width, height),
        );
        
        elements.add(imageElement);
        notifyListeners();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load image: ${e.toString()}')),
        );
      }
    }
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Error picking image: ${e.toString()}')),
    );
    print('Image picker error: $e');
  }
}

Future<void> addVideoFromGallery(BuildContext context) async {
  try {
    final picker = ImagePicker();
    final pickedFile = await picker.pickVideo(source: ImageSource.gallery);
    
    if (pickedFile != null) {
      saveToUndoStack();
      
      // Create a video controller
      final controller = VideoPlayerController.file(File(pickedFile.path));
      
      // Wait for controller to initialize
      try {
        await controller.initialize();
        
        // Calculate a reasonable size (maintain aspect ratio)
        final videoWidth = controller.value.size.width;
        final videoHeight = controller.value.size.height;
        
        // Default size (can be adjusted)
        double width = 320;
        double height = (videoHeight / videoWidth) * width;
        
        final center = Offset(
          MediaQuery.of(context).size.width / 2,
          MediaQuery.of(context).size.height / 2,
        );
        
        final videoElement = VideoElement(
          videoUrl: pickedFile.path,
          controller: controller,
          position: Offset(center.dx - width / 2, center.dy - height / 2),
          size: Size(width, height),
        );
        
        elements.add(videoElement);
        notifyListeners();
      } catch (e) {
        // If video initialization fails, dispose of controller and show error
        controller.dispose();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load video: ${e.toString()}')),
        );
      }
    }
  } catch (e) {
    // Show a user-friendly error message
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Error picking video: ${e.toString()}')),
    );
    print('Video picker error: $e');
  }
}

  void toggleVideoPlayback(String elementId) {
    for (int i = 0; i < elements.length; i++) {
      if (elements[i].id == elementId && elements[i] is VideoElement) {
        final videoElement = elements[i] as VideoElement;
        videoElement.togglePlayPause();
        notifyListeners();
        break;
      }
    }
  }

  // Override dispose method to clean up video controllers
  @override
  void dispose() {
    for (final element in elements) {
      if (element is VideoElement) {
        element.dispose();
      }
    }
    super.dispose();
  }

  // Current active tool
  ElementType currentTool = ElementType.pen;

  // Drawing elements
  List<DrawingElement> elements = [];

  // Current drawing element (being created)
  DrawingElement? currentElement;

  // Selection state
  List<String> selectedElementIds = [];

  // Undo/redo stacks
  List<List<DrawingElement>> undoStack = [];
  List<List<DrawingElement>> redoStack = [];

  // Current color and stroke width
  Color currentColor = Colors.black;
  double currentStrokeWidth = 2.0;

  // Grouping
  Map<String, List<String>> groups = {};

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

  void startDrawing(Offset position) {
    // Save current state for undo
    saveToUndoStack();

    switch (currentTool) {
      case ElementType.pen:
        currentElement = PenElement(
          position: position,
          color: currentColor,
          points: [position],
          strokeWidth: currentStrokeWidth,
        );
        break;

      // Implement creation logic for other element types if needed

      default:
        break;
    }

    notifyListeners();
  }

  void updateDrawing(Offset position) {
    if (currentElement == null) return;

    switch (currentElement!.type) {
      case ElementType.pen:
        final penElement = currentElement as PenElement;
        final updatedPoints = List<Offset>.from(penElement.points)
          ..add(position);
        currentElement = penElement.copyWith(points: updatedPoints);
        break;

      // Implement update logic for other element types if needed

      default:
        break;
    }

    notifyListeners();
  }

  void addTextElement(String text, Offset position) {
    saveToUndoStack();
    // Create a new text element using your TextElement model
    final newTextElement = TextElement(
      position: position,
      text: text,
      color: currentColor,
    );
    elements.add(newTextElement);
    notifyListeners();
  }

  void endDrawing() {
    if (currentElement != null) {
      elements.add(currentElement!);
      currentElement = null;
      notifyListeners();
    }
  }

  void selectElementAt(Offset position) {
    clearSelection();

    // Check elements in reverse order (top to bottom)
    for (int i = elements.length - 1; i >= 0; i--) {
      if (elements[i].containsPoint(position)) {
        selectedElementIds.add(elements[i].id);
        elements[i] = elements[i].copyWith(isSelected: true);
        notifyListeners();
        break;
      }
    }
  }

  void clearSelection() {
    for (int i = 0; i < elements.length; i++) {
      if (elements[i].isSelected) {
        elements[i] = elements[i].copyWith(isSelected: false);
      }
    }

    selectedElementIds.clear();
    notifyListeners();
  }

  void deleteSelected() {
    if (selectedElementIds.isEmpty) return;

    saveToUndoStack();

    elements.removeWhere((element) => selectedElementIds.contains(element.id));
    selectedElementIds.clear();

    notifyListeners();
  }

  void moveSelected(Offset delta) {
    if (selectedElementIds.isEmpty) return;

    for (int i = 0; i < elements.length; i++) {
      if (selectedElementIds.contains(elements[i].id)) {
        elements[i] = elements[i].copyWith(
          position: elements[i].position + delta,
        );
      }
    }

    notifyListeners();
  }

  // Undo/Redo functionality
  void saveToUndoStack() {
    undoStack.add(List.from(elements));
    redoStack.clear();
  }

  void undo() {
    if (undoStack.isEmpty) return;

    redoStack.add(List.from(elements));
    elements = undoStack.removeLast();
    clearSelection();

    notifyListeners();
  }

  void redo() {
    if (redoStack.isEmpty) return;

    undoStack.add(List.from(elements));
    elements = redoStack.removeLast();
    clearSelection();

    notifyListeners();
  }

  // Grouping functionality
  void groupSelected() {
    if (selectedElementIds.length < 2) return;

    final groupId = 'group-${DateTime.now().millisecondsSinceEpoch}';
    groups[groupId] = List.from(selectedElementIds);

    notifyListeners();
  }

  void ungroupSelected() {
    if (selectedElementIds.isEmpty) return;

    groups.removeWhere((groupId, memberIds) {
      return selectedElementIds.contains(groupId);
    });

    notifyListeners();
  }
}
