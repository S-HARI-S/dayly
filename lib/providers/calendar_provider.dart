import 'dart:io';
import 'dart:ui' as ui;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:video_player/video_player.dart';

import '../models/calendar_entry.dart';
import '../models/element.dart';
import '../models/pen_element.dart';
import '../models/text_element.dart';
import '../models/image_element.dart';
import '../models/video_element.dart';
import 'drawing_provider.dart';

class CalendarProvider extends ChangeNotifier {
  // Calendar data
  List<CalendarEntry> _entries = [];
  DateTime _selectedDate = DateTime.now();
  
  // Getters
  List<CalendarEntry> get entries => _entries;
  DateTime get selectedDate => _selectedDate;
  
  // Constructor - load entries when provider is created
  CalendarProvider() {
    loadEntriesFromDisk();
  }
  
  // Find entry for a specific date
  CalendarEntry? getEntryForDate(DateTime date) {
    try {
      return _entries.firstWhere(
        (entry) => entry.matchesDate(date),
      );
    } catch (e) {
      return null;
    }
  }
  
  // Get entry for currently selected date
  CalendarEntry? get currentEntry => getEntryForDate(_selectedDate);
  
  // Select a date
  void selectDate(DateTime date) {
    _selectedDate = date;
    notifyListeners();
  }
  
  // Save current drawing as today's entry
  Future<void> saveCurrentDrawing(DrawingProvider drawingProvider) async {
    // Generate a thumbnail from the current drawing
    final thumbnailPath = await _generateThumbnail(drawingProvider.elements);
    
    // Clone all elements to ensure we store a snapshot
    final elementsCopy = drawingProvider.elements.map((e) => e.clone()).toList();
    
    // Check if there's already an entry for today
    final existingEntryIndex = _entries.indexWhere(
      (entry) => entry.matchesDate(_selectedDate)
    );
    
    if (existingEntryIndex >= 0) {
      // Update existing entry
      _entries[existingEntryIndex] = _entries[existingEntryIndex].copyWith(
        elements: elementsCopy,
        thumbnailPath: thumbnailPath,
      );
    } else {
      // Create new entry
      _entries.add(
        CalendarEntry(
          date: _selectedDate,
          elements: elementsCopy,
          thumbnailPath: thumbnailPath,
        )
      );
    }
    
    // Save entries to persistent storage
    await _saveEntriesToDisk();
    
    notifyListeners();
  }
  
  // Load a saved drawing into the DrawingProvider
  void loadDrawing(DateTime date, DrawingProvider drawingProvider) {
    final entry = getEntryForDate(date);
    
    if (entry != null) {
      // Save to undo stack first
      drawingProvider.saveToUndoStack();
      
      // Clone the elements to prevent shared references
      final loadedElements = entry.elements.map((e) => e.clone()).toList();
      
      // Set the elements in the drawing provider
      drawingProvider.loadElements(loadedElements);
      
      // Update selected date
      selectDate(date);
    }
  }
  
