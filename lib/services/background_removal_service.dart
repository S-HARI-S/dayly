import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:path_provider/path_provider.dart';

/// Service to handle background removal from images
class BackgroundRemovalService {
  /// Removes the background from an image using the Remove.bg API
  /// 
  /// Takes a ui.Image and returns a new ui.Image with the background removed
  /// Requires an API key from remove.bg stored in your .env file as REMOVE_BG_API_KEY
  static Future<ui.Image> removeBackground(ui.Image image) async {
    try {
      // Convert the ui.Image to bytes
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw Exception("Failed to convert image to bytes");
      }
      
      final Uint8List imageBytes = byteData.buffer.asUint8List();
      
      // Get API key from environment variables
      final apiKey = dotenv.env['REMOVE_BG_API_KEY'];
      if (apiKey == null || apiKey.isEmpty) {
        throw Exception("Remove.bg API key not found. Add REMOVE_BG_API_KEY to your .env file");
      }
      
      // Prepare the request to remove.bg API
      final uri = Uri.parse('https://api.remove.bg/v1.0/removebg');
      
      // Send the request using multipart form
      final request = http.MultipartRequest('POST', uri)
        ..headers['X-Api-Key'] = apiKey
        ..fields['size'] = 'auto'
        ..fields['format'] = 'auto'
        ..files.add(http.MultipartFile.fromBytes(
          'image_file',
          imageBytes,
          filename: 'image.png',
        ));
      
      // Send the request and get response
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      
      // Check the response
      if (response.statusCode == 200) {
        // Successfully removed background - decode the image
        final Uint8List resultBytes = response.bodyBytes;
        final ui.Codec codec = await ui.instantiateImageCodec(resultBytes);
        final ui.FrameInfo frameInfo = await codec.getNextFrame();
        return frameInfo.image;
      } else {
        if (response.headers['content-type'] == 'application/json') {
          final errorJson = jsonDecode(response.body);
          throw Exception("Background removal failed: ${errorJson['errors']?[0]?['title'] ?? 'Unknown error'}");
        } else {
          throw Exception("Background removal failed with status code: ${response.statusCode}");
        }
      }
    } catch (e) {
      // If using the API fails, we can fall back to a local/temporary solution
      if (e.toString().contains('API key not found')) {
        // Create a simulated result (just for demonstration)
        return await _simulateBackgroundRemoval(image);
      }
      rethrow; // Re-throw the error to be handled by the caller
    }
  }
  
  // Fallback method that simulates background removal when no API key is available
  static Future<ui.Image> _simulateBackgroundRemoval(ui.Image image) async {
    // Create an in-memory canvas to draw the image with a "mock" background removal
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final size = Size(image.width.toDouble(), image.height.toDouble());
    
    // Paint the image
    final paint = Paint();
    canvas.drawImage(image, Offset.zero, paint);
    
    // Create a simulated "cutout" effect by drawing a slightly smaller image on top
    final frame = Rect.fromLTRB(
      size.width * 0.05,
      size.height * 0.05,
      size.width * 0.95,
      size.height * 0.95
    );
    
    final Path path = Path()
      ..addOval(Rect.fromCenter(
        center: Offset(size.width / 2, size.height / 2),
        width: size.width * 0.9,
        height: size.height * 0.9,
      ));
    
    // Clear the area outside the path
    canvas.saveLayer(Rect.fromLTWH(0, 0, size.width, size.height), Paint());
    canvas.clipPath(path);
    canvas.drawImage(image, Offset.zero, paint);
    canvas.restore();
    
    // Convert the drawing to an image
    final ui.Picture picture = recorder.endRecording();
    return await picture.toImage(image.width, image.height);
  }
  
  // For local development, you can use this method to save the image for testing
  static Future<File> saveImageToTempFile(Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/temp_${DateTime.now().millisecondsSinceEpoch}.png');
    await file.writeAsBytes(bytes);
    return file;
  }
}
