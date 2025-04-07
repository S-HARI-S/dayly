import 'dart:io';
import 'dart:ui' as ui;
import 'dart:convert';
import 'package:flutter/material.dart';
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
import '../models/gif_element.dart'; // Add this import
import 'drawing_provider.dart';

class CalendarProvider extends ChangeNotifier {
  // Calendar data
  List<CalendarEntry> _entries = [];
  DateTime _selectedDate = DateTime.now();
  String? _selectedEntryId; // Track the currently selected entry ID
  
  // Getters
  List<CalendarEntry> get entries => _entries;
  DateTime get selectedDate => _selectedDate;
  String? get selectedEntryId => _selectedEntryId;
  
  // Constructor - load entries when provider is created
  CalendarProvider() {
    loadEntriesFromDisk();
  }
  
  // Get all entries for a specific date
  List<CalendarEntry> getEntriesForDate(DateTime date) {
    // Convert entries to match just date (ignore time)
    final normalizedDate = DateTime(date.year, date.month, date.day);
    return _entries.where((entry) => 
      entry.date.year == normalizedDate.year && 
      entry.date.month == normalizedDate.month && 
      entry.date.day == normalizedDate.day
    ).toList();
  }
  
  // Get a specific entry by ID
  CalendarEntry? getEntryById(String id) {
    try {
      return _entries.firstWhere((entry) => entry.id == id);
    } catch (e) {
      return null;
    }
  }
  
  // Get the currently selected entry
  CalendarEntry? get currentEntry => _selectedEntryId != null 
      ? getEntryById(_selectedEntryId!)
      : getEntriesForDate(_selectedDate).isNotEmpty 
          ? getEntriesForDate(_selectedDate).first 
          : null;
  
  // Select a date
  void selectDate(DateTime date) {
    // Normalize the date to remove time component
    _selectedDate = DateTime(date.year, date.month, date.day);
    // Reset selected entry ID when changing date
    _selectedEntryId = null;
    notifyListeners();
  }

  // Select a specific entry
  void selectEntry(String id) {
    _selectedEntryId = id;
    final entry = getEntryById(id);
    if (entry != null) {
      // Keep same date but reset the entry selection
      _selectedDate = DateTime(entry.date.year, entry.date.month, entry.date.day);
    }
    notifyListeners();
  }
  
  // Save current drawing - now with option to update existing or create new
  Future<CalendarEntry?> saveCurrentDrawing(DrawingProvider drawingProvider, {String title = '', bool updateExisting = false}) async {
    if (drawingProvider.elements.isEmpty) {
      print('Nothing to save - canvas is empty');
      return null;
    }
    
    // Check if we should update an existing entry
    if (updateExisting && _selectedEntryId != null) {
      // Update the existing entry
      final index = _entries.indexWhere((entry) => entry.id == _selectedEntryId);
      if (index >= 0) {
        await updateEntry(_selectedEntryId!, drawingProvider, title: title);
        return _entries[index];
      }
    }
    
    // Otherwise, create a new entry
    // Generate a thumbnail from the current drawing
    final thumbnailPath = await _generateThumbnail(drawingProvider.elements);
    
    // Clone all elements to ensure we store a snapshot
    final elementsCopy = drawingProvider.elements.map((e) => e.clone()).toList();
    
    // Generate a unique ID using UUID
    final uniqueId = const Uuid().v4();
    
    // Create new entry with unique ID
    final newEntry = CalendarEntry(
      date: _selectedDate,
      id: uniqueId,
      title: title,
      elements: elementsCopy,
      thumbnailPath: thumbnailPath,
      createdAt: DateTime.now(),
    );
    
    // Add to entries list
    _entries.add(newEntry);
    
    // Save entries to persistent storage
    await _saveEntriesToDisk();
    
    // Select this new entry
    _selectedEntryId = newEntry.id;
    
    notifyListeners();
    return newEntry;
  }

