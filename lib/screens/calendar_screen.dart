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
                      // Get the number of entries for this date
                      final entryCount = calendarProvider.getEntryCountForDate(date);
                      
                      return Positioned(
                        right: 1,
                        bottom: 1,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.blue,
                            border: Border.all(color: Colors.white, width: 1.0),
                          ),
                          child: Center(
                            child: Text(
                              entryCount.toString(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
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
        onPressed: () => _createNewCanvas(context),
        tooltip: 'Create New Canvas',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildEntriesList(BuildContext context, CalendarProvider calendarProvider) {
    if (_selectedDay == null) {
      return const Center(child: Text('Please select a date'));
    }
    
    final selectedDate = _selectedDay!;
    final entries = calendarProvider.getEntriesForDate(selectedDate);
    
    if (entries.isEmpty) {
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
            '${DateFormat.yMMMMd().format(selectedDate)} - ${entries.length} ${entries.length == 1 ? 'Canvas' : 'Canvases'}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[index];
              return _buildCanvasCard(context, entry);
            },
          ),
        ),
      ],
    );
  }
  
  Widget _buildCanvasCard(BuildContext context, CalendarEntry entry) {
    return Card(
      elevation: 4,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Title bar with canvas name and time
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    entry.title.isEmpty 
                        ? 'Canvas ${DateFormat('h:mm a').format(entry.createdAt)}' 
                        : entry.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(
                  DateFormat('h:mm a').format(entry.createdAt),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600]
                  ),
                ),
              ],
            ),
          ),
          
          // Canvas thumbnail
          if (entry.thumbnailPath != null)
            Container(
              height: 150,
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8.0),
                child: GestureDetector(
                  onTap: () => _openCanvas(context, entry),
                  child: Image.file(
                    File(entry.thumbnailPath!),
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
            
          // Action buttons
          OverflowBar(
            alignment: MainAxisAlignment.end,
            children: [
              // Edit title button
              IconButton(
                icon: const Icon(Icons.edit_note, size: 20),
                onPressed: () => _showEditTitleDialog(context, entry),
                tooltip: 'Edit Title',
              ),
              // Open button
              TextButton.icon(
                icon: const Icon(Icons.edit, size: 16),
                label: const Text('Open'),
                onPressed: () => _openCanvas(context, entry),
              ),
              // Delete button
              TextButton.icon(
                icon: const Icon(Icons.delete, size: 16),
                label: const Text('Delete'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.red,
                ),
                onPressed: () => _confirmDelete(context, entry),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showEditTitleDialog(BuildContext context, CalendarEntry entry) {
    final titleController = TextEditingController(text: entry.title);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Canvas Title'),
        content: TextField(
          controller: titleController,
          decoration: const InputDecoration(
            labelText: 'Canvas Title',
            hintText: 'Enter a title for this canvas',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () {
              final calendarProvider = Provider.of<CalendarProvider>(context, listen: false);
              final drawingProvider = Provider.of<DrawingProvider>(context, listen: false);
              
              // Load the entry and update its title
              calendarProvider.loadDrawing(entry.id, drawingProvider);
              calendarProvider.updateEntry(entry.id, drawingProvider, title: titleController.text);
              
              Navigator.of(context).pop();
            },
            child: const Text('SAVE'),
          ),
        ],
      ),
    );
  }

  void _createNewCanvas(BuildContext context) {
    // Get providers
    final calendarProvider = Provider.of<CalendarProvider>(context, listen: false);
    final drawingProvider = Provider.of<DrawingProvider>(context, listen: false);
    
    // If a date is selected, use that, otherwise use today
    final selectedDate = _selectedDay ?? DateTime.now();
    
    // Just select the date without selecting a specific entry
    // This will prepare for creating a new canvas
    calendarProvider.selectDate(selectedDate);
    
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
    calendarProvider.loadDrawing(entry.id, drawingProvider);
    
    // Navigate back to drawing screen
    Navigator.of(context).pop();
  }

  void _confirmDelete(BuildContext context, CalendarEntry entry) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Canvas'),
        content: Text(
          entry.title.isEmpty
            ? 'Are you sure you want to delete this canvas?'
            : 'Are you sure you want to delete "${entry.title}"?'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () {
              final calendarProvider = Provider.of<CalendarProvider>(context, listen: false);
              calendarProvider.deleteEntry(entry.id);
              Navigator.of(context).pop();
            },
            child: const Text('DELETE', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}