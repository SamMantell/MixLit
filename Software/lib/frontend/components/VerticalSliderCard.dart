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
  final bool hasIntegration;

  // New properties for group support
  final bool isGroup;
  final int? appCount;
  final String? sliderType; // 'app', 'group', 'device', 'master', etc.

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
    this.isGroup = false,
    this.hasIntegration = false,
    this.appCount,
    this.sliderType,
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
                          // Use different icons based on slider type
                          _buildMainIcon(),

                          //Integration
                          if (hasIntegration)
                            Positioned(
                              right: 0,
                              top: 0,
                              child: Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  color: effectiveAccentColor,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: baseColor,
                                    width: 2,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.power,
                                  color: Colors.white,
                                  size: 16,
                                ),
                              ),
                            ),

                          // Edit icon for active sliders
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

                // Volume value with app count for groups
                Column(
                  children: [
                    Text(
                      isMuted ? 'MUTED' : '$percentage',
                      style: TextStyle(
                        fontFamily: 'BitstreamVeraSans',
                        color: isMuted ? mutedTextColor : textColor,
                        fontSize: 12,
                        fontWeight:
                            isMuted ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    if (isGroup && appCount != null)
                      Text(
                        '$appCount apps',
                        style: TextStyle(
                          fontFamily: 'BitstreamVeraSans',
                          color: textColor.withOpacity(0.6),
                          fontSize: 10,
                        ),
                      ),
                  ],
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
                      thumbColor: Colors.transparent,
                      activeTrackColor: isMuted
                          ? Colors.grey.withOpacity(0.3)
                          : effectiveAccentColorStrong,
                      inactiveTrackColor: Colors.transparent,
                      overlayColor: Colors.transparent,
                      thumbShape: SliderThumbShape(
                        isMuted: isMuted,
                        accentColor: effectiveAccentColor,
                        isGroup: isGroup,
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

  Widget _buildMainIcon() {
    if (iconWidget != null) {
      return iconWidget!;
    }

    // Return appropriate icon based on slider type
    switch (sliderType) {
      case 'group':
        return Icon(
          Icons.folder,
          color: Colors.white,
          size: 24,
        );
      case 'device':
        return Icon(
          Icons.speaker,
          color: Colors.white,
          size: 24,
        );
      case 'master':
        return Icon(
          Icons.volume_up,
          color: Colors.white,
          size: 24,
        );
      case 'active_app_control':
        return Icon(
          Icons.app_registration,
          color: Colors.white,
          size: 24,
        );
      default:
        return const Icon(Icons.apps, color: Colors.white, size: 24);
    }
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
    final double trackWidth = parentBox.size.width + 30;
    return Rect.fromLTWH(trackLeft, trackTop, trackWidth, trackHeight);
  }

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 2,
  }) {
    if (sliderTheme.trackHeight == null || sliderTheme.trackHeight! <= 0) {
      return;
    }

    final Rect trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );

    final Canvas canvas = context.canvas;
    final double trackRadius = trackRect.height / 2;

    final Paint inactivePaint = Paint()
      ..color = sliderTheme.inactiveTrackColor ?? Colors.grey.withOpacity(0.3)
      ..style = PaintingStyle.fill;

    final RRect inactiveRRect = RRect.fromRectAndRadius(
      trackRect,
      Radius.circular(trackRadius),
    );
    canvas.drawRRect(inactiveRRect, inactivePaint);

    final double sliderValue =
        (thumbCenter.dx - trackRect.left) / (trackRect.right - trackRect.left);

    final double visualHeightStart = trackRect.left;
    final double visualHeightEnd = thumbCenter.dx;

    double thicknessScale = 1.0;
    if (sliderValue <= 0.10) {
      thicknessScale = sliderValue / 0.10;
      thicknessScale = thicknessScale.clamp(0.0, 1.0);
    }

    final double originalThickness = trackRect.height;
    final double scaledThickness = originalThickness * thicknessScale;

    if (thicknessScale > 0.0 && visualHeightEnd > visualHeightStart) {
      canvas.save();
      canvas.clipRRect(inactiveRRect);

      final double thicknessOffset = (originalThickness - scaledThickness) / 2;

      final Rect activeTrackRect = Rect.fromLTRB(
        visualHeightStart,
        trackRect.top + thicknessOffset,
        visualHeightEnd,
        trackRect.bottom - thicknessOffset,
      );

      final Paint activePaint = Paint()
        ..color = sliderTheme.activeTrackColor ?? Colors.blue
        ..style = PaintingStyle.fill;

      if (scaledThickness < 2.0) {
        canvas.drawRect(activeTrackRect, activePaint);
      } else {
        final double scaledRadius =
            (scaledThickness / 2).clamp(0.0, trackRadius);

        final RRect activeRRect = RRect.fromRectAndRadius(
          activeTrackRect,
          Radius.circular(scaledRadius),
        );
        canvas.drawRRect(activeRRect, activePaint);
      }

      canvas.restore();
    }
  }
}

class SliderThumbShape extends SliderComponentShape {
  final bool isMuted;
  final Color accentColor;
  final bool isGroup;

  SliderThumbShape({
    required this.isMuted,
    required this.accentColor,
    this.isGroup = false,
  });

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) {
    return const Size(0, 0);
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
  }) {}
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
        duration: const Duration(milliseconds: 100),
        width: 60,
        height: 40,
        decoration: BoxDecoration(
          color: isActive
              ? (isMuted
                  ? Colors.red.withOpacity(0.8)
                  : accentColor.withOpacity(0.8))
              : Colors.grey.withOpacity(0.3),
          borderRadius: BorderRadius.circular(10),
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
