import 'package:flutter/material.dart';

class ModernSliderCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final double value;
  final bool isMuted;
  final bool isActive;
  final int percentage;
  final Color backgroundColor;
  final Color? foregroundColor;
  final Color accentColor;
  final ValueChanged<double> onSliderChanged;
  final VoidCallback onToggleMute;
  final VoidCallback onTap;

  const ModernSliderCard({
    super.key,
    required this.title,
    required this.icon,
    required this.value,
    required this.isMuted,
    required this.isActive,
    required this.percentage,
    required this.backgroundColor,
    this.foregroundColor,
    required this.accentColor,
    required this.onSliderChanged,
    required this.onToggleMute,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = foregroundColor ??
        (backgroundColor.computeLuminance() > 0.5
            ? Colors.black87
            : Colors.white);

    return GestureDetector(
      onTap: isActive ? onToggleMute : onTap,
      child: Container(
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              offset: const Offset(0, 4),
              blurRadius: 8,
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon and title row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(
                    icon,
                    color: textColor,
                    size: 28,
                  ),
                  if (isActive)
                    _buildToggleSwitch()
                  else
                    IconButton(
                      icon: Icon(Icons.add, color: textColor),
                      onPressed: onTap,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                ],
              ),

              const SizedBox(height: 10),

              // Title
              Text(
                title,
                style: TextStyle(
                  color: textColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),

              const SizedBox(height: 6),

              // Volume percentage
              Text(
                isMuted ? 'Muted' : '$percentage%',
                style: TextStyle(
                  color: isMuted ? Colors.red : textColor.withOpacity(0.8),
                  fontSize: 14,
                  fontWeight: isMuted ? FontWeight.bold : FontWeight.normal,
                ),
              ),

              const Spacer(),

              // Slider
              if (isActive)
                SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 4,
                    thumbColor: accentColor,
                    activeTrackColor: accentColor,
                    inactiveTrackColor: accentColor.withOpacity(0.2),
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 8,
                      elevation: 2,
                    ),
                  ),
                  child: Slider(
                    value: isMuted ? 0.0 : value,
                    onChanged: (val) {
                      if (isMuted) {
                        onToggleMute();
                      }
                      onSliderChanged(val);
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToggleSwitch() {
    return GestureDetector(
      onTap: onToggleMute,
      child: Container(
        width: 52,
        height: 28,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          color: isMuted
              ? Colors.grey.withOpacity(0.3)
              : accentColor.withOpacity(0.2),
        ),
        padding: const EdgeInsets.all(2),
        child: Stack(
          children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              left: isMuted ? 2 : 26,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isMuted ? Colors.grey : accentColor,
                ),
                child: Center(
                  child: Icon(
                    isMuted ? Icons.volume_off : Icons.volume_up,
                    color: Colors.white,
                    size: 14,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
