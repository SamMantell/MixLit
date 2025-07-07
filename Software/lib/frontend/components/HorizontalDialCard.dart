import 'package:flutter/material.dart';
import 'package:mixlit/frontend/components/tooltip_helper.dart';
import 'dart:math' as math;

class HorizontalDialCard extends StatelessWidget {
  final String title;
  final Widget? iconWidget;
  final double value; // 0.0 to 1.0
  final bool isActive;
  final int percentage;
  final Color accentColor;
  final double accentOpacity;
  final ValueChanged<double> onDialChanged;
  final VoidCallback onTap;
  final bool isDarkMode;

  const HorizontalDialCard({
    super.key,
    required this.title,
    required this.iconWidget,
    required this.value,
    required this.isActive,
    required this.percentage,
    required this.accentColor,
    this.accentOpacity = 1.0,
    required this.onDialChanged,
    required this.onTap,
    required this.isDarkMode,
  });

  @override
  Widget build(BuildContext context) {
    final baseColor = isDarkMode ? const Color(0xFF282828) : Colors.white;
    final textColor = isDarkMode ? Colors.white : Colors.black87;

    final effectiveAccentColor = accentColor.withOpacity(accentOpacity);
    final effectiveAccentColorLight =
        accentColor.withOpacity(accentOpacity * 0.1);
    final effectiveAccentColorMedium =
        accentColor.withOpacity(accentOpacity * 0.3);

    return Container(
      height: 120,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: baseColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
        border: Border.all(
          color: isActive
              ? effectiveAccentColor.withOpacity(0.5 * accentOpacity)
              : accentColor.withOpacity(0.2),
          width: 2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            // Left section with dial
            SizedBox(
              width: 88,
              height: 88,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Dial background and progress
                  if (isActive)
                    GestureDetector(
                      onPanUpdate: (details) {
                        _handlePanUpdate(details);
                      },
                      child: CustomPaint(
                        size: const Size(88, 88),
                        painter: SegmentedDialPainter(
                          value: value,
                          accentColor: effectiveAccentColor,
                          backgroundColor:
                              Colors.transparent, // Remove background segments
                          strokeWidth: 8,
                        ),
                      ),
                    ),

                  GestureDetector(
                    onTap: onTap,
                    child: Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        color: effectiveAccentColorLight,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: effectiveAccentColorMedium,
                          width: 2,
                        ),
                      ),
                    ),
                  ),

                  // Center icon (clickable for app assignment)
                  CustomTooltip(
                    message: isActive ? 'Change' : 'Assign Application',
                    child: GestureDetector(
                      onTap: onTap,
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            if (!isActive) ...[
                              // Show add icon for unassigned
                              Icon(
                                Icons.add,
                                color: effectiveAccentColor.withOpacity(0.7),
                                size: 20,
                              ),
                            ] else ...[
                              // Show app icon for assigned
                              iconWidget ??
                                  const Icon(Icons.apps,
                                      color: Colors.white, size: 20),
                            ],

                            // Add a small edit icon for assigned cards
                            if (isActive)
                              Positioned(
                                right: 2,
                                bottom: 2,
                                child: Container(
                                  width: 14,
                                  height: 14,
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
                                    size: 8,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 16),

            // Right section with app info
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // App title
                    Text(
                      title,
                      style: TextStyle(
                        fontFamily: 'BitstreamVeraSans',
                        color: textColor,
                        fontSize: 16,
                        fontWeight: FontWeight.w400,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    // Volume percentage
                    Text(
                      '$percentage',
                      style: TextStyle(
                        fontFamily: 'BitstreamVeraSans',
                        color: textColor.withOpacity(0.7),
                        fontSize: 14,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    const center = Offset(44, 44);

    final touchPoint = details.localPosition;
    final dx = touchPoint.dx - center.dx;
    final dy = touchPoint.dy - center.dy;

    double angle = math.atan2(dy, dx);

    if (angle < 0) angle += 2 * math.pi;

    const startAngle = 3 * math.pi / 4; // 135° (bottom-left)
    const totalSweep = 3 * math.pi / 2; // 270° (bottom-right - 75% of circle)
    const endAngle = startAngle + totalSweep;

    double normalizedValue;

    if (angle >= startAngle) {
      // From 135° to 360°
      normalizedValue = (angle - startAngle) / totalSweep;
    } else if (angle <= (endAngle - 2 * math.pi)) {
      normalizedValue = (angle + 2 * math.pi - startAngle) / totalSweep;
    } else {
      double distToStart = math.min(
          (startAngle - angle).abs(), (startAngle - angle - 2 * math.pi).abs());
      double distToEnd = math.min(
          (endAngle - 2 * math.pi - angle).abs(), (endAngle - angle).abs());
      normalizedValue = distToStart < distToEnd ? 0.0 : 1.0;
    }

    normalizedValue = normalizedValue.clamp(0.0, 1.0);

    onDialChanged(normalizedValue);
  }
}

class SegmentedDialPainter extends CustomPainter {
  final double value;
  final Color accentColor;
  final Color backgroundColor;
  final double strokeWidth;
  final int segmentCount;

  //TODO: segemented design if looks good in design mock-up??
  SegmentedDialPainter({
    required this.value,
    required this.accentColor,
    required this.backgroundColor,
    required this.strokeWidth,
    this.segmentCount = 24,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    const startAngle = 3 * math.pi / 4;
    const totalSweep = 3 * math.pi / 2;
    const gapAngle = 0.04;

    final segmentAngle =
        (totalSweep - (segmentCount - 1) * gapAngle) / segmentCount;

    final filledSegments = (value * segmentCount).floor();
    final partialSegmentProgress = (value * segmentCount) - filledSegments;

    for (int i = 0; i < segmentCount; i++) {
      final segmentStartAngle = startAngle + i * (segmentAngle + gapAngle);

      if (i < filledSegments) {
        final paint = Paint()
          ..color = accentColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round;

        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius),
          segmentStartAngle,
          segmentAngle,
          false,
          paint,
        );
      } else if (i == filledSegments && partialSegmentProgress > 0) {
        final paint = Paint()
          ..color = accentColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round;
        final currentSegmentSweep = segmentAngle * partialSegmentProgress;

        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius),
          segmentStartAngle,
          currentSegmentSweep,
          false,
          paint,
        );
      }
    }

    if (value > 0) {
      final centerDotPaint = Paint()
        ..color = accentColor
        ..style = PaintingStyle.fill;

      canvas.drawCircle(center, 3, centerDotPaint);
    }
  }

  @override
  bool shouldRepaint(SegmentedDialPainter oldDelegate) {
    return oldDelegate.value != value ||
        oldDelegate.accentColor != accentColor ||
        oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.segmentCount != segmentCount;
  }
}
