import 'package:flutter/material.dart';
import 'package:mixlit/frontend/components/MuteButton.dart';

class MuteButtonContainer extends StatelessWidget {
  final double containerWidth;
  final List<bool> muteStates;
  final List<Animation<double>> buttonAnimations;
  final List<String> sliderTags;
  final Function(int) onTapDown;
  final Function(int) onTapUp;
  final Function(int) onTapCancel;

  const MuteButtonContainer({
    Key? key,
    required this.containerWidth,
    required this.muteStates,
    required this.buttonAnimations,
    required this.sliderTags,
    required this.onTapDown,
    required this.onTapUp,
    required this.onTapCancel,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: containerWidth,
      height: 60,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            spreadRadius: 2,
            blurRadius: 5,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(
          muteStates.length,
          (index) => MuteButton(
            isMuted: muteStates[index],
            animation: buttonAnimations[index],
            onTapDown: () => onTapDown(index),
            onTapUp: () => onTapUp(index),
            onTapCancel: () => onTapCancel(index),
          ),
        ),
      ),
    );
  }
}
