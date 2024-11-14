// lib/frontend/components/application_icon.dart

import 'dart:typed_data';
import 'package:flutter/material.dart';

class ApplicationIcon extends StatelessWidget {
  final Uint8List iconData;

  ApplicationIcon({required this.iconData});

  @override
  Widget build(BuildContext context) {
    return Image.memory(
      iconData,
      width: 32,
      height: 32,
      errorBuilder: (context, error, stackTrace) {
        return Icon(Icons.apps, size: 32);  // Default icon if loading fails
      },
    );
  }
}
