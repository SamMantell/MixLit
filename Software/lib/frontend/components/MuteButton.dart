import 'package:flutter/material.dart';

class MuteButton extends StatelessWidget {
  final bool isMuted;
  final Animation<double> animation;
  final Function() onTapDown;
  final Function() onTapUp;
  final Function() onTapCancel;

  const MuteButton({
    Key? key,
    required this.isMuted,
    required this.animation,
    required this.onTapDown,
    required this.onTapUp,
    required this.onTapCancel,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final Color baseColor =
        isMuted ? const Color(0xFFFF5252) : const Color(0xFF4CAF50);

    final icon = Icon(
      isMuted ? Icons.volume_off : Icons.volume_up,
      color: Colors.white,
      size: 24,
    );

    return GestureDetector(
      onTapDown: (_) => onTapDown(),
      onTapUp: (_) => onTapUp(),
      onTapCancel: onTapCancel,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: animation,
          builder: (context, child) {
            return Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: Color.lerp(
                  baseColor,
                  Colors.white,
                  animation.value * 0.5,
                ),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: baseColor.withOpacity(0.5),
                    spreadRadius: animation.value * 5,
                    blurRadius: 7,
                  ),
                ],
              ),
              transform: Matrix4.identity()
                ..scale(1.0 - (animation.value * 0.1)),
              child: Center(
                child: icon,
              ),
            );
          },
        ),
      ),
    );
  }
}