  // Generate a thumbnail image from the current drawing
  Future<String?> _generateThumbnail(List<DrawingElement> elements) async {
    if (elements.isEmpty) return null;
    
    try {
      // Create a recorder to capture the drawing
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      
      // Define a fixed size for the thumbnail (adjust as needed)
      const thumbnailSize = Size(320, 240);
      
      // Calculate bounds of all elements
      Rect? boundingRect;
      for (var element in elements) {
        if (boundingRect == null) {
          boundingRect = element.bounds;
        } else {
          boundingRect = boundingRect.expandToInclude(element.bounds);
        }
      }
      
      // If we have elements but no valid bounds, return null
      if (boundingRect == null || boundingRect.isEmpty) {
        return null;
      }
      
      // Apply a scale to fit everything into the thumbnail
      final scaleX = thumbnailSize.width / boundingRect.width;
      final scaleY = thumbnailSize.height / boundingRect.height;
      final scale = scaleX < scaleY ? scaleX : scaleY;
      
      // Translate to center the content
      final offsetX = -boundingRect.left + (thumbnailSize.width / scale - boundingRect.width) / 2;
      final offsetY = -boundingRect.top + (thumbnailSize.height / scale - boundingRect.height) / 2;
      
      // Set up transform
      canvas.translate(offsetX, offsetY);
      canvas.scale(scale);
      
      // Fill background
      canvas.drawRect(
        Rect.fromLTWH(boundingRect.left, boundingRect.top, boundingRect.width, boundingRect.height),
        Paint()..color = Colors.white
      );
      
      // Render each element
      for (var element in elements) {
        // Skip video elements in thumbnails (they're too complex)
        if (element is VideoElement) {
          continue;
        }
        element.render(canvas, inverseScale: 1.0);
      }
      
      // End recording and convert to image
      final picture = recorder.endRecording();
      final img = await picture.toImage(
        thumbnailSize.width.toInt(),
        thumbnailSize.height.toInt(),
      );
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      final buffer = byteData?.buffer.asUint8List();
      
      if (buffer == null) {
        return null;
      }
      
      // Save the image to a file
      final directory = await getApplicationDocumentsDirectory();
      final thumbnailDir = Directory('${directory.path}/thumbnails');
      await thumbnailDir.create(recursive: true);
      
      final fileName = '${const Uuid().v4()}.png';
      final file = File('${thumbnailDir.path}/$fileName');
      await file.writeAsBytes(buffer);
      
      return file.path;
    } catch (e) {
      print('Error generating thumbnail: $e');
      return null;
    }
  }
  
  // Clear the entry for a specific date
  Future<void> clearEntry(DateTime date) async {
    // First get the entry to clean up resources
    final entry = getEntryForDate(date);
    if (entry != null) {
      // Delete thumbnail file if it exists
      if (entry.thumbnailPath != null) {
        try {
          final thumbnailFile = File(entry.thumbnailPath!);
          if (await thumbnailFile.exists()) {
            await thumbnailFile.delete();
          }
        } catch (e) {
          print('Error deleting thumbnail: $e');
        }
      }
      
      // Dispose any video elements
      for (final element in entry.elements) {
        if (element is VideoElement) {
          element.dispose();
        }
      }
      
      // Remove entry
      _entries.removeWhere((entry) => entry.matchesDate(date));
      
      // Save entries to disk
      await _saveEntriesToDisk();
      
      notifyListeners();
    }
  }
  
  // Persistence methods - Improved
  Future<void> _saveEntriesToDisk() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/calendar_entries.json');
      
      // Convert entries to JSON format
      final entriesList = _entries.map((entry) => entry.toJson()).toList();
      final entriesJson = json.encode(entriesList);
      
