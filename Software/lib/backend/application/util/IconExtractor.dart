import 'dart:io';
import 'dart:typed_data';
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';
import 'package:image/image.dart' as img;

class IconExtractor {
  static const int SHGFI_ICON = 0x000000100;
  static const int SHGFI_LARGEICON = 0x000000000;
  static const int SHGFI_SMALLICON = 0x000000001;

  /// returns base64 png formatted data from icon
  static Future<Uint8List?> extractSmallIcon(String executablePath) async {
    if (!Platform.isWindows) {
      return null;
    }

    try {
      final pathPtr = executablePath.toNativeUtf16();
      final shFileInfo = calloc<SHFILEINFO>();

      final result = SHGetFileInfo(
        pathPtr,
        0,
        shFileInfo,
        sizeOf<SHFILEINFO>(),
        SHGFI_ICON | SHGFI_SMALLICON,
      );

      if (result != 0 && shFileInfo.ref.hIcon != 0) {
        final pngData = await _convertHIconToPng(shFileInfo.ref.hIcon);
        DestroyIcon(shFileInfo.ref.hIcon);
        calloc.free(pathPtr);
        calloc.free(shFileInfo);
        return pngData;
      }

      calloc.free(pathPtr);
      calloc.free(shFileInfo);
      return null;
    } catch (e) {
      print('Error extracting small icon: $e');
      return null;
    }
  }

  static Future<Uint8List?> extractLargeIcon(String executablePath) async {
    if (!Platform.isWindows) {
      return null;
    }

    try {
      final pathPtr = executablePath.toNativeUtf16();
      final shFileInfo = calloc<SHFILEINFO>();

      final result = SHGetFileInfo(
        pathPtr,
        0,
        shFileInfo,
        sizeOf<SHFILEINFO>(),
        SHGFI_ICON | SHGFI_LARGEICON,
      );

      if (result != 0 && shFileInfo.ref.hIcon != 0) {
        final pngData = await _convertHIconToPng(shFileInfo.ref.hIcon);
        DestroyIcon(shFileInfo.ref.hIcon);
        calloc.free(pathPtr);
        calloc.free(shFileInfo);
        return pngData;
      }

      calloc.free(pathPtr);
      calloc.free(shFileInfo);
      return null;
    } catch (e) {
      print('Error extracting large icon: $e');
      return null;
    }
  }

  static Future<Uint8List?> _convertHIconToPng(int hIcon) async {
    try {
      // Get icon information
      final iconInfo = calloc<ICONINFO>();
      if (GetIconInfo(hIcon, iconInfo) == 0) {
        calloc.free(iconInfo);
        return null;
      }

      final colorBitmap = iconInfo.ref.hbmColor;
      final maskBitmap = iconInfo.ref.hbmMask;

      // Get device context
      final hdc = GetDC(NULL);
      if (hdc == 0) {
        DeleteObject(colorBitmap);
        DeleteObject(maskBitmap);
        calloc.free(iconInfo);
        return null;
      }

      // Get bitmap info
      final bitmapInfo = calloc<BITMAPINFO>();
      bitmapInfo.ref.bmiHeader.biSize = sizeOf<BITMAPINFOHEADER>();

      if (GetDIBits(
              hdc, colorBitmap, 0, 0, nullptr, bitmapInfo, DIB_RGB_COLORS) ==
          0) {
        ReleaseDC(NULL, hdc);
        DeleteObject(colorBitmap);
        DeleteObject(maskBitmap);
        calloc.free(iconInfo);
        calloc.free(bitmapInfo);
        return null;
      }

      final width = bitmapInfo.ref.bmiHeader.biWidth;
      final height = bitmapInfo.ref.bmiHeader.biHeight.abs();
      final bitsPerPixel = bitmapInfo.ref.bmiHeader.biBitCount;

      // Calculate image size
      final imageSize = ((width * bitsPerPixel + 31) ~/ 32) * 4 * height;
      final colorData = calloc<Uint8>(imageSize);

      // Get color bitmap data
      bitmapInfo.ref.bmiHeader.biHeight = -height;
      bitmapInfo.ref.bmiHeader.biCompression = BI_RGB;
      if (GetDIBits(hdc, colorBitmap, 0, height, colorData, bitmapInfo,
              DIB_RGB_COLORS) ==
          0) {
        ReleaseDC(NULL, hdc);
        DeleteObject(colorBitmap);
        DeleteObject(maskBitmap);
        calloc.free(iconInfo);
        calloc.free(bitmapInfo);
        calloc.free(colorData);
        return null;
      }

      // Convert BGRA to RGBA and create image
      final pixels = colorData.asTypedList(imageSize);
      final rgbaPixels = Uint8List(width * height * 4);

      for (int i = 0; i < pixels.length; i += 4) {
        if (i + 3 < pixels.length && i + 3 < rgbaPixels.length) {
          rgbaPixels[i] = pixels[i + 2]; // R
          rgbaPixels[i + 1] = pixels[i + 1]; // G
          rgbaPixels[i + 2] = pixels[i]; // B
          rgbaPixels[i + 3] = pixels[i + 3]; // A
        }
      }
      final image = img.Image.fromBytes(
        width: width,
        height: height,
        bytes: rgbaPixels.buffer,
        numChannels: 4,
      );

      final pngBytes = img.encodePng(image);

      // Clean up
      ReleaseDC(NULL, hdc);
      DeleteObject(colorBitmap);
      DeleteObject(maskBitmap);
      calloc.free(iconInfo);
      calloc.free(bitmapInfo);
      calloc.free(colorData);

      return Uint8List.fromList(pngBytes);
    } catch (e) {
      print('Error converting HICON to PNG: $e');
      return null;
    }
  }

  static Future<bool> extractIconToFile(
      String executablePath, String outputPath) async {
    try {
      final iconData = await extractLargeIcon(executablePath);
      if (iconData != null) {
        await File(outputPath).writeAsBytes(iconData);
        print('Successfully extracted icon to $outputPath');
        return true;
      }
      return false;
    } catch (e) {
      print('Error extracting icon to file: $e');
      return false;
    }
  }
}
