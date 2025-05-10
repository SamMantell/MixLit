import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class IconColorExtractor {
  static final Map<String, Color> _colourCache = {};

  static Future<Color> extractDominantColor(
      Uint8List iconData, String identifier, // Use path as identifier
      {Color defaultColor = Colors.blue}) async {
    if (_colourCache.containsKey(identifier)) {
      return _colourCache[identifier]!;
    }

    try {
      final codec = await ui.instantiateImageCodec(iconData);
      final frameInfo = await codec.getNextFrame();
      final image = frameInfo.image;

      final resizedCodec = await ui.instantiateImageCodec(
        iconData,
        targetHeight: 50,
        targetWidth: 50,
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

      for (int i = 0; i < pixels.length; i += 4) {
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

  static void clearCache() {
    _colourCache.clear();
  }
}