      // Write to file
      await file.writeAsString(entriesJson);
      print('Saved ${_entries.length} entries to disk');
    } catch (e) {
      print('Error saving entries to disk: $e');
    }
  }
  
  Future<void> loadEntriesFromDisk() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/calendar_entries.json');
      
      if (await file.exists()) {
        final String content = await file.readAsString();
        
        // Parse JSON content
        final List<dynamic> entriesJsonList = json.decode(content);
        
        // List to hold fully loaded entries
        List<CalendarEntry> loadedEntries = [];
        
        // Process each entry
        for (var entryJson in entriesJsonList) {
          try {
            // Parse the entry
            Map<String, dynamic> entryMap = json.decode(entryJson);
            
            // Create entry with reconstructed elements
            CalendarEntry entry = await _recreateEntryWithElements(entryMap);
            loadedEntries.add(entry);
          } catch (e) {
            print('Error parsing entry: $e');
          }
        }
        
        _entries = loadedEntries;
        print('Loaded ${_entries.length} entries from disk');
        notifyListeners();
      } else {
        print('No saved entries found');
      }
    } catch (e) {
      print('Error loading entries from disk: $e');
    }
  }
  
  // Helper method to rebuild a calendar entry with its elements
  Future<CalendarEntry> _recreateEntryWithElements(Map<String, dynamic> entryMap) async {
    // Parse basic entry data
    DateTime date = DateTime.parse(entryMap['date']);
    String id = entryMap['id'];
    String? thumbnailPath = entryMap['thumbnailPath'];
    
    // Process elements
    List<DrawingElement> elements = [];
    if (entryMap['elements'] != null) {
      for (var elementMap in entryMap['elements']) {
        try {
          String elementType = elementMap['elementType'] ?? 'unknown';
          DrawingElement? element;
          
          // Create the appropriate element type
          switch (elementType) {
            case 'pen':
              element = PenElement.fromMap(elementMap);
              break;
              
            case 'text':
              element = TextElement.fromMap(elementMap);
              break;
              
            case 'image':
              // For images, we need to load the image data
              element = await _recreateImageElement(elementMap);
              break;
              
            case 'video':
              // For videos, we need to create a video controller
              element = await _recreateVideoElement(elementMap);
              break;
              
            default:
              print('Unknown element type: $elementType');
              break;
          }
          
          // Add the element if successfully created
          if (element != null) {
            elements.add(element);
          }
        } catch (e) {
          print('Error recreating element: $e');
        }
      }
    }
    
    // Create and return the entry
    return CalendarEntry(
      date: date,
      id: id,
      elements: elements,
      thumbnailPath: thumbnailPath,
    );
  }
  
  // Helper to recreate an ImageElement from serialized data
  Future<ImageElement?> _recreateImageElement(Map<String, dynamic> map) async {
    try {
      // Parse position
      final posMap = map['position'];
      final position = Offset(
        posMap['dx'] as double,
        posMap['dy'] as double
      );
      
      // Parse size
      final sizeMap = map['size'];
      final size = Size(
        sizeMap['width'] as double,
        sizeMap['height'] as double
      );
      
      // Get image path
      final String? imagePath = map['imagePath'];
      
      if (imagePath != null) {
        // Load image from file
        File imageFile = File(imagePath);
        if (await imageFile.exists()) {
          Uint8List bytes = await imageFile.readAsBytes();
          final codec = await ui.instantiateImageCodec(bytes);
          final frame = await codec.getNextFrame();
          final image = frame.image;
          
          // Create and return the ImageElement
          return ImageElement(
            id: map['id'],
            position: position,
            isSelected: map['isSelected'] ?? false,
            image: image,
            size: size,
            imagePath: imagePath,
          );
        }
      }
      
      // If we can't load the image, return null
      print('Could not load image from path: $imagePath');
      return null;
    } catch (e) {
      print('Error recreating image element: $e');
      return null;
    }
  }
  
  // Helper to recreate a VideoElement from serialized data
  Future<VideoElement?> _recreateVideoElement(Map<String, dynamic> map) async {
    try {
      // Parse position
      final posMap = map['position'];
      final position = Offset(
        posMap['dx'] as double,
        posMap['dy'] as double
      );
      
      // Parse size
      final sizeMap = map['size'];
      final size = Size(
        sizeMap['width'] as double,
        sizeMap['height'] as double
      );
      
      // Get video URL
      final String videoUrl = map['videoUrl'];
      
      // Create and initialize the controller
      VideoPlayerController controller;
      if (videoUrl.startsWith('http')) {
        controller = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
      } else {
        controller = VideoPlayerController.file(File(videoUrl));
      }
      
      // Initialize the controller
      await controller.initialize();
      
      // Create and return the VideoElement
      return VideoElement(
        id: map['id'],
        position: position,
        isSelected: map['isSelected'] ?? false,
        videoUrl: videoUrl,
        controller: controller,
        size: size,
      );
    } catch (e) {
      print('Error recreating video element: $e');
      return null;
    }
  }
  
  // Get entries for a specific month
  List<CalendarEntry> getEntriesForMonth(int year, int month) {
    return _entries.where((entry) => 
      entry.date.year == year && entry.date.month == month
    ).toList();
  }
  
  // Check if there's an entry for a specific date
  bool hasEntryFor(DateTime date) {
    return _entries.any((entry) => entry.matchesDate(date));
  }

  // Get a list of dates that have entries in a given month range
  List<DateTime> getDatesWithEntries(DateTime start, DateTime end) {
    return _entries
        .where((entry) => 
            entry.date.isAfter(start.subtract(const Duration(days: 1))) &&
            entry.date.isBefore(end.add(const Duration(days: 1))))
        .map((entry) => entry.date)
        .toList();
  }
  
  // Clean up resources
  @override
  void dispose() {
    // Dispose of all video elements
    for (var entry in _entries) {
      for (var element in entry.elements) {
        if (element is VideoElement) {
          element.dispose();
        }
      }
    }
    super.dispose();
  }
}
