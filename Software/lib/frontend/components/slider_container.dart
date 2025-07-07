import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'painting/muted_red_line.dart';
import 'package:mixlit/frontend/components/custom_slider.dart';
import 'package:mixlit/backend/application/data/ConfigManager.dart';

class SliderContainer extends StatelessWidget {
  final double containerWidth;
  final double containerHeight;
  final List<double> sliderValues;
  final List<dynamic> assignedApps; // Accept dynamic for flexibility
  final Map<String, Uint8List?> appIcons;
  final List<String>
      sliderTags; // New list to track the tag of each slider (app or default device)
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
              final String sliderTag = sliderTags[index];
              String sliderLabel = 'Unassigned';

              if (sliderTag == ConfigManager.TAG_APP &&
                  assignedApps[index] != null) {
                sliderLabel = _formatAppName(
                    assignedApps[index]!.processPath.split(r'\').last);
              } else if (sliderTag == ConfigManager.TAG_DEFAULT_DEVICE ||
                  sliderTag == ConfigManager.TAG_MASTER_VOLUME) {
                sliderLabel = 'Master Volume';
              } else if (sliderTag == ConfigManager.TAG_ACTIVE_APP) {
                sliderLabel = 'Active App';
              }

              final bool isMuted = muteStates != null
                  ? muteStates![index]
                  : (sliderValues[index] / 1024 * 100).round() == 0;

              final volumePercentage =
                  (sliderValues[index] / 1024 * 100).round();

              Widget iconWidget;
              if (sliderTag == ConfigManager.TAG_DEFAULT_DEVICE ||
                  sliderTag == ConfigManager.TAG_MASTER_VOLUME) {
                iconWidget =
                    const Icon(Icons.volume_up, color: Colors.white, size: 64);
              } else if (sliderTag == ConfigManager.TAG_ACTIVE_APP) {
                iconWidget = const Icon(Icons.app_registration,
                    color: Colors.white, size: 64);
              } else if (sliderTag == ConfigManager.TAG_APP &&
                  assignedApps[index] != null) {
                final appPath = assignedApps[index]!.processPath;
                if (appIcons.containsKey(appPath) &&
                    appIcons[appPath] != null) {
                  iconWidget = Image.memory(
                    appIcons[appPath]!,
                    width: 64,
                    height: 64,
                    errorBuilder: (context, error, stackTrace) =>
                        const Icon(Icons.apps, color: Colors.white, size: 64),
                  );
                } else {
                  iconWidget =
                      const Icon(Icons.apps, color: Colors.white, size: 64);
                }
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
                  const SizedBox(height: 8),
                  SizedBox(
                    width: 80,
                    child: Text(
                      sliderLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  const SizedBox(height: 4),
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
                    height: containerHeight * 0.5,
                    child: RotatedBox(
                      quarterTurns: 3,
                      child: CustomSlider(
                        value: sliderValues[index],
                        min: 0,
                        max: 1024,
                        activeColor: _getSliderColor(sliderTag),
                        inactiveColor:
                            _getSliderColor(sliderTag).withOpacity(0.5),
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

  Color _getSliderColor(String sliderTag) {
    if (sliderTag == ConfigManager.TAG_DEFAULT_DEVICE ||
        sliderTag == ConfigManager.TAG_MASTER_VOLUME) {
      return Colors.green;
    } else if (sliderTag == ConfigManager.TAG_ACTIVE_APP) {
      return Colors.purple;
    } else if (sliderTag == ConfigManager.TAG_APP) {
      return Colors.blue;
    } else {
      return Colors.blueGrey;
    }
  }
}
