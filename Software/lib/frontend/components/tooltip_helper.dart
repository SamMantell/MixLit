import 'package:flutter/material.dart';

/// A custom tooltip with better styling for use throughout the app
class CustomTooltip extends StatelessWidget {
  final Widget child;
  final String message;
  final Color? backgroundColor;
  final Color? textColor;

  const CustomTooltip({
    Key? key,
    required this.child,
    required this.message,
    this.backgroundColor,
    this.textColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: message,
      textStyle: TextStyle(
        color: textColor ?? Colors.white,
        fontSize: 12,
      ),
      decoration: BoxDecoration(
        color: backgroundColor ?? Colors.black.withOpacity(0.8),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      preferBelow: true,
      verticalOffset: 16,
      child: child,
    );
  }
}
