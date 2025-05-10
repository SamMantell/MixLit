import 'package:flutter/material.dart';

class MuteButton extends StatefulWidget {
  final bool isMuted;
  final bool isPressed;
  final Function(bool) onToggle;
  final Color color;

  const MuteButton({
    Key? key,
    required this.isMuted,
    required this.isPressed,
    required this.onToggle,
    this.color = Colors.white,
  }) : super(key: key);

  @override
  _MuteButtonState createState() => _MuteButtonState();
}

class _MuteButtonState extends State<MuteButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.8).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(MuteButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPressed != oldWidget.isPressed) {
      if (widget.isPressed) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => widget.onToggle(!widget.isMuted),
      child: AnimatedBuilder(
        animation: _animationController,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color:
                        widget.color.withOpacity(widget.isPressed ? 0.5 : 0.2),
                    blurRadius: widget.isPressed ? 8 : 4,
                    spreadRadius: widget.isPressed ? 2 : 0,
                  ),
                ],
                border: Border.all(
                  color: widget.color.withOpacity(0.5),
                  width: 1.5,
                ),
              ),
              child: Icon(
                widget.isMuted ? Icons.volume_off : Icons.volume_up,
                color: widget.color,
                size: 30,
              ),
            ),
          );
        },
      ),
    );
  }
}
