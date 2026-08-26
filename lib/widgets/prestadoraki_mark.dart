import 'package:flutter/material.dart';

/// A marca do PrestadorAki (pino de localização + casinha) desenhada em
/// código — vetorial, sem depender de nenhum arquivo de imagem, então
/// fica nítida em qualquer tamanho e não pesa nada no app. É o mesmo
/// desenho usado pra gerar o ícone do app nos launchers (esse sim precisa
/// ser um PNG, por exigência do Android/iOS) — se a marca mudar, os dois
/// lugares precisam ser atualizados juntos.
class PrestadorAkiMark extends StatelessWidget {
  const PrestadorAkiMark({
    super.key,
    this.size = 160,
    this.pinColor = Colors.white,
    this.circleColor = const Color(0xFF241512),
  });

  final double size;
  final Color pinColor;
  final Color circleColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _MarkPainter(pinColor: pinColor, circleColor: circleColor),
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  _MarkPainter({required this.pinColor, required this.circleColor});

  final Color pinColor;
  final Color circleColor;

  // Coordenadas num canvas de referência de 1024x1024 (mesmas do desenho
  // original do ícone), escaladas pro tamanho real do widget em paint().
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 1024;
    Offset p(double x, double y) => Offset(x * s, y * s);

    final pinPaint = Paint()
      ..color = pinColor
      ..style = PaintingStyle.fill;
    final pinShadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.22)
      ..style = PaintingStyle.fill
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 10 * s);

    final pinPath = Path()
      ..moveTo(p(560, 190).dx, p(560, 190).dy)
      ..cubicTo(p(668, 190).dx, p(668, 190).dy, p(748, 270).dx, p(748, 270).dy, p(748, 374).dx,
          p(748, 374).dy)
      ..cubicTo(p(748, 470).dx, p(748, 470).dy, p(660, 560).dx, p(660, 560).dy, p(588, 660).dx,
          p(588, 660).dy)
      ..cubicTo(p(574, 680).dx, p(574, 680).dy, p(546, 680).dx, p(546, 680).dy, p(532, 660).dx,
          p(532, 660).dy)
      ..cubicTo(p(460, 560).dx, p(460, 560).dy, p(372, 470).dx, p(372, 470).dy, p(372, 374).dx,
          p(372, 374).dy)
      ..cubicTo(p(372, 270).dx, p(372, 270).dy, p(452, 190).dx, p(452, 190).dy, p(560, 190).dx,
          p(560, 190).dy)
      ..close();

    canvas.save();
    canvas.translate(0, 6 * s);
    canvas.drawPath(pinPath, pinShadowPaint);
    canvas.restore();
    canvas.drawPath(pinPath, pinPaint);

    final circleCenter = p(560, 378);
    final circleRadius = 132 * s;
    canvas.drawCircle(circleCenter, circleRadius, Paint()..color = circleColor);

    final housePath = Path()
      ..moveTo(p(560, 300).dx, p(560, 300).dy)
      ..lineTo(p(648, 372).dx, p(648, 372).dy)
      ..lineTo(p(628, 372).dx, p(628, 372).dy)
      ..lineTo(p(628, 448).dx, p(628, 448).dy)
      ..lineTo(p(492, 448).dx, p(492, 448).dy)
      ..lineTo(p(492, 372).dx, p(492, 372).dy)
      ..lineTo(p(472, 372).dx, p(472, 372).dy)
      ..close();
    canvas.drawPath(housePath, Paint()..color = pinColor);

    final windowPaint = Paint()..color = circleColor;
    void window(double x, double y) {
      final rect = Rect.fromLTWH(p(x, y).dx, p(x, y).dy, 20 * s, 20 * s);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(3 * s)), windowPaint);
    }

    window(536, 392);
    window(564, 392);
    window(536, 416);
    window(564, 416);
  }

  @override
  bool shouldRepaint(covariant _MarkPainter oldDelegate) =>
      oldDelegate.pinColor != pinColor || oldDelegate.circleColor != circleColor;
}
