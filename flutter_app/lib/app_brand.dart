import 'package:flutter/material.dart';

class SnipersBrandMark extends StatelessWidget {
  const SnipersBrandMark({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _SnipersBrandPainter()),
    );
  }
}

class _SnipersBrandPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final radius = size.width * 0.24;
    final scale = size.width / 48;

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(radius)),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF293B25), Color(0xFF101710)],
        ).createShader(rect),
    );

    final center = rect.center;
    final lime = Paint()
      ..color = const Color(0xFFC5F86A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.7 * scale
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    canvas.drawCircle(center, size.width * 0.31, lime);

    final ticks = Paint()
      ..color = const Color(0xFFC5F86A)
      ..strokeWidth = 2.7 * scale
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    final outer = size.width * 0.44;
    final inner = size.width * 0.37;
    canvas.drawLine(
      Offset(center.dx, center.dy - outer),
      Offset(center.dx, center.dy - inner),
      ticks,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy + inner),
      Offset(center.dx, center.dy + outer),
      ticks,
    );
    canvas.drawLine(
      Offset(center.dx - outer, center.dy),
      Offset(center.dx - inner, center.dy),
      ticks,
    );
    canvas.drawLine(
      Offset(center.dx + inner, center.dy),
      Offset(center.dx + outer, center.dy),
      ticks,
    );

    final play = Path()
      ..moveTo(center.dx - size.width * 0.075, center.dy - size.width * 0.12)
      ..lineTo(center.dx + size.width * 0.13, center.dy)
      ..lineTo(center.dx - size.width * 0.075, center.dy + size.width * 0.12)
      ..close();
    canvas.drawPath(
      play,
      Paint()
        ..color = const Color(0xFFC5F86A)
        ..style = PaintingStyle.fill
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(covariant _SnipersBrandPainter oldDelegate) => false;
}
