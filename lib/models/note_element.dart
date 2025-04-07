// lib/models/note_element.dart

import 'dart:ui' as ui;
import 'package:flutter/material.dart';
// Make sure this path is correct for your project structure
import 'element.dart';
import 'dart:math' as math;

// --- REMOVED NoteAspectRatio enum ---

class NoteElement extends DrawingElement {
  static const double MIN_WIDTH = 100.0;
  static const double MIN_HEIGHT = 80.0;
  static const double MAX_WIDTH = 800.0; // Allow wider notes
  static const double MIN_FONT_SIZE = 8.0;
  static const double MAX_FONT_SIZE = 100.0;

  final String? title;
  final String? content;
  final Color backgroundColor;
  final bool isPinned;
  final Size size; // Width and Height are now independent (except during proportional resize)
  final double fontSize;

  NoteElement({
    super.id,
    required super.position,
    required this.size,
    super.isSelected,
    super.rotation,
    this.title,
    this.content,
    this.backgroundColor = const Color(0xFFFFFA99), // Default yellow
    this.isPinned = false,
    this.fontSize = 16.0, // Default font size
    // --- REMOVED aspectRatioType ---
  }) : super(
          type: ElementType.note,
        );

  @override
  Rect get bounds => Rect.fromLTWH(position.dx, position.dy, size.width, size.height);

  // --- REVISED STATIC METHOD ---
  // Calculates required height for given content constrained by a specific targetWidth.
  static Size calculateSizeForContent(
    String? title,
    String? content,
    double fontSize, {
    required double targetWidth, // Width is now the primary constraint
    double minHeight = MIN_HEIGHT, // Keep minHeight constraint
    // Removed aspectRatioType parameter
  }) {
    // Clamp targetWidth - Resizing logic should also handle this
    final clampedTargetWidth = targetWidth.clamp(MIN_WIDTH, MAX_WIDTH);

    // Padding values
    const double horizontalPadding = 16.0; // 8px on each side
    const double verticalPadding = 16.0;   // 8px top/bottom
    const double titleBottomSpacing = 4.0;

    // Available width for text layout *inside* the padding
    final double layoutWidth = math.max(0, clampedTargetWidth - horizontalPadding); // Ensure non-negative

    // Text Painters
    final TextPainter titlePainter = TextPainter(textDirection: ui.TextDirection.ltr);
    final TextPainter contentPainter = TextPainter(textDirection: ui.TextDirection.ltr);

    double requiredHeight = verticalPadding; // Start with top/bottom padding

    // Calculate height based on the layoutWidth derived from targetWidth
    final clampedFontSize = fontSize.clamp(MIN_FONT_SIZE, MAX_FONT_SIZE);
    final contentFontSize = (clampedFontSize - 2).clamp(MIN_FONT_SIZE, MAX_FONT_SIZE);

    if (title != null && title.isNotEmpty) {
      titlePainter.text = TextSpan(
        text: title,
        style: TextStyle(fontSize: clampedFontSize, fontWeight: FontWeight.bold, color: Colors.black87),
      );
      titlePainter.layout(maxWidth: layoutWidth); // Layout constrained by width
      requiredHeight += titlePainter.height;
      if (content != null && content.isNotEmpty) {
        requiredHeight += titleBottomSpacing;
      }
    }
    if (content != null && content.isNotEmpty) {
      contentPainter.text = TextSpan(
        text: content,
        style: TextStyle(fontSize: contentFontSize, color: Colors.black87),
      );
      contentPainter.layout(maxWidth: layoutWidth); // Layout constrained by width
      requiredHeight += contentPainter.height;
    }

    // Ensure the final height meets the minimum requirement
    double finalHeight = math.max(minHeight, requiredHeight);

    // Return the size with the target width and calculated/minimum height
    return Size(clampedTargetWidth, finalHeight);
  }
  // --- END OF REVISED METHOD ---

  @override
  bool containsPoint(Offset point) => bounds.contains(point);

