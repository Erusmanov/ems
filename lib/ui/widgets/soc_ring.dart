import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// Круговой индикатор SOC: серый трек + цветная дуга по проценту, в центре —
/// крупный SOC%, подпись «SOC» и статус (Заряд/Разряд/Ожидание).
class SocRing extends StatelessWidget {
  final double soc; // %
  final Color color;
  final String statusText;
  final Color statusColor;
  final double size;

  const SocRing({
    super.key,
    required this.soc,
    required this.color,
    required this.statusText,
    required this.statusColor,
    this.size = 150,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size.square(size),
            painter: _RingPainter(soc: soc, color: color),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: soc.round().toString(),
                      style: TextStyle(
                        color: color,
                        fontSize: size * 0.28,
                        fontWeight: FontWeight.w700,
                        height: 1,
                        letterSpacing: -0.5,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    TextSpan(
                      text: '%',
                      style: TextStyle(
                        color: color,
                        fontSize: size * 0.13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              Text('SOC',
                  style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: size * 0.085,
                      letterSpacing: 1.5)),
              const SizedBox(height: 4),
              Text(
                statusText,
                style: TextStyle(
                  color: statusColor,
                  fontSize: size * 0.085,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double soc;
  final Color color;

  _RingPainter({required this.soc, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.068;
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = (size.width - stroke) / 2;
    final arcRect = Rect.fromCircle(center: center, radius: radius);

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = AppColors.ringTrack;
    canvas.drawArc(arcRect, 0, 2 * math.pi, false, track);

    final sweep = 2 * math.pi * (soc.clamp(0, 100) / 100.0);
    const start = -math.pi / 2; // от верхней точки
    final progress = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(arcRect, start, sweep, false, progress);

    // Белая точка на конце дуги (как на макете)
    if (soc > 0 && soc < 100) {
      final ang = start + sweep;
      final dot = Offset(
        center.dx + radius * math.cos(ang),
        center.dy + radius * math.sin(ang),
      );
      canvas.drawCircle(dot, stroke * 0.55, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.soc != soc || old.color != color;
}
