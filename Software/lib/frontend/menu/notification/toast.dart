import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';

class Toast extends StatefulWidget {
  final IconData icon;
  final String message;
  final Color color;
  final Duration duration;

  const Toast({
    Key? key,
    required this.icon,
    required this.message,
    required this.color,
    required this.duration,
  }) : super(key: key);

  @override
  State<Toast> createState() => _ToastState();

  // Static method to show the toast
  static void show({
    required BuildContext context,
    required IconData icon,
    required String message,
    required Color color,
    Duration duration = const Duration(seconds: 3),
  }) {
    OverlayEntry overlayEntry;
    
    overlayEntry = OverlayEntry(
      builder: (context) => Toast(
        icon: icon,
        message: message,
        color: color,
        duration: duration,
      ),
    );

    Overlay.of(context).insert(overlayEntry);

    // Remove the toast after duration + animation time
    //Future.delayed(duration + const Duration(milliseconds: 500), () {
    //  overlayEntry.remove();
    //});
  }
}

class _ToastState extends State<Toast> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _slideAnimation;
  late Animation<double> _progressAnimation;

  @override
  void initState() {
    super.initState();
    
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    // Slide animation from bottom-right to position
    _slideAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));

    // Progress bar animation
    _progressAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.linear,
    ));

    // Start entry animation
    _controller.forward();

    // Start exit animation after duration
    Future.delayed(widget.duration - const Duration(milliseconds: 500), () {
      if (mounted) {
        _controller.reverse();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Positioned(
          bottom: 32.0 + (_slideAnimation.value * 100),
          right: _slideAnimation.value * -400,
            child: Container(
              width: 300,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.75),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(
                        widget.icon,
                        color: widget.color,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.message,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Progress bar
                  TweenAnimationBuilder<double>(
                    duration: widget.duration,
                    tween: Tween(begin: 0.0, end: 1.0),
                    builder: (context, value, child) {
                      return LinearProgressIndicator(
                        value: value,
                        backgroundColor: Colors.white.withOpacity(0.1),
                        valueColor: AlwaysStoppedAnimation<Color>(widget.color),
                      );
                    },
                  ),
                ],
              ),
            ),
        );
      },
    );
  }
}