  @override
  void render(Canvas canvas, {double inverseScale = 1.0}) {
    final rect = bounds;

    applyRotation(canvas, rect, () {
      // Draw the note background
      final Paint backgroundPaint = Paint()..color = backgroundColor;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(8.0)),
        backgroundPaint
      );

      // Add a subtle shadow effect
      final Paint shadowPaint = Paint()
        ..color = Colors.black.withOpacity(0.2)
        ..maskFilter = MaskFilter.blur(BlurStyle.outer, 3.0 * inverseScale) // Soften shadow
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5 * inverseScale; // Thinner shadow line
      // Draw slightly offset for better effect
      canvas.drawRRect(
         RRect.fromRectAndRadius(rect.shift(Offset(1.0 * inverseScale, 1.5*inverseScale)), const Radius.circular(8.0)),
         shadowPaint
      );

      // Draw pin icon if note is pinned
      if (isPinned) {
        final pinSize = 16.0 * inverseScale;
        final pinRect = Rect.fromLTWH(
          rect.right - pinSize - (4.0 * inverseScale),
          rect.top + (4.0 * inverseScale),
          pinSize,
          pinSize
        );
        final pinPaint = Paint()..color = Colors.red.shade700;
        // Simple pin representation
         canvas.drawCircle(
            Offset(pinRect.center.dx, pinRect.top + pinSize * 0.3), // Head
            pinSize * 0.3,
            pinPaint);
         canvas.drawLine( // Stem
            Offset(pinRect.center.dx, pinRect.top + pinSize * 0.5),
            Offset(pinRect.center.dx, pinRect.bottom - pinSize * 0.1),
            pinPaint..strokeWidth = pinSize * 0.15..strokeCap = StrokeCap.round);

      }

      // Draw the text content
      final TextPainter textPainter = TextPainter(
        textDirection: ui.TextDirection.ltr,
        textAlign: TextAlign.left,
      );
      const double paddingX = 8.0;
      const double paddingY = 8.0;
      const double titleBottomSpacing = 4.0;
      final availableWidth = math.max(0, rect.width - (paddingX * 2)); // Ensure non-negative
      double contentTopOffset = paddingY;

      // Use the element's font size, clamped
      final scaledFontSize = fontSize.clamp(MIN_FONT_SIZE, MAX_FONT_SIZE);
      final contentScaledFontSize = (fontSize - 2).clamp(MIN_FONT_SIZE, MAX_FONT_SIZE);


      // Title text
      if (title != null && title!.isNotEmpty && availableWidth > 0) {
        textPainter.text = TextSpan(
          text: title,
          style: TextStyle(
            fontSize: scaledFontSize,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        );
        textPainter.layout(maxWidth: availableWidth.toDouble());
        textPainter.paint(
          canvas,
          Offset(rect.left + paddingX, rect.top + contentTopOffset)
        );
        contentTopOffset += textPainter.height;
        if (content != null && content!.isNotEmpty) {
          contentTopOffset += titleBottomSpacing;
        }
      }

      // Content text
      if (content != null && content!.isNotEmpty && availableWidth > 0) {
        textPainter.text = TextSpan(
          text: content,
          style: TextStyle(
            fontSize: contentScaledFontSize,
            color: Colors.black87,
          ),
        );
        // Layout with available width, but clip drawing below
        textPainter.layout(maxWidth: availableWidth.toDouble());
        final maxHeight = math.max(0, rect.height - contentTopOffset - paddingY); // Ensure non-negative
        if (maxHeight > 0) {
            canvas.save();
            // Clip the content drawing area to prevent overflow
            canvas.clipRect(Rect.fromLTWH(
              rect.left + paddingX,
              rect.top + contentTopOffset,
              availableWidth.toDouble(),
              maxHeight.toDouble()
            ));
            textPainter.paint(
              canvas,
              Offset(rect.left + paddingX, rect.top + contentTopOffset)
            );
            canvas.restore();
        }
      }
    });
  }

  @override
  NoteElement copyWith({
    String? id,
    Offset? position,
    bool? isSelected,
    Size? size,
    double? rotation,
    String? title,
    String? content,
    Color? backgroundColor,
    bool? isPinned,
    double? fontSize,
    // --- REMOVED aspectRatioType ---
  }) {
    return NoteElement(
      id: id ?? this.id,
      position: position ?? this.position,
      isSelected: isSelected ?? this.isSelected,
      size: size ?? this.size,
      rotation: rotation ?? this.rotation,
      title: title ?? this.title,
      content: content ?? this.content,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      isPinned: isPinned ?? this.isPinned,
      fontSize: fontSize ?? this.fontSize,
      // --- REMOVED aspectRatioType ---
    );
  }

  @override
  NoteElement clone() {
    return NoteElement(
      id: id,
      position: position,
      isSelected: false, // Clones are not selected by default
      size: size,
      rotation: rotation,
      title: title,
      content: content,
      backgroundColor: backgroundColor,
      isPinned: isPinned,
      fontSize: fontSize,
      // --- REMOVED aspectRatioType ---
    );
  }

  @override
  Map<String, dynamic> toMap() {
    return {
      'elementType': 'note',
      'id': id,
      'position': {'dx': position.dx, 'dy': position.dy},
      'isSelected': isSelected,
      'size': {'width': size.width, 'height': size.height},
      'rotation': rotation,
      'title': title,
      'content': content,
      'backgroundColor': backgroundColor.value,
      'isPinned': isPinned,
      'fontSize': fontSize,
      // --- REMOVED aspectRatioType ---
    };
  }

  static NoteElement fromMap(Map<String, dynamic> map) {
    final posMap = map['position'] as Map<String, dynamic>? ?? {};
    final position = Offset(
      posMap['dx'] as double? ?? 0.0,
      posMap['dy'] as double? ?? 0.0
    );

    final sizeMap = map['size'] as Map<String, dynamic>? ?? {};
    final size = Size(
      sizeMap['width'] as double? ?? MIN_WIDTH,
      sizeMap['height'] as double? ?? MIN_HEIGHT
    );

    // --- REMOVED aspectRatioType loading ---

    return NoteElement(
      id: map['id'] as String? ?? '',
      position: position,
      size: size,
      isSelected: map['isSelected'] as bool? ?? false,
      rotation: map['rotation'] as double? ?? 0.0,
      title: map['title'] as String?,
      content: map['content'] as String?,
      backgroundColor: Color(map['backgroundColor'] as int? ?? 0xFFFFFA99),
      isPinned: map['isPinned'] as bool? ?? false,
      fontSize: map['fontSize'] as double? ?? 16.0,
      // --- REMOVED aspectRatioType ---
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      super == other &&
          other is NoteElement &&
          runtimeType == other.runtimeType &&
          title == other.title &&
          content == other.content &&
          backgroundColor == other.backgroundColor &&
          isPinned == other.isPinned &&
          size == other.size &&
          fontSize == other.fontSize;


  @override
  int get hashCode =>
      super.hashCode ^
      title.hashCode ^
      content.hashCode ^
      backgroundColor.hashCode ^
      isPinned.hashCode ^
      size.hashCode ^
      fontSize.hashCode;
}