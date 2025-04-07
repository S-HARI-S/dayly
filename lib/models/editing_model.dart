import 'package:flutter/material.dart';
import 'element.dart';
import 'text_element.dart';
import 'pen_element.dart';
import 'note_element.dart';
import 'gif_element.dart';

// EditingModel manages the state of element editing in the app
// It provides methods to update properties of selected elements
class EditingModel extends ChangeNotifier {
  List<DrawingElement> elements = [];
  String? selectedElementId;
  Color currentColor = Colors.black;
  double currentFontSize = 24.0;

  DrawingElement? getElementById(String id) {
    try {
      return elements.firstWhere((element) => element.id == id);
    } catch (e) {
      return null;
    }
  }

  void selectElement(String? id) {
    selectedElementId = id;
    notifyListeners();
  }

  void updateTextColor(Color color) {
    currentColor = color;
    if (selectedElementId != null) {
      final element = getElementById(selectedElementId!);
      if (element is TextElement) {
        final updatedElement = element.copyWith(color: color);
        updateElement(updatedElement);
      }
    }
  }

  void updateTextFontSize(double fontSize) {
    currentFontSize = fontSize;
    if (selectedElementId != null) {
      final element = getElementById(selectedElementId!);
      if (element is TextElement) {
        final updatedElement = element.copyWith(fontSize: fontSize);
        updateElement(updatedElement);
      } else if (element is NoteElement) {
        final updatedElement = element.copyWith(fontSize: fontSize);
        updateElement(updatedElement);
      }
    }
  }

  void updatePenColor(Color color) {
    currentColor = color;
    if (selectedElementId != null) {
      final element = getElementById(selectedElementId!);
      if (element is PenElement) {
        final updatedElement = element.copyWith(color: color);
        updateElement(updatedElement);
      }
    }
  }

  void updateNoteColor(Color color) {
    if (selectedElementId != null) {
      final element = getElementById(selectedElementId!);
      if (element is NoteElement) {
        final updatedElement = element.copyWith(backgroundColor: color);
        updateElement(updatedElement);
      }
    }
  }

  void updateElementRotation(double rotation) {
    if (selectedElementId != null) {
      final element = getElementById(selectedElementId!);
      if (element != null) {
        final updatedElement = element.copyWith(rotation: rotation);
        updateElement(updatedElement);
      }
    }
  }

  void updateElementSize(Size size) {
    if (selectedElementId != null) {
      final element = getElementById(selectedElementId!);
      if (element != null) {
        final updatedElement = element.copyWith(size: size);
        updateElement(updatedElement);
      }
    }
  }

  void updateElement(DrawingElement updatedElement) {
    final index = elements.indexWhere((element) => element.id == updatedElement.id);
    if (index != -1) {
      elements[index] = updatedElement;
      notifyListeners();
    }
  }

  void addElement(DrawingElement element) {
    elements.add(element);
    notifyListeners();
  }

  void removeElement(String id) {
    elements.removeWhere((element) => element.id == id);
    if (selectedElementId == id) {
      selectedElementId = null;
    }
    notifyListeners();
  }

  void clearSelection() {
    selectedElementId = null;
    notifyListeners();
  }
}