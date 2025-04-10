import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart'; // Import color picker

import '../providers/drawing_provider.dart';
import '../models/element.dart';
import '../models/image_element.dart';
import '../models/text_element.dart';
import '../models/pen_element.dart'; // Import PenElement
import '../models/note_element.dart';
import '../models/video_element.dart';
import '../models/gif_element.dart';

class ContextToolbar extends StatefulWidget {
  final bool isVisible;
  final Function(double)? onHeightChanged;

  const ContextToolbar({
    Key? key,
    required this.isVisible,
    this.onHeightChanged,
  }) : super(key: key);

  @override
  State<ContextToolbar> createState() => _ContextToolbarState();
}

class _ContextToolbarState extends State<ContextToolbar> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  double _height = 0.0;
  final double _toolbarHeight = 60.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _animation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut)
    );
    _animation.addListener(() {
      setState(() {
        _height = _animation.value * _toolbarHeight;
        if (widget.onHeightChanged != null) {
          widget.onHeightChanged!(_height);
        }
      });
    });
    
    // Initialize visibility based on initial prop
    if (widget.isVisible) {
      _controller.value = 1.0;
      _height = _toolbarHeight;
    }
  }
  
  @override
  void didUpdateWidget(ContextToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible != oldWidget.isVisible) {
      if (widget.isVisible) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isVisible) {
      return const SizedBox.shrink(); 
    }

    return SizedBox(
      height: _toolbarHeight,
      child: Consumer<DrawingProvider>(
        builder: (context, drawingProvider, child) {
          if (!drawingProvider.showContextToolbar || drawingProvider.selectedElementIds.isEmpty) {
            return const SizedBox.shrink();
          }

          // Get the selected elements
          final selectedElements = drawingProvider.elements
              .where((el) => drawingProvider.selectedElementIds.contains(el.id))
              .toList();

          // Build the list of actions - ONLY include delete, bring forward, send backward
          // No rotation or resize buttons as per user request
          List<Widget> actions = [
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete',
              onPressed: drawingProvider.deleteSelected,
            ),
            IconButton(
              icon: const Icon(Icons.flip_to_front_outlined),
              tooltip: 'Bring Forward',
              onPressed: drawingProvider.bringSelectedForward,
            ),
            IconButton(
              icon: const Icon(Icons.flip_to_back_outlined),
              tooltip: 'Send Backward',
              onPressed: drawingProvider.sendSelectedBackward,
            ),
          ];

          // Build the actual toolbar widget
          return Material(
            elevation: 8.0,
            color: Theme.of(context).bottomAppBarTheme.color ?? Theme.of(context).primaryColor.withOpacity(0.1),
            child: Container(
              height: _toolbarHeight,
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: Center(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center, 
                    children: actions,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
