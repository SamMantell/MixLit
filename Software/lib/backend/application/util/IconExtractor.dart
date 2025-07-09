import 'dart:io';
import 'dart:typed_data';
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

class IconExtractor {
  static const int SHGFI_ICON = 0x000000100;
  static const int SHGFI_LARGEICON = 0x000000000;
  static const int SHGFI_SMALLICON = 0x000000001;

  /// Extracts an icon from the given executable path and saves it as an ICO file
  static Future<bool> extractIconToFile(
      String executablePath, String outputPath) async {
    if (!Platform.isWindows) {
      print('Icon extraction is only supported on Windows');
      return false;
    }

    try {
      // Get the icon handle using SHGetFileInfo
      final pathPtr = executablePath.toNativeUtf16();
      final shFileInfo = calloc<SHFILEINFO>();

      final result = SHGetFileInfo(
        pathPtr,
        0,
        shFileInfo,
        sizeOf<SHFILEINFO>(),
        SHGFI_ICON | SHGFI_LARGEICON,
      );

      if (result == 0) {
        print('Failed to get file info for $executablePath');
        calloc.free(pathPtr);
        calloc.free(shFileInfo);
        return false;
      }

      final hIcon = shFileInfo.ref.hIcon;
      if (hIcon == 0) {
        print('No icon found for $executablePath');
        calloc.free(pathPtr);
        calloc.free(shFileInfo);
        return false;
      }

      // Convert HICON to ICO file data
      final iconData = await _convertHIconToIcoData(hIcon);

      // Clean up
      DestroyIcon(hIcon);
      calloc.free(pathPtr);
      calloc.free(shFileInfo);

      if (iconData != null) {
        // Write the ICO data to file
        await File(outputPath).writeAsBytes(iconData);
        print('Successfully extracted icon to $outputPath');
        return true;
      }

      return false;
    } catch (e) {
      print('Error extracting icon: $e');
      return false;
    }
  }

  /// Converts an HICON to ICO file format data
  static Future<Uint8List?> _convertHIconToIcoData(int hIcon) async {
    try {
      // Get icon information
      final iconInfo = calloc<ICONINFO>();
      if (GetIconInfo(hIcon, iconInfo) == 0) {
        calloc.free(iconInfo);
        return null;
      }

      // Get bitmap information for the color bitmap
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
      bitmapInfo.ref.bmiHeader.biHeight = height;
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

      // Get mask bitmap data
      final maskSize = ((width + 31) ~/ 32) * 4 * height;
      final maskData = calloc<Uint8>(maskSize);

      final maskBitmapInfo = calloc<BITMAPINFO>();
      maskBitmapInfo.ref.bmiHeader.biSize = sizeOf<BITMAPINFOHEADER>();
      maskBitmapInfo.ref.bmiHeader.biWidth = width;
      maskBitmapInfo.ref.bmiHeader.biHeight = -height;
      maskBitmapInfo.ref.bmiHeader.biPlanes = 1;
      maskBitmapInfo.ref.bmiHeader.biBitCount = 1;
      maskBitmapInfo.ref.bmiHeader.biCompression = BI_RGB;

      GetDIBits(
          hdc, maskBitmap, 0, height, maskData, maskBitmapInfo, DIB_RGB_COLORS);

      // Create ICO file structure
      final icoData = _createIcoFileData(
        width,
        height,
        bitsPerPixel,
        colorData.asTypedList(imageSize),
        maskData.asTypedList(maskSize),
      );

      // Clean up
      ReleaseDC(NULL, hdc);
      DeleteObject(colorBitmap);
      DeleteObject(maskBitmap);
      calloc.free(iconInfo);
      calloc.free(bitmapInfo);
      calloc.free(maskBitmapInfo);
      calloc.free(colorData);
      calloc.free(maskData);

      return icoData;
    } catch (e) {
      print('Error converting HICON to ICO data: $e');
      return null;
    }
  }

  /// Creates ICO file format data from bitmap data
  static Uint8List _createIcoFileData(
    int width,
    int height,
    int bitsPerPixel,
    Uint8List colorData,
    Uint8List maskData,
  ) {
    // ICO file header (6 bytes)
    final header = ByteData(6);
    header.setUint16(0, 0, Endian.little); // Reserved
    header.setUint16(2, 1, Endian.little); // Type (1 = ICO)
    header.setUint16(4, 1, Endian.little); // Number of images

    // ICO directory entry (16 bytes)
    final dirEntry = ByteData(16);
    dirEntry.setUint8(0, width == 256 ? 0 : width); // Width
    dirEntry.setUint8(1, height == 256 ? 0 : height); // Height
    dirEntry.setUint8(2, 0); // Color count (0 for >8bpp)
    dirEntry.setUint8(3, 0); // Reserved
    dirEntry.setUint16(4, 1, Endian.little); // Planes
    dirEntry.setUint16(6, bitsPerPixel, Endian.little); // Bits per pixel

    final imageDataSize = 40 +
        colorData.length +
        maskData.length; // BITMAPINFOHEADER + color + mask
    dirEntry.setUint32(8, imageDataSize, Endian.little); // Image size
    dirEntry.setUint32(12, 22, Endian.little); // Offset to image data (6 + 16)

    // BITMAPINFOHEADER (40 bytes)
    final bmpHeader = ByteData(40);
    bmpHeader.setUint32(0, 40, Endian.little); // Header size
    bmpHeader.setInt32(4, width, Endian.little); // Width
    bmpHeader.setInt32(
        8, height * 2, Endian.little); // Height (doubled for ICO)
    bmpHeader.setUint16(12, 1, Endian.little); // Planes
    bmpHeader.setUint16(14, bitsPerPixel, Endian.little); // Bits per pixel
    bmpHeader.setUint32(16, 0, Endian.little); // Compression
    bmpHeader.setUint32(
        20, colorData.length + maskData.length, Endian.little); // Image size
    bmpHeader.setUint32(24, 0, Endian.little); // X pixels per meter
    bmpHeader.setUint32(28, 0, Endian.little); // Y pixels per meter
    bmpHeader.setUint32(32, 0, Endian.little); // Colors used
    bmpHeader.setUint32(36, 0, Endian.little); // Important colors

    // Combine all data
    final totalSize = 6 + 16 + 40 + colorData.length + maskData.length;
    final result = Uint8List(totalSize);
    int offset = 0;

    // Copy header
    result.setRange(offset, offset + 6, header.buffer.asUint8List());
    offset += 6;

    // Copy directory entry
    result.setRange(offset, offset + 16, dirEntry.buffer.asUint8List());
    offset += 16;

    // Copy bitmap header
    result.setRange(offset, offset + 40, bmpHeader.buffer.asUint8List());
    offset += 40;

    // Copy color data
    result.setRange(offset, offset + colorData.length, colorData);
    offset += colorData.length;

    // Copy mask data
    result.setRange(offset, offset + maskData.length, maskData);

    return result;
  }

  /// Extracts a small icon (16x16) for use in UI
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
        final iconData = await _convertHIconToIcoData(shFileInfo.ref.hIcon);
        DestroyIcon(shFileInfo.ref.hIcon);
        calloc.free(pathPtr);
        calloc.free(shFileInfo);
        return iconData;
      }

      calloc.free(pathPtr);
      calloc.free(shFileInfo);
      return null;
    } catch (e) {
      print('Error extracting small icon: $e');
      return null;
    }
  }
}
