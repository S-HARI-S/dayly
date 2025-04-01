// lib/models/video_element.dart
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'dart:ui' as ui;
import 'element.dart';
import 'dart:async';

class VideoElement extends DrawingElement {
  final String videoUrl;
  final VideoPlayerController controller;
  final Size size;
  final ValueNotifier<bool> _showPlayIconNotifier;
  // FIX: Remove StreamSubscription variable - addListener doesn't return one
  // StreamSubscription? _controllerListenerSubscription;

  VideoElement({
    String? id,
    required Offset position,
    bool isSelected = false,
    required this.videoUrl,
    required this.controller,
    required this.size,
  }) : _showPlayIconNotifier = ValueNotifier(!controller.value.isPlaying),
       super(id: id, type: ElementType.video, position: position, isSelected: isSelected) {
    // FIX: Just add the listener, don't assign the result
    controller.addListener(_onVideoStateChanged);
    _onVideoStateChanged(); // Update initial state
  }

  void _onVideoStateChanged() {
    final shouldShowPlay = !controller.value.isPlaying;
    if (_showPlayIconNotifier.value != shouldShowPlay) {
      _showPlayIconNotifier.value = shouldShowPlay;
    }
  }

  void togglePlayPause() { /* ... (Keep as before) ... */ if(controller.value.isPlaying){controller.pause();}else{if(controller.value.isInitialized){controller.play(); controller.setLooping(true);}else{print("Vid not init");}} }

  void dispose() {
     print("Disposing VideoElement ${id}");
     // FIX: Use removeListener, not cancel subscription
     controller.removeListener(_onVideoStateChanged);
     controller.dispose();
     _showPlayIconNotifier.dispose();
  }

  @override
  Rect get bounds => Rect.fromLTWH(position.dx, position.dy, size.width, size.height);
  @override
  bool containsPoint(Offset point) => bounds.contains(point);
  @override
  void render(Canvas canvas, {double inverseScale = 1.0}) { /* ... (Keep placeholder rendering as before) ... */ final dst=bounds; final ph=Paint()..color=Colors.black87; canvas.drawRect(dst,ph); final iconC=Colors.white.withOpacity(0.9); final iconP=Paint()..color=iconC; final iconS=(size.shortestSide*0.3).clamp(15.0,60.0); final iconR=Rect.fromCenter(center:dst.center, width:iconS, height:iconS); if(_showPlayIconNotifier.value){final p=Path()..moveTo(iconR.left,iconR.top)..lineTo(iconR.right,iconR.center.dy)..lineTo(iconR.left,iconR.bottom)..close(); canvas.drawPath(p,iconP);}else{final bw=iconS*0.25; final g=iconS*0.1; final lb=Rect.fromLTWH(iconR.center.dx-bw-g/2,iconR.top,bw,iconR.height); final rb=Rect.fromLTWH(iconR.center.dx+g/2,iconR.top,bw,iconR.height); canvas.drawRect(lb,iconP); canvas.drawRect(rb,iconP);} }

  // FIX: Ensure Size? size is included in override
  @override
  VideoElement copyWith({
    String? id,
    Offset? position,
    bool? isSelected,
    Size? size, // Added from base class override
    // Video specific - not changeable via copyWith easily
    String? videoUrl,
    VideoPlayerController? controller,
  }) {
    assert(videoUrl == null && controller == null, "Cannot change video source or controller via copyWith.");
    return VideoElement(
      id: id ?? this.id, position: position ?? this.position, isSelected: isSelected ?? this.isSelected,
      videoUrl: this.videoUrl, controller: this.controller, // Share controller reference
      size: size ?? this.size, // Use new size if provided
    );
  }

  @override
  VideoElement clone() { /* ... (Keep as before - shares controller) ... */ print("Warn: Cloning VideoElement shares controller"); return VideoElement(id: id, position: position, isSelected: false, videoUrl: videoUrl, controller: controller, size: size,); }
}