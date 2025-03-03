// lib/providers/drawing_provider.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/element.dart';
import '../models/pen_element.dart';
// Import other element types

class DrawingProvider extends ChangeNotifier {
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
      
      // Implement other element creation logic
      
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
        final updatedPoints = List<Offset>.from(penElement.points)..add(position);
        currentElement = penElement.copyWith(points: updatedPoints);
        break;
      
      // Implement update logic for other element types
      
      default:
        break;
    }
    
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