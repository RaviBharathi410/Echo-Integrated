import 'dart:math' as math;

import 'package:echo_hearing/app/theme/echo_colors.dart';
import 'package:echo_hearing/core/domain/models/hearing_models.dart';
import 'package:flutter/material.dart';

/// ASHA-style interactive audiogram canvas rendering digital response patterns.
///
/// Matches `AudiogramView.kt`:
/// - Logarithmic (log2) X axis across 250 Hz .. 8000 Hz
/// - Inverted Y axis from 0 dBFS (top) to 80 dBFS (bottom)
/// - Shaded green `#E7F8F2` normal provisional screening band <= 25 dBFS
/// - Solid red line with hollow `O` circles for Right Ear
/// - Dashed blue line with `X` crosses for Left Ear
class AudiogramView extends StatelessWidget {
  const AudiogramView({
    super.key,
    required this.thresholds,
    this.height = 240,
  });

  final List<ThresholdResult> thresholds;
  final double height;

  @override
  Widget build(BuildContext context) {
    final leftPoints =
        thresholds.where((t) => t.ear == Ear.left).toList()
          ..sort((a, b) => a.frequencyHz.compareTo(b.frequencyHz));
    final rightPoints =
        thresholds.where((t) => t.ear == Ear.right).toList()
          ..sort((a, b) => a.frequencyHz.compareTo(b.frequencyHz));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(
            painter: _AudiogramPainter(
              leftPoints: leftPoints,
              rightPoints: rightPoints,
            ),
          ),
        ),
        const SizedBox(height: 10),
        const Wrap(
          alignment: WrapAlignment.center,
          spacing: 16,
          runSpacing: 6,
          children: [
            _LegendDot(
              symbol: 'O',
              color: Color(0xFFDC2626),
              label: 'Right Ear (AD)',
            ),
            _LegendDot(
              symbol: 'X',
              color: EchoColors.primary,
              label: 'Left Ear (AS)',
            ),
          ],
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({
    required this.symbol,
    required this.color,
    required this.label,
  });

  final String symbol;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          symbol,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w800,
            fontSize: 13,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            color: EchoColors.muted,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _AudiogramPainter extends CustomPainter {
  const _AudiogramPainter({
    required this.leftPoints,
    required this.rightPoints,
  });

  final List<ThresholdResult> leftPoints;
  final List<ThresholdResult> rightPoints;

  static const _freqs = [250, 500, 1000, 2000, 4000, 8000];
  static const _freqLabels = ['250', '500', '1k', '2k', '4k', '8k'];
  static const _levels = [0, 20, 40, 60, 80];

  @override
  void paint(Canvas canvas, Size size) {
    const padLeft = 36.0;
    const padRight = 14.0;
    const padTop = 14.0;
    const padBottom = 26.0;

    final chartW = size.width - padLeft - padRight;
    final chartH = size.height - padTop - padBottom;
    if (chartW <= 0 || chartH <= 0) return;

    double freqToX(int freq) {
      final logMin = math.log(250) / math.ln2;
      final logMax = math.log(8000) / math.ln2;
      final val = (math.log(freq.clamp(250, 8000)) / math.ln2 - logMin) /
          (logMax - logMin);
      return padLeft + val * chartW;
    }

    double dbToY(int db) {
      final norm = (db.clamp(0, 80)) / 80.0;
      return padTop + norm * chartH;
    }

    // Normal baseline green band <= 25 dBFS.
    final normalPaint = Paint()..color = EchoColors.emeraldSoft;
    canvas.drawRect(
      Rect.fromLTRB(padLeft, padTop, padLeft + chartW, dbToY(25)),
      normalPaint,
    );

    final gridPaint = Paint()
      ..color = EchoColors.border
      ..strokeWidth = 1.0;

    final borderPaint = Paint()
      ..color = EchoColors.pillBorder
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawRect(
      Rect.fromLTWH(padLeft, padTop, chartW, chartH),
      borderPaint,
    );

    // Vertical frequency lines & labels.
    for (var i = 0; i < _freqs.length; i++) {
      final x = freqToX(_freqs[i]);
      canvas.drawLine(
        Offset(x, padTop),
        Offset(x, padTop + chartH),
        gridPaint,
      );
      _drawText(
        canvas,
        _freqLabels[i],
        Offset(x, padTop + chartH + 4),
        centerX: true,
      );
    }

    // Horizontal level lines & labels.
    for (final db in _levels) {
      final y = dbToY(db);
      canvas.drawLine(
        Offset(padLeft, y),
        Offset(padLeft + chartW, y),
        gridPaint,
      );
      _drawText(
        canvas,
        '$db',
        Offset(padLeft - 6, y - 6),
        alignRight: true,
      );
    }

    // Right ear solid red line + hollow O markers.
    const redColor = Color(0xFFDC2626);
    final rightOffsets = rightPoints
        .map((p) => Offset(freqToX(p.frequencyHz), dbToY(p.thresholdDb)))
        .toList();
    if (rightOffsets.length > 1) {
      final linePaint = Paint()
        ..color = redColor
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke;
      final path = Path()..moveTo(rightOffsets.first.dx, rightOffsets.first.dy);
      for (var i = 1; i < rightOffsets.length; i++) {
        path.lineTo(rightOffsets[i].dx, rightOffsets[i].dy);
      }
      canvas.drawPath(path, linePaint);
    }
    for (final pt in rightOffsets) {
      canvas.drawCircle(
        pt,
        6,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        pt,
        6,
        Paint()
          ..color = redColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4,
      );
    }

    // Left ear dashed blue line + X crosses.
    const blueColor = EchoColors.primary;
    final leftOffsets = leftPoints
        .map((p) => Offset(freqToX(p.frequencyHz), dbToY(p.thresholdDb)))
        .toList();
    if (leftOffsets.length > 1) {
      final dashPaint = Paint()
        ..color = blueColor
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke;
      for (var i = 0; i < leftOffsets.length - 1; i++) {
        _drawDashedSegment(canvas, leftOffsets[i], leftOffsets[i + 1], dashPaint);
      }
    }
    for (final pt in leftOffsets) {
      const r = 5.5;
      final xPaint = Paint()
        ..color = blueColor
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(pt.dx - r, pt.dy - r),
        Offset(pt.dx + r, pt.dy + r),
        xPaint,
      );
      canvas.drawLine(
        Offset(pt.dx - r, pt.dy + r),
        Offset(pt.dx + r, pt.dy - r),
        xPaint,
      );
    }
  }

  void _drawDashedSegment(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dashLen = 6.0;
    const gapLen = 4.0;
    final delta = b - a;
    final dist = delta.distance;
    if (dist <= 0) return;
    final dir = delta / dist;
    double d = 0;
    while (d < dist) {
      final start = a + dir * d;
      final end = a + dir * math.min(d + dashLen, dist);
      canvas.drawLine(start, end, paint);
      d += dashLen + gapLen;
    }
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset pos, {
    bool centerX = false,
    bool alignRight = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: EchoColors.muted,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    var dx = pos.dx;
    if (centerX) dx -= tp.width / 2;
    if (alignRight) dx -= tp.width;
    tp.paint(canvas, Offset(dx, pos.dy));
  }

  @override
  bool shouldRepaint(covariant _AudiogramPainter oldDelegate) {
    return oldDelegate.leftPoints != leftPoints ||
        oldDelegate.rightPoints != rightPoints;
  }
}
