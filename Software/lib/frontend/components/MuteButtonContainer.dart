import 'package:flutter/material.dart';
import 'package:mixlit/frontend/components/MuteButton.dart';

class MuteButtonContainer extends StatelessWidget {
  final double containerWidth;
  final double containerHeight;
  final List<bool> mutedStates;
  final List<bool> pressedStates;
  final List<String> sliderTags;
  final Function(int, bool) onToggleMute;

  const MuteButtonContainer({
    Key? key,
    required this.containerWidth,
    required this.containerHeight,
    required this.mutedStates,
    required this.pressedStates,
    required this.sliderTags,
    required this.onToggleMute,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Define button colors based on slider tags
    final List<Color> buttonColors = sliderTags.map((tag) {
      if (tag == 'defaultDevice') {
        return Colors.blue;
      } else if (tag == 'app') {
        return Colors.green;
      } else {
        return Colors.white;
      }
    }).toList();

    return Container(
      width: containerWidth,
      height: containerHeight * 0.25, // Adjust height as needed
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withOpacity(0.2),
          width: 1.5,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(
          mutedStates.length,
          (index) => MuteButton(
            isMuted: mutedStates[index],
            isPressed: pressedStates[index],
            onToggle: (value) => onToggleMute(index, value),
            color: buttonColors[index],
          ),
        ),
      ),
    );
  }
}
