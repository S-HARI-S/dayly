import 'package:flutter/material.dart';

/// An improved floating action button that positions itself above the bottom toolbar
/// with smooth animation and proper layout handling.
class BottomFloatingButton extends StatelessWidget {
  /// The offset from the bottom of the screen
  final double bottomOffset;
  
  /// Callback when button is pressed
  final VoidCallback onPressed;
  
  /// Child widget to display inside the button
  final Widget child;
  
  /// Optional size for the button
  final double? size;
  
  /// Optional hero tag
  final Object? heroTag;
  
  /// Optional tooltip
  final String? tooltip;

  const BottomFloatingButton({
    Key? key,
    required this.bottomOffset,
    required this.onPressed,
    required this.child,
    this.size,
    this.heroTag,
    this.tooltip,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Calculate safe area (handle notches, rounded corners, etc.)
    final EdgeInsets safeArea = MediaQuery.of(context).padding;
    final double defaultBottomPadding = 16.0;
    final double safePadding = safeArea.bottom > 0 ? safeArea.bottom : defaultBottomPadding;
    
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      right: 16.0,
      bottom: bottomOffset + safePadding + 16.0, // Account for toolbar height, safe area, and padding
      child: SafeArea(
        child: FloatingActionButton(
          onPressed: onPressed,
          tooltip: tooltip,
          heroTag: heroTag,
          elevation: 4.0,
          highlightElevation: 8.0,
          child: child,
        ),
      ),
    );
  }
}
