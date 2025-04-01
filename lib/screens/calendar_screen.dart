// lib/screens/calendar_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';

import '../providers/calendar_provider.dart';
import '../providers/drawing_provider.dart';
import '../models/calendar_entry.dart';
import '../models/element.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  late List<DateTime> _markedDates;

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _markedDates = [];
    
    // Load saved entries when screen is first shown
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final calendarProvider = Provider.of<CalendarProvider>(context, listen: false);
      calendarProvider.loadEntriesFromDisk();
      _updateMarkedDates();
    });
  }
  
  void _updateMarkedDates() {
    final calendarProvider = Provider.of<CalendarProvider>(context, listen: false);
    
    // Get dates with entries for the current view
    final firstDay = DateTime(_focusedDay.year, _focusedDay.month, 1);
    final lastDay = DateTime(_focusedDay.year, _focusedDay.month + 1, 0);
    
    setState(() {
      _markedDates = calendarProvider.getDatesWithEntries(firstDay, lastDay);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendar'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'New Canvas',
            onPressed: () => _createNewCanvas(context),
          ),
        ],
      ),
      body: Consumer<CalendarProvider>(
        builder: (context, calendarProvider, child) {
          // Update marked dates when provider data changes
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _updateMarkedDates();
          });
          
          return Column(
            children: [
              TableCalendar(
                firstDay: DateTime.utc(2020, 1, 1),
                lastDay: DateTime.utc(2030, 12, 31),
                focusedDay: _focusedDay,
                calendarFormat: _calendarFormat,
                selectedDayPredicate: (day) {
                  return isSameDay(_selectedDay, day);
                },
                onDaySelected: (selectedDay, focusedDay) {
                  setState(() {
                    _selectedDay = selectedDay;
                    _focusedDay = focusedDay;
                  });
                  calendarProvider.selectDate(selectedDay);
                },
                onFormatChanged: (format) {
                  setState(() {
                    _calendarFormat = format;
                  });
                },
                onPageChanged: (focusedDay) {
                  setState(() {
                    _focusedDay = focusedDay;
                  });
                  _updateMarkedDates();
                },
                calendarBuilders: CalendarBuilders(
                  markerBuilder: (context, date, events) {
                    // Check if this date has an entry
                    if (_markedDates.any((markedDate) => 
                        markedDate.year == date.year && 
                        markedDate.month == date.month && 
                        markedDate.day == date.day)) {
                      return Positioned(
                        right: 1,
                        bottom: 1,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.blue,
                          ),
                        ),
                      );
                    }
                    return null;
                  },
                ),
                calendarStyle: const CalendarStyle(
                  todayDecoration: BoxDecoration(
                    color: Colors.blue,
                    shape: BoxShape.circle,
                  ),
                  selectedDecoration: BoxDecoration(
                    color: Colors.deepPurple,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _buildEntriesList(context, calendarProvider),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () => _createNewCanvas(context),
        tooltip: 'Create New Canvas',
      ),
    );
  }

  Widget _buildEntriesList(BuildContext context, CalendarProvider calendarProvider) {
    final selectedEntry = calendarProvider.getEntryForDate(_selectedDay ?? DateTime.now());
    
    if (selectedEntry == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('No entries for this date'),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Create New Canvas'),
              onPressed: () => _createNewCanvas(context),
            ),
          ],
        ),
      );
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Text(
            DateFormat.yMMMMd().format(selectedEntry.date),
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        const SizedBox(height: 8),
        if (selectedEntry.thumbnailPath != null)
          Expanded(
            child: Center(
              child: GestureDetector(
                onTap: () => _openCanvas(context, selectedEntry),
                child: Card(
                  elevation: 4,
                  margin: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Image.file(
                          File(selectedEntry.thumbnailPath!),
                          fit: BoxFit.contain,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton.icon(
                              icon: const Icon(Icons.edit, size: 16),
                              label: const Text('Open'),
                              onPressed: () => _openCanvas(context, selectedEntry),
                            ),
                            const SizedBox(width: 8),
                            TextButton.icon(
                              icon: const Icon(Icons.delete, size: 16),
                              label: const Text('Delete'),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.red,
                              ),
                              onPressed: () => _confirmDelete(context, selectedEntry),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )
        else
          Expanded(
            child: Center(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.edit),
                label: const Text('Open Canvas'),
                onPressed: () => _openCanvas(context, selectedEntry),
              ),
            ),
          ),
      ],
    );
  }

  void _createNewCanvas(BuildContext context) {
    // Get providers
    final calendarProvider = Provider.of<CalendarProvider>(context, listen: false);
    final drawingProvider = Provider.of<DrawingProvider>(context, listen: false);
    
    // Select today's date
    final today = DateTime.now();
    calendarProvider.selectDate(today);
    
    // Clear current drawing and reset tools
    drawingProvider.elements = [];
    drawingProvider.currentElement = null;
    drawingProvider.setTool(ElementType.select);
    
    // Navigate to drawing screen
    Navigator.of(context).pop(); // Assuming this takes us back to main screen with canvas
  }

  void _openCanvas(BuildContext context, CalendarEntry entry) {
    // Get providers
    final calendarProvider = Provider.of<CalendarProvider>(context, listen: false);
    final drawingProvider = Provider.of<DrawingProvider>(context, listen: false);
    
    // Load this entry's elements into drawing provider
    calendarProvider.loadDrawing(entry.date, drawingProvider);
    
    // Navigate back to drawing screen
    Navigator.of(context).pop();
  }

  void _confirmDelete(BuildContext context, CalendarEntry entry) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Entry'),
        content: Text('Are you sure you want to delete the entry for ${DateFormat.yMMMMd().format(entry.date)}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () {
              final calendarProvider = Provider.of<CalendarProvider>(context, listen: false);
              calendarProvider.clearEntry(entry.date);
              Navigator.of(context).pop();
            },
            child: const Text('DELETE', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}