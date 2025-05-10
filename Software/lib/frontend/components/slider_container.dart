import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'painting/muted_red_line.dart';
import 'package:mixlit/frontend/components/custom_slider.dart';

class SliderContainer extends StatelessWidget {
  final double containerWidth;
  final double containerHeight;
  final List<double> sliderValues;
  final List<dynamic> assignedApps; // Accept dynamic for flexibility
  final Map<String, Uint8List?> appIcons;
  final List<String> sliderTags;
  final Function(int sliderIndex, double value) onSliderChange;
  final Future<void> Function(int sliderIndex) onAssignApp;
  final Function(int sliderIndex, bool isDefault) onSelectDefaultDevice;
  final List<bool>? muteStates;

  const SliderContainer({
    super.key,
    required this.containerWidth,
    required this.containerHeight,
    required this.sliderValues,
    required this.assignedApps,
    required this.appIcons,
    required this.sliderTags,
    required this.onSliderChange,
    required this.onAssignApp,
    required this.onSelectDefaultDevice,
    this.muteStates,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: containerWidth,
      height: containerHeight,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.75),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(sliderValues.length, (index) {
              final appName = assignedApps[index] != null
                  ? _formatAppName(
                      assignedApps[index]!.processPath.split(r'\').last)
                  : 'Unassigned';

              final bool isMuted = muteStates != null
                  ? muteStates![index]
                  : (sliderValues[index] / 1024 * 100).round() == 0;

              final volumePercentage =
                  (sliderValues[index] / 1024 * 100).round();

              // Use default device icon if assigned, otherwise app icon
              Widget iconWidget;
              if (sliderTags[index] == 'defaultDevice') {
                // Default device: Use Icons.speaker when it's the default device
                iconWidget =
                    const Icon(Icons.speaker, color: Colors.white, size: 64);
              } else if (assignedApps[index] != null) {
                final appPath = assignedApps[index]!.processPath;
                iconWidget = Image.memory(
                  appIcons[appPath]!,
                  width: 64,
                  height: 64,
                  errorBuilder: (context, error, stackTrace) => const Icon(
                      Icons.image_not_supported,
                      color: Colors.white),
                );
              } else {
                iconWidget =
                    const Icon(Icons.apps, color: Colors.white, size: 64);
              }

              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Icon display with red line overlay for muted state
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      iconWidget,
                      if (isMuted)
                        CustomPaint(
                          size: const Size(64, 64),
                          painter: MutedRedLine(),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Display label for volume or MUTED
                  Text(
                    isMuted ? "MUTED" : "$volumePercentage%",
                    style: TextStyle(
                      color: isMuted ? Colors.red : Colors.white,
                      fontSize: 14,
                      fontWeight: isMuted ? FontWeight.bold : FontWeight.normal,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  // Vertical slider
                  SizedBox(
                    height: containerHeight *
                        0.5, // Proportional height for the slider
                    child: RotatedBox(
                      quarterTurns: 3,
                      child: CustomSlider(
                        value: sliderValues[index],
                        min: 0,
                        max: 1024,
                        activeColor: Colors.blueGrey,
                        inactiveColor: Colors.blueGrey.withOpacity(0.5),
                        onChanged: (newValue) =>
                            onSliderChange(index, newValue),
                        isMuted: isMuted,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // App assignment button
                  IconButton(
                    icon:
                        const Icon(Icons.arrow_drop_down, color: Colors.white),
                    onPressed: () => onAssignApp(index),
                    tooltip: 'Select application',
                  ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }

  String _formatAppName(String appName) {
    appName = appName.replaceAll('.exe', '');
    return appName[0].toUpperCase() + appName.substring(1);
  }
}
