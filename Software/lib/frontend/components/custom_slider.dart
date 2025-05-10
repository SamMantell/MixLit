import 'package:flutter/material.dart';

class CustomSlider extends StatelessWidget {
  final double value;
  final double min;
  final double max;
  final Color? activeColor;
  final Color? inactiveColor;
  final ValueChanged<double> onChanged;
  final bool isMuted;

  static final SliderComponentShape _sliderTrackShape =
      SliderComponentShape.noOverlay;

  const CustomSlider({
    Key? key,
    required this.value,
    this.min = 0.0,
    this.max = 1024.0,
    this.activeColor,
    this.inactiveColor,
    required this.onChanged,
    this.isMuted = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Use RepaintBoundary to optimize rendering performance
    return RepaintBoundary(
      child: Slider(
        value: value,
        min: min,
        max: max,
        activeColor: activeColor ?? Colors.blueGrey,
        inactiveColor: inactiveColor ?? Colors.blueGrey.withOpacity(0.5),
        onChanged: onChanged,
      ),
    );
  }
}
