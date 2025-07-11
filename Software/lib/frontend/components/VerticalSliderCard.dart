import 'package:flutter/material.dart';
import 'package:mixlit/frontend/components/tooltip_helper.dart';

class VerticalSliderCard extends StatelessWidget {
  final String title;
  final Widget? iconWidget;
  final double value;
  final bool isMuted;
  final bool isActive;
  final int percentage;
  final Color accentColor;
  final double accentOpacity;
  final ValueChanged<double> onSliderChanged;
  final VoidCallback onMutePressed;
  final VoidCallback onTap;
  final bool isDarkMode;

  const VerticalSliderCard({
    super.key,
    required this.title,
    required this.iconWidget,
    required this.value,
    required this.isMuted,
    required this.isActive,
    required this.percentage,
    required this.accentColor,
    this.accentOpacity = 1.0,
    required this.onSliderChanged,
    required this.onMutePressed,
    required this.onTap,
    required this.isDarkMode,
  });

  @override
  Widget build(BuildContext context) {
    final baseColor = isDarkMode ? const Color(0xFF282828) : Colors.white;
    final textColor = isDarkMode ? Colors.white : Colors.black87;
    final mutedTextColor = isDarkMode ? Colors.red[300]! : Colors.red;

    final effectiveAccentColor = accentColor.withOpacity(accentOpacity);
    final effectiveAccentColorLight =
        accentColor.withOpacity(accentOpacity * 0.1);
    final effectiveAccentColorMedium =
        accentColor.withOpacity(accentOpacity * 0.3);
    final effectiveAccentColorStrong =
        accentColor.withOpacity(accentOpacity * 0.8);

    const double cardWidth = 120;

    return Container(
      width: cardWidth,
      height: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: baseColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: isActive
              ? effectiveAccentColor.withOpacity(0.5 * accentOpacity)
              : accentColor.withOpacity(0.2),
          width: 2,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                CustomTooltip(
                  message: isActive ? 'Change' : 'Assign Application',
                  child: GestureDetector(
                    onTap: onTap,
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: effectiveAccentColorLight,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: effectiveAccentColorMedium,
                          width: 1,
                        ),
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          iconWidget ??
                              const Icon(Icons.apps, color: Colors.white),

                          //edit icon
                          if (isActive)
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: Container(
                                width: 16,
                                height: 16,
                                decoration: BoxDecoration(
                                  color: effectiveAccentColor,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: baseColor,
                                    width: 1,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.edit,
                                  color: Colors.white,
                                  size: 10,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: isActive ? onTap : null,
                  child: Text(
                    title,
                    style: TextStyle(
                      fontFamily: 'BitstreamVeraSans',
                      color: textColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w200,
                      height: 1,
                      decoration: TextDecoration.none,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 4),

                //volume value
                Text(
                  isMuted ? 'MUTED' : '$percentage',
                  style: TextStyle(
                    fontFamily: 'BitstreamVeraSans',
                    color: isMuted ? mutedTextColor : textColor,
                    fontSize: 12,
                    fontWeight: isMuted ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),

          //slider
          if (isActive)
            Expanded(
              child: Container(
                width: 60,
                margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                decoration: BoxDecoration(
                  color: isDarkMode
                      ? Colors.black26
                      : Colors.grey.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: RotatedBox(
                  quarterTurns: 3,
                  child: SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 60,
                      thumbColor: isMuted ? Colors.grey : effectiveAccentColor,
                      activeTrackColor: isMuted
                          ? Colors.grey.withOpacity(0.3)
                          : effectiveAccentColorStrong,
                      inactiveTrackColor: Colors.transparent,
                      overlayColor: effectiveAccentColorLight,
                      thumbShape: SliderThumbShape(
                        isMuted: isMuted,
                        accentColor: effectiveAccentColor,
                      ),
                      trackShape: CustomTrackShape(),
                    ),
                    child: Slider(
                      value: isMuted ? 0.0 : value,
                      onChanged: (val) {
                        if (isMuted) {
                          onMutePressed();
                        }
                        onSliderChanged(val);
                      },
                    ),
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: GestureDetector(
                onTap: onTap,
                child: Container(
                  width: 60,
                  margin:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDarkMode
                        ? Colors.black26
                        : Colors.grey.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.add,
                          color: effectiveAccentColor.withOpacity(0.5),
                          size: 32,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "Assign",
                          style: TextStyle(
                            fontFamily: 'BitstreamVeraSans',
                            color: effectiveAccentColor.withOpacity(0.7),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          //bottom part
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: CustomTooltip(
              message:
                  isActive ? (isMuted ? 'Unmute' : 'Mute') : 'Assign app first',
              child: MuteButton(
                isMuted: isMuted,
                accentColor: effectiveAccentColor,
                onPressed: onMutePressed,
                isActive: isActive,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CustomTrackShape extends RoundedRectSliderTrackShape {
  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final double trackHeight = sliderTheme.trackHeight ?? 4;
    final double trackLeft = offset.dx;
    final double trackTop =
        offset.dy + (parentBox.size.height - trackHeight) / 2;
    final double trackWidth = parentBox.size.width;
    return Rect.fromLTWH(trackLeft, trackTop, trackWidth, trackHeight);
  }
}

class SliderThumbShape extends SliderComponentShape {
  final bool isMuted;
  final Color accentColor;

  SliderThumbShape({
    required this.isMuted,
    required this.accentColor,
  });

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) {
    return const Size(28, 28);
  }

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final Canvas canvas = context.canvas;
    final thumbColor = isMuted ? Colors.grey : accentColor;

    final Paint fillPaint = Paint()
      ..color = thumbColor
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, 10, fillPaint);

    if (isMuted) {
      final Paint linePaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;

      canvas.drawLine(
        Offset(center.dx - 5, center.dy - 5),
        Offset(center.dx + 5, center.dy + 5),
        linePaint,
      );

      canvas.drawLine(
        Offset(center.dx + 5, center.dy - 5),
        Offset(center.dx - 5, center.dy + 5),
        linePaint,
      );
    } else {
      final Paint linePaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;

      canvas.drawLine(
        Offset(center.dx - 5, center.dy),
        Offset(center.dx + 5, center.dy),
        linePaint,
      );
    }
  }
}

class MuteButton extends StatelessWidget {
  final bool isMuted;
  final Color accentColor;
  final VoidCallback onPressed;
  final bool isActive;

  const MuteButton({
    super.key,
    required this.isMuted,
    required this.accentColor,
    required this.onPressed,
    required this.isActive,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isActive ? onPressed : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 60,
        height: 40,
        decoration: BoxDecoration(
          color: isActive
              ? (isMuted
                  ? Colors.red.withOpacity(0.8)
                  : accentColor.withOpacity(0.8))
              : Colors.grey.withOpacity(0.3),
          borderRadius: BorderRadius.circular(20),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color:
                        (isMuted ? Colors.red : accentColor).withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Center(
          child: Icon(
            isMuted ? Icons.volume_off : Icons.volume_up,
            color: Colors.white,
            size: 24,
          ),
        ),
      ),
    );
  }
}
