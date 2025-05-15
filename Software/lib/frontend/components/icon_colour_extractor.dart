import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class IconColorExtractor {
  static final Map<String, Color> _colourCache = {};
  static const int MAX_CACHE_SIZE = 50;
  static int _lastCacheClean = 0;

  static Future<Color> extractDominantColor(
      Uint8List iconData, String identifier, // Use path as identifier
      {Color defaultColor = Colors.blue}) async {
    // Check cache first
    if (_colourCache.containsKey(identifier)) {
      return _colourCache[identifier]!;
    }
    _cleanCacheIfNeeded();

    try {
      final codec = await ui.instantiateImageCodec(iconData);
      final frameInfo = await codec.getNextFrame();
      final image = frameInfo.image;
      final resizedCodec = await ui.instantiateImageCodec(
        iconData,
        targetHeight: 32,
        targetWidth: 32,
      );
      final resizedFrameInfo = await resizedCodec.getNextFrame();
      final resizedImage = resizedFrameInfo.image;

      final byteData =
          await resizedImage.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null) {
        return defaultColor;
      }

      final pixels = byteData.buffer.asUint8List();
      final Map<int, int> colourCount = {};

      for (int i = 0; i < pixels.length; i += 16) {
        // Increased step from 4 to 16
        final r = pixels[i];
        final g = pixels[i + 1];
        final b = pixels[i + 2];
        final a = pixels[i + 3];

        if (a < 128) continue;

        final colourKey = (r << 16) | (g << 8) | b;
        colourCount[colourKey] = (colourCount[colourKey] ?? 0) + 1;
      }

      if (colourCount.isEmpty) {
        return defaultColor;
      }

      int dominantColorKey =
          colourCount.entries.reduce((a, b) => a.value > b.value ? a : b).key;

      final r = (dominantColorKey >> 16) & 0xFF;
      final g = (dominantColorKey >> 8) & 0xFF;
      final b = dominantColorKey & 0xFF;

      final dominantColor = Color.fromRGBO(r, g, b, 1.0);

      final HSLColor hslColor = HSLColor.fromColor(dominantColor);
      final adjustedColor = hslColor
          .withLightness(hslColor.lightness < 0.3
              ? 0.4
              : (hslColor.lightness > 0.8 ? 0.7 : hslColor.lightness))
          .withSaturation(hslColor.saturation < 0.4 ? 0.6 : hslColor.saturation)
          .toColor();

      _colourCache[identifier] = adjustedColor;
      return adjustedColor;
    } catch (e) {
      print('Error extracting colour: $e');
      return defaultColor;
    }
  }

  static void _cleanCacheIfNeeded() {
    final currentTime = DateTime.now().millisecondsSinceEpoch;
    if (_colourCache.length > MAX_CACHE_SIZE &&
        currentTime - _lastCacheClean > 30000) {
      final entries = _colourCache.entries.take(MAX_CACHE_SIZE ~/ 2).toList();
      _colourCache.clear();
      _colourCache.addAll(Map.fromEntries(entries));

      _lastCacheClean = currentTime;
    }
  }

  static void clearCache() {
    _colourCache.clear();
    _lastCacheClean = DateTime.now().millisecondsSinceEpoch;
  }

  static int get cacheSize => _colourCache.length;
}