  // Update an existing entry
  Future<void> updateEntry(String entryId, DrawingProvider drawingProvider, {String? title}) async {
    final index = _entries.indexWhere((entry) => entry.id == entryId);
    if (index < 0) return;
    
    // Generate a thumbnail from the current drawing
    final thumbnailPath = await _generateThumbnail(drawingProvider.elements);
    
    // Clone all elements to ensure we store a snapshot
    final elementsCopy = drawingProvider.elements.map((e) => e.clone()).toList();
    
    // Update the entry
    _entries[index] = _entries[index].copyWith(
      elements: elementsCopy,
      thumbnailPath: thumbnailPath,
      title: title ?? _entries[index].title,
    );
    
    // Save to disk
    await _saveEntriesToDisk();
    
    notifyListeners();
  }
  
  // Load a saved drawing into the DrawingProvider
  void loadDrawing(String entryId, DrawingProvider drawingProvider) {
    final entry = getEntryById(entryId);
    
    if (entry != null) {
      // Save to undo stack first
      drawingProvider.saveToUndoStack();
      
      // Clone the elements to prevent shared references
      final loadedElements = entry.elements.map((e) => e.clone()).toList();
      
      // Set the elements in the drawing provider
      drawingProvider.loadElements(loadedElements);
      
      // Update selected date and entry
      selectDate(entry.date);
      _selectedEntryId = entry.id;
      
      notifyListeners();
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
      
      // Generate a unique filename for the thumbnail
      final filename = '${const Uuid().v4()}.png';
      final file = File('${thumbnailDir.path}/$filename');
      await file.writeAsBytes(buffer);
      
      return file.path;
    } catch (e, s) {
      print('Error generating thumbnail: $e\n$s');
      return null;
    }
  }
  
  // Delete a specific entry by ID
  Future<void> deleteEntry(String entryId) async {
    // First get the entry to clean up resources
    final entry = getEntryById(entryId);
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
      _entries.removeWhere((e) => e.id == entryId);
      
      // If this was the selected entry, clear selection
      if (_selectedEntryId == entryId) {
        _selectedEntryId = null;
      }
      
      // Save entries to disk
      await _saveEntriesToDisk();
      
      notifyListeners();
    }
  }
  
  // Clear all entries for a specific date
  Future<void> clearEntriesForDate(DateTime date) async {
    final entriesToDelete = getEntriesForDate(date);
    
    for (final entry in entriesToDelete) {
      await deleteEntry(entry.id);
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
    String title = entryMap['title'] ?? '';
    DateTime createdAt = entryMap.containsKey('createdAt') 
        ? DateTime.parse(entryMap['createdAt']) 
        : DateTime.now();
    
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
              
            case 'gif':
              // For GIFs, we need to reconstruct the element with the URLs
              element = _recreateGifElement(elementMap);
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
      title: title,
      elements: elements,
      thumbnailPath: thumbnailPath,
      createdAt: createdAt,
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
  
  // Helper to recreate a GifElement from serialized data
  GifElement? _recreateGifElement(Map<String, dynamic> map) {
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
      
      // Get URLs
      final String gifUrl = map['gifUrl'];
      final String? previewUrl = map['previewUrl'];
      
      // Create and return the GifElement
      return GifElement(
        id: map['id'],
        position: position,
        isSelected: map['isSelected'] ?? false,
        size: size,
        gifUrl: gifUrl,
        previewUrl: previewUrl,
      );
    } catch (e) {
      print('Error recreating GIF element: $e');
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
    // Get unique dates that have entries
    final Set<String> uniqueDates = {};
    final List<DateTime> result = [];
    
    for (var entry in _entries) {
      if (entry.date.isAfter(start.subtract(const Duration(days: 1))) &&
          entry.date.isBefore(end.add(const Duration(days: 1)))) {
            
        // Create a date string in the format YYYY-MM-DD for uniqueness check
        final dateString = '${entry.date.year}-${entry.date.month}-${entry.date.day}';
        if (!uniqueDates.contains(dateString)) {
          uniqueDates.add(dateString);
          result.add(entry.date);
        }
      }
    }
    
    return result;
  }
  
  // Get the count of entries for a specific date
  int getEntryCountForDate(DateTime date) {
    return getEntriesForDate(date).length;
  }
  
  // Generate a default title for a canvas if none is provided
  String generateDefaultTitle(DateTime date) {
    final count = getEntryCountForDate(date) + 1;
    if (count > 1) {
      return 'Canvas $count';
    }
    return 'Canvas';
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
