import 'dart:io';
import 'dart:ui' as ui;
import 'dart:convert';
import 'dart:math' as math;
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
import '../models/note_element.dart'; // Add import for NoteElement
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
    
    print('Saving drawing with ${drawingProvider.elements.length} elements');
    
    // Check if we should update an existing entry
    if (updateExisting && _selectedEntryId != null) {
      // Update the existing entry
      final index = _entries.indexWhere((entry) => entry.id == _selectedEntryId);
      if (index >= 0) {
        print('Updating existing entry: $_selectedEntryId');
        await updateEntry(_selectedEntryId!, drawingProvider, title: title);
        return _entries[index];
      }
    }
    
    // Otherwise, create a new entry
    // Generate a thumbnail from the current drawing
    print('Generating thumbnail for new entry');
    final thumbnailPath = await _generateThumbnail(drawingProvider.elements);
    print('Thumbnail generated: $thumbnailPath');
    
    // Clone all elements to ensure we store a snapshot
    final elementsCopy = drawingProvider.elements.map((e) => e.clone()).toList();
    print('Cloned ${elementsCopy.length} elements');
    
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
    if (index < 0) {
      print('Cannot update entry: Entry with ID $entryId not found');
      return;
    }
    
    print('Updating entry $entryId with ${drawingProvider.elements.length} elements');
    
    // Generate a thumbnail from the current drawing
    print('Generating thumbnail for updated entry');
    final thumbnailPath = await _generateThumbnail(drawingProvider.elements);
    print('Thumbnail generated: $thumbnailPath');
    
    // Clone all elements to ensure we store a snapshot
    final elementsCopy = drawingProvider.elements.map((e) => e.clone()).toList();
    print('Cloned ${elementsCopy.length} elements');
    
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
    if (elements.isEmpty) {
      return null;
    }

    final uniqueId = const Uuid().v4(); // Unique ID for this thumbnail attempt

    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      const thumbnailSize = Size(320, 240); // Fixed size for thumbnail

      // Fill background
      canvas.drawRect(
        Rect.fromLTWH(0, 0, thumbnailSize.width, thumbnailSize.height),
        Paint()..color = Colors.white,
      );

      // Calculate bounds
      Rect? boundingRect;
      for (var element in elements) {
        try {
           if (boundingRect == null) {
             boundingRect = element.bounds;
           } else {
             boundingRect = boundingRect.expandToInclude(element.bounds);
           }
        } catch (e) {
        }
      }

      if (boundingRect == null || boundingRect.isEmpty || !boundingRect.isFinite) {
         // Draw a fallback message directly onto the canvas
        final textPainter = TextPainter(
          text: const TextSpan(text: 'Preview Error', style: TextStyle(color: Colors.red, fontSize: 16)),
          textDirection: ui.TextDirection.ltr,
        )..layout();
        textPainter.paint(canvas, Offset((thumbnailSize.width - textPainter.width) / 2, (thumbnailSize.height - textPainter.height) / 2));

      } else {

        // Calculate scale and offset
        final scaleX = boundingRect.width > 0 ? thumbnailSize.width / boundingRect.width : 1.0;
        final scaleY = boundingRect.height > 0 ? thumbnailSize.height / boundingRect.height : 1.0;
        final scale = math.min(scaleX, scaleY) * 0.9; // Use 90% space

        // Center the content
        final scaledWidth = boundingRect.width * scale;
        final scaledHeight = boundingRect.height * scale;
        final translateX = (thumbnailSize.width - scaledWidth) / 2 - (boundingRect.left * scale);
        final translateY = (thumbnailSize.height - scaledHeight) / 2 - (boundingRect.top * scale);

        // Apply transform
        canvas.save(); // Save state before transform
        canvas.translate(translateX, translateY);
        canvas.scale(scale);

        // Render elements
        for (var element in elements) {
          try {
            // Skip video elements in thumbnails
            if (element is VideoElement) {
              // Optionally draw a placeholder for video
              canvas.drawRect(element.bounds, Paint()..color = Colors.grey[300]!);
              // Remove const from TextSpan
              final textPainter = TextPainter(text: TextSpan(text: 'VIDEO', style: TextStyle(color: Colors.black54, fontSize: 10 / scale)), textDirection: ui.TextDirection.ltr)..layout();
              textPainter.paint(canvas, element.bounds.center.translate(-textPainter.width / 2, -textPainter.height / 2));
              continue;
            }

            canvas.save(); // Save state for this element's transform/rendering

            // Apply element's rotation if any
            if (element.rotation != 0) {
              final center = element.bounds.center;
              canvas.translate(center.dx, center.dy);
              canvas.rotate(element.rotation);
              canvas.translate(-center.dx, -center.dy);
            }

            // Render based on type (simplified rendering for complex types if needed)
            if (element is ImageElement) {
               if (element.image != null) {
                 // Use drawImageRect for better control if needed, or just drawImage
                 canvas.drawImageRect(
                   element.image!,
                   Rect.fromLTWH(0, 0, element.image!.width.toDouble(), element.image!.height.toDouble()),
                   element.bounds,
                   Paint()..filterQuality = FilterQuality.low, // Use lower quality for thumbs
                 );
               } else {
                 canvas.drawRect(element.bounds, Paint()..color = Colors.grey[200]!); // Placeholder
               }
            } else if (element is GifElement) {
               // Draw placeholder for GIF, attempting first frame is too complex/slow here
               canvas.drawRect(element.bounds, Paint()..color = Colors.purple[100]!);
               // Remove const from TextSpan
               final textPainter = TextPainter(text: TextSpan(text: 'GIF', style: TextStyle(color: Colors.purple, fontSize: 10 / scale)), textDirection: ui.TextDirection.ltr)..layout();
               textPainter.paint(canvas, element.bounds.center.translate(-textPainter.width / 2, -textPainter.height / 2));
            } else if (element is NoteElement) {
               // Simplified Note Rendering for Thumbnail
               final rect = element.bounds;
               final Paint backgroundPaint = Paint()..color = element.backgroundColor;
               canvas.drawRRect(
                 // Remove const from Radius.circular
                 RRect.fromRectAndRadius(rect, Radius.circular(4.0 / scale)), // Scale radius
                 backgroundPaint
               );
               // Maybe just draw title or an icon, full text rendering is slow
               final textPainter = TextPainter(
                 text: TextSpan(text: element.title?.isNotEmpty == true ? element.title : 'Note', style: TextStyle(color: Colors.black87, fontSize: 8 / scale, fontWeight: FontWeight.bold)),
                 textDirection: ui.TextDirection.ltr,
                 maxLines: 1,
                 ellipsis: '...',
               )..layout(maxWidth: rect.width - (8.0 / scale));
               textPainter.paint(canvas, rect.topLeft.translate(4.0 / scale, 4.0 / scale));
               if (element.isPinned) {
                  final pinPaint = Paint()..color = Colors.red.shade700;
                  canvas.drawCircle(rect.topRight.translate(-6 / scale, 6 / scale), 3 / scale, pinPaint);
               }
            }
            else {
              // Use standard render for Pen, Text etc.
              element.render(canvas, inverseScale: 1.0 / scale); // Pass inverse scale if needed by render
            }

            canvas.restore(); // Restore state after rendering element

          } catch (e, s) {
            // Draw an error placeholder for this specific element
             try {
               canvas.drawRect(element.bounds, Paint()..color = Colors.red.withOpacity(0.3));
               // Remove const from TextSpan
               final textPainter = TextPainter(text: TextSpan(text: 'ERR', style: TextStyle(color: Colors.red, fontSize: 8 / scale)), textDirection: ui.TextDirection.ltr)..layout();
               textPainter.paint(canvas, element.bounds.center.translate(-textPainter.width / 2, -textPainter.height / 2));
             } catch (placeholderError) {
             }
             // Ensure canvas state is restored even if rendering fails
             canvas.restore(); // Make sure restore is called if save was called
          }
        }
        canvas.restore(); // Restore state after transform
      }


      // End recording and generate image
      final picture = recorder.endRecording();

      final img = await picture.toImage(
        thumbnailSize.width.toInt(),
        thumbnailSize.height.toInt(),
      );

      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      img.dispose(); // Dispose image object
      picture.dispose(); // Dispose picture object
      final buffer = byteData?.buffer.asUint8List();

      if (buffer == null || buffer.isEmpty) {
        return null;
      }

      // Save the image to a file
      final directory = await getApplicationDocumentsDirectory();
      final thumbnailDir = Directory('${directory.path}/thumbnails');
      if (!await thumbnailDir.exists()) {
         await thumbnailDir.create(recursive: true);
      }

      final filename = '$uniqueId.png'; // Use unique ID for filename
      final file = File('${thumbnailDir.path}/$filename');
      await file.writeAsBytes(buffer);

      // Verify file existence and size immediately after writing
      if (await file.exists()) {
        final fileSize = await file.length();
        if (fileSize > 0) {
          return file.path; // Success
        } else {
          await file.delete(); // Delete empty file
          return null;
        }
      } else {
        return null;
      }
    } catch (e, s) {
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
        : DateTime.now(); // Consider defaulting to 'date' if createdAt is missing?

    // Process elements
    List<DrawingElement> elements = [];
    if (entryMap['elements'] != null && entryMap['elements'] is List) {
       final List<dynamic> elementMaps = entryMap['elements'];
       int elementIndex = 0;
      for (var elementMapJson in elementMaps) {
         // Ensure elementMapJson is a Map<String, dynamic>
         if (elementMapJson is! Map<String, dynamic>) {
            elementIndex++;
            continue;
         }
         Map<String, dynamic> elementMap = elementMapJson;

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
              if (element == null) {
              }
              break;

            case 'video':
              // For videos, we need to create a video controller
              element = await _recreateVideoElement(elementMap);
               if (element == null) {
              }
              break;

            case 'gif':
              // For GIFs, we need to reconstruct the element with the URLs
              element = _recreateGifElement(elementMap);
               if (element == null) {
              }
              break;

            case 'note':
              // For notes, we need to reconstruct the note element
              element = NoteElement.fromMap(elementMap);
              break;

            default:
              break;
          }

          // Add the element if successfully created
          if (element != null) {
            elements.add(element);
          }
        } catch (e, s) {
          // Continue parsing other elements
        }
        elementIndex++;
      }
    } else {
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
    final String elementId = map['id'] ?? 'unknown_image';
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

      if (imagePath != null && imagePath.isNotEmpty) {
        File imageFile = File(imagePath);
        if (await imageFile.exists()) {
          Uint8List bytes = await imageFile.readAsBytes();
          if (bytes.isEmpty) {
             return null;
          }
          final codec = await ui.instantiateImageCodec(bytes);
          final frame = await codec.getNextFrame();
          final image = frame.image;

          // Create and return the ImageElement
          return ImageElement(
            id: map['id'],
            position: position,
            isSelected: map['isSelected'] ?? false,
            image: image, // The actual ui.Image object
            size: size,
            imagePath: imagePath, // Store the path too
            rotation: map['rotation'] ?? 0.0, // Load rotation
            // Load brightness and contrast using the correct parameters (added in next step)
            brightness: map['brightness'] ?? 0.0,
            contrast: map['contrast'] ?? 0.0,
          );
        } else {
        }
      } else {
      }

      // If we can't load the image, return null
      return null;
    } catch (e, s) {
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
