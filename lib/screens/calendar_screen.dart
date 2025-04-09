// lib/screens/calendar_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'dart:math' as math;
import 'dart:async';
import 'package:visibility_detector/visibility_detector.dart';

import '../providers/calendar_provider.dart';
import '../providers/drawing_provider.dart';
import '../models/calendar_entry.dart';
import '../models/element.dart';
import '../models/note_element.dart';
import '../models/image_element.dart';
import '../models/pen_element.dart';
import '../models/text_element.dart';
import '../models/gif_element.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _currentDate = DateTime.now();
  late List<DateTime> _monthsList;
  
  // Number of grid columns
  final int _gridColumns = 3;
  
  // Number of months to generate into the future
  final int _futureMonths = 120; // e.g., 10 years
  
  // Size constants for the vertical scrolling layout
  final double _monthHeaderHeight = 40.0;
  
  // For tracking visible month in app bar
  final ScrollController _scrollController = ScrollController();
  String _visibleMonthTitle = '';
  int _currentVisibleMonthIndex = 0;
  
  // Debounce timer for title updates
  Timer? _titleUpdateTimer;
  
  // Flag to track if we're currently in a title change cooldown period
  bool _titleChangeCooldown = false;
  
  // Set to keep track of currently visible header indices
  final Set<int> _visibleHeaderIndices = {};
  
  @override
  void initState() {
    super.initState();
    
    // Initialize months list with current month in the middle
    _initializeMonthsList();
    
    // Load saved entries when screen is first shown
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final calendarProvider = Provider.of<CalendarProvider>(context, listen: false);
      calendarProvider.loadEntriesFromDisk();
      
      // Set initial title - should be the first month in the list
      // No delay needed here as the list is now fixed from the start
      _updateVisibleMonth(0, force: true); 
      
      // Removed delayed update logic
    });
  }
  
  @override
  void dispose() {
    _titleUpdateTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }
  
  void _updateVisibleMonth(int monthIndex, {bool force = false}) {
    // Skip update if in cooldown unless forced
    if (_titleChangeCooldown && !force && monthIndex == _currentVisibleMonthIndex) return;
    
    if (monthIndex >= 0 && monthIndex < _monthsList.length) {
      final DateTime month = _monthsList[monthIndex];
      final newTitle = '${DateFormat.MMMM().format(month).toLowerCase()} ${month.year}';
      
      // Log when the update function is called *because a new month passed*
      print('>>> $newTitle PASSED - Triggering title update');
      
      // Cancel any pending updates
      _titleUpdateTimer?.cancel();
      
      // Schedule update with a short delay to prevent rapid changes
      _titleUpdateTimer = Timer(const Duration(milliseconds: 150), () {
        if (mounted) {
          // Verify that the index is still the best match before updating
          // This helps prevent unnecessary updates during rapid scrolling
          setState(() {
            // Format month name in lowercase for consistent style
            _visibleMonthTitle = '${DateFormat.MMMM().format(month).toLowerCase()} ${month.year}';
            _currentVisibleMonthIndex = monthIndex;
            
            // Set cooldown flag to prevent rapid changes
            _titleChangeCooldown = true;
            
            // Clear cooldown after a delay
            // Using a longer cooldown helps prevent title flickering
            Timer(const Duration(milliseconds: 500), () {
              if (mounted) {
                setState(() {
                  _titleChangeCooldown = false;
                });
              }
            });
          });
        }
      });
    }
  }
  
  void _initializeMonthsList() {
    _monthsList = [];
    final currentMonth = DateTime(_currentDate.year, _currentDate.month);
    
    // Add current month
    _monthsList.add(currentMonth);
    
    // Add future months
    for (int i = 1; i <= _futureMonths; i++) {
      _monthsList.add(_addMonths(currentMonth, i));
    }
    // Removed past month generation
  }
  
  DateTime _addMonths(DateTime date, int months) {
    var newMonth = date.month + months;
    var newYear = date.year + (newMonth > 12 ? (newMonth - 1) ~/ 12 : 0);
    newMonth = ((newMonth - 1) % 12) + 1;
    return DateTime(newYear, newMonth);
  }

  // Helper to get all days in the selected month with canvas data
  List<Map<String, dynamic>> _getDaysInMonth(int year, int month) {
    final calendarProvider = Provider.of<CalendarProvider>(context, listen: false);
    
    // Ensure month value is valid (1-12)
    if (month < 1 || month > 12) {
      // Adjust year and month if out of bounds
      if (month < 1) {
        year--;
        month = 12;
      } else if (month > 12) {
        year++;
        month = 1;
      }
    }
    
    final int daysInMonth = DateTime(year, month + 1, 0).day;
    
    // Get dates with entries for the current month
    final List<CalendarEntry> monthEntries = calendarProvider.getEntriesForMonth(year, month);
    
    List<Map<String, dynamic>> days = [];
    
    // Add days of current month
    for (int i = 1; i <= daysInMonth; i++) {
      final DateTime currentDate = DateTime(year, month, i);
      
      // Find entry for this date (if any)
      CalendarEntry? entry;
      final entriesForDay = calendarProvider.getEntriesForDate(currentDate);
      if (entriesForDay.isNotEmpty) {
        // Take only the first entry per day
        entry = entriesForDay.first;
      }
      
      days.add({
        'day': i,
        'date': currentDate,
        'entry': entry,
        'isToday': currentDate.year == DateTime.now().year && 
                   currentDate.month == DateTime.now().month && 
                   currentDate.day == DateTime.now().day,
      });
    }
    
    return days;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (Widget child, Animation<double> animation) {
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0.0, 0.5),
                  end: Offset.zero,
                ).animate(CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeInOut,
                )),
                child: child,
              ),
            );
          },
          child: Text(
            _visibleMonthTitle.isEmpty ? 'calendar' : _visibleMonthTitle,
            key: ValueKey<String>(_visibleMonthTitle),
            style: const TextStyle(
              color: Colors.black87,
              fontSize: 24,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black54),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Consumer<CalendarProvider>(
        builder: (context, calendarProvider, child) {
          return _buildMonthList();
        },
      ),
    );
  }
  
  Widget _buildMonthList() {
    return ListView.builder(
      controller: _scrollController,
      itemCount: _monthsList.length,
      itemBuilder: (context, monthIndex) {
        final yearMonth = _monthsList[monthIndex];
        final year = yearMonth.year;
        final month = yearMonth.month;
        final days = _getDaysInMonth(year, month);
        
        // Add padding between months for visual separation
        return Container(
          margin: const EdgeInsets.only(bottom: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Month header wrapped in VisibilityDetector
              VisibilityDetector(
                key: ValueKey('vis_header_$monthIndex'), // Unique key for the detector
                onVisibilityChanged: (info) => _onHeaderVisibilityChanged(monthIndex, info),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
                  width: double.infinity,
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        offset: const Offset(0, 1),
                        blurRadius: 2,
                      ),
                    ],
                  ),
                  child: Text(
                    '${DateFormat.MMMM().format(DateTime(year, month)).toLowerCase()} $year',
                    style: const TextStyle(
                      color: Colors.black87,
                      fontSize: 20,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              // Days grid
              GridView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 8.0),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: _gridColumns,
                  childAspectRatio: 0.65,
                  crossAxisSpacing: 4.0,
                  mainAxisSpacing: 4.0,
                ),
                itemCount: days.length,
                itemBuilder: (context, dayIndex) {
                  final day = days[dayIndex];
                  final bool isToday = day['isToday'] ?? false;
                  
                  return _buildDayCell(context, day, isToday);
                },
              ),
            ],
          ),
        );
      },
    );
  }
  
  Widget _buildDayCell(BuildContext context, Map<String, dynamic> dayData, bool isToday) {
    final day = dayData['day'];
    final date = dayData['date'] as DateTime;
    final entry = dayData['entry'] as CalendarEntry?;
    
    return GestureDetector(
      onTap: () => _handleDayTap(date, entry),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade200),
          color: Colors.white,
        ),
        padding: const EdgeInsets.all(1.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Day number and weekday
            Padding(
              padding: const EdgeInsets.only(left: 8.0, top: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    day.toString(),
                    style: TextStyle(
                      fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                      fontSize: 18,
                      color: isToday ? Colors.black : Colors.black87,
                    ),
                  ),
                  Text(
                    DateFormat('EEE').format(date).toLowerCase(),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.black54,
                      fontWeight: isToday ? FontWeight.w500 : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
            
            // Canvas thumbnail or empty space
            Expanded(
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.all(1.0),
                child: entry != null 
                    ? _buildThumbnail(context, entry) 
                    : Container(),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildThumbnail(BuildContext context, CalendarEntry entry) {
    // Check if thumbnail file exists
    bool thumbnailExists = false;
    File? thumbnailFile;

    if (entry.thumbnailPath != null && entry.thumbnailPath!.isNotEmpty) {
      thumbnailFile = File(entry.thumbnailPath!);
      try {
        thumbnailExists = thumbnailFile.existsSync();
      } catch (e) {
         thumbnailExists = false;
      }
    }

    return ClipRect(
                child: (thumbnailFile != null && thumbnailExists)
                    ? Image.file(
              thumbnailFile,
              key: ValueKey(entry.thumbnailPath),
              fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return _buildThumbnailFallback(context, entry, error.toString());
                        },
                      )
          : _buildThumbnailFallback(context, entry, 'No thumbnail'),
    );
  }

  Widget _buildThumbnailFallback(BuildContext context, CalendarEntry entry, String reason) {
    return Container(
      color: Colors.grey[100],
    );
  }

  void _handleDayTap(DateTime date, CalendarEntry? existingEntry) {
    final calendarProvider = Provider.of<CalendarProvider>(context, listen: false);
    final drawingProvider = Provider.of<DrawingProvider>(context, listen: false);
    
    // Select this date
    calendarProvider.selectDate(date);
    
    if (existingEntry != null) {
      // Open existing canvas
      calendarProvider.loadDrawing(existingEntry.id, drawingProvider);
    } else {
      // Create new canvas
    drawingProvider.elements = [];
    drawingProvider.currentElement = null;
    drawingProvider.setTool(ElementType.select);
    }
    
    // Navigate back to drawing screen
    Navigator.of(context).pop();
  }

  // New method to handle visibility changes from VisibilityDetector
  void _onHeaderVisibilityChanged(int monthIndex, VisibilityInfo info) {
    if (info.visibleFraction > 0) {
      // Header is at least partially visible, add it to the set
      _visibleHeaderIndices.add(monthIndex);
    } else {
      // Header is no longer visible, remove it from the set
      _visibleHeaderIndices.remove(monthIndex);
    }

    // Determine the top-most visible header
    int? topVisibleIndex;
    if (_visibleHeaderIndices.isNotEmpty) {
      // Find the minimum index in the set (this corresponds to the highest header)
      topVisibleIndex = _visibleHeaderIndices.reduce(math.min);
    }

    // Update the title if the top-most visible header has changed
    if (topVisibleIndex != null && topVisibleIndex != _currentVisibleMonthIndex) {
      print('VisibilityDetector: Top visible header changed to index $topVisibleIndex. Triggering update.');
      // Use force: true if we want immediate updates, or rely on existing debounce
      _updateVisibleMonth(topVisibleIndex); 
    }
  }
}