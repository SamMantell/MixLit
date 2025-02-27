// lib/frontend/components/slider.dart

import 'package:flutter/material.dart';

class CustomSlider extends StatelessWidget {
  final double value;
  final String label;
  final ValueChanged<double> onChanged;

  const CustomSlider({super.key, required this.value, required this.label, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 18)),
        Slider(
          value: value,
          min: 0,
          max: 1024,
          onChanged: onChanged,
        ),
        Text(value.toStringAsFixed(1)),
      ],
    );
  }
}
