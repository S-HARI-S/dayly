import 'dart:convert';
import 'package:flutter/material.dart';
import 'element.dart';
import 'pen_element.dart';
import 'text_element.dart';
import 'image_element.dart';
import 'video_element.dart';

class CalendarEntry {
  final DateTime date;
  final String id;
  final String title; // Add a title for each canvas
  final List<DrawingElement> elements;
  final String? thumbnailPath; // Path to stored thumbnail image
  final DateTime createdAt; // When this canvas was created

  CalendarEntry({
    required this.date,
    String? id,
    this.title = '', // Default empty title
    required this.elements,
    this.thumbnailPath,
    DateTime? createdAt,
  }) : 
    id = id ?? DateTime.now().microsecondsSinceEpoch.toString(),
    createdAt = createdAt ?? DateTime.now();

  // Check if this entry matches a specific date (ignoring time)
  bool matchesDate(DateTime other) {
    return date.year == other.year && 
           date.month == other.month && 
           date.day == other.day;
  }

  // Create copy with updated fields
  CalendarEntry copyWith({
    DateTime? date,
    String? id,
    String? title,
    List<DrawingElement>? elements,
    String? thumbnailPath,
    DateTime? createdAt,
  }) {
    return CalendarEntry(
      date: date ?? this.date,
      id: id ?? this.id,
      title: title ?? this.title,
      elements: elements ?? this.elements,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  // Serialization methods
  Map<String, dynamic> toMap() {
    return {
      'date': date.toIso8601String(),
      'id': id,
      'title': title,
      'thumbnailPath': thumbnailPath,
      'createdAt': createdAt.toIso8601String(),
      'elements': elements.map((element) {
        final Map<String, dynamic> elementMap = element.toMap();
        // Add type information for proper deserialization
        elementMap['elementType'] = element.type.toString().split('.').last;
        return elementMap;
      }).toList(),
    };
  }

  String toJson() => json.encode(toMap());

  factory CalendarEntry.fromMap(Map<String, dynamic> map) {
    List<DrawingElement> parsedElements = [];
    
    if (map['elements'] != null) {
      final List<dynamic> elementMaps = map['elements'];
      for (var elementMap in elementMaps) {
        final String elementType = elementMap['elementType'] ?? 'unknown';
        
        // Create the appropriate element type
        try {
          switch (elementType) {
            case 'pen':
              parsedElements.add(PenElement.fromMap(elementMap));
              break;
            case 'text':
              parsedElements.add(TextElement.fromMap(elementMap));
              break;
            case 'image':
              parsedElements.add(ImageElement.fromMap(elementMap));
              break;
            case 'video':
              parsedElements.add(VideoElement.fromMap(elementMap));
              break;
            default:
              print('Unknown element type: $elementType');
              break;
          }
        } catch (e) {
          print('Error parsing element of type $elementType: $e');
        }
      }
    }
    
    return CalendarEntry(
      date: DateTime.parse(map['date']),
      id: map['id'],
      title: map['title'] ?? '',
      elements: parsedElements,
      thumbnailPath: map['thumbnailPath'],
      createdAt: map.containsKey('createdAt') ? DateTime.parse(map['createdAt']) : null,
    );
  }

  factory CalendarEntry.fromJson(String source) => 
      CalendarEntry.fromMap(json.decode(source));
}
