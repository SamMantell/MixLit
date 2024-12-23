// lib/frontend/components/knob.dart

import 'package:flutter/material.dart';

class CustomKnob extends StatelessWidget {
  final double value;
  final String label;
  final ValueChanged<double> onChanged;

  const CustomKnob({super.key, required this.value, required this.label, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 18)),
        Slider( // For simplicity, using Slider here; replace with custom knob widget if needed
          value: value,
          min: 0,
          max: 100,
          onChanged: onChanged,
        ),
        Text(value.toStringAsFixed(1)),
      ],
    );
  }
}
