import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Ícone de parada no estilo Moovit: quadradinho com ônibus em cima de uma
/// haste. A ponta da haste é o ponto exato da parada.
/// Usado pelos dois mapas (Google pinta como imagem, o reserva como widget).
class StopPin {
  StopPin._();

  /// Tamanho em pixels lógicos; a ponta da haste fica no meio da borda de baixo.
  static const size = Size(26, 34);

  static void paint(Canvas c, {Offset origin = Offset.zero}) {
    c.save();
    c.translate(origin.dx, origin.dy);
    const cx = 13.0;
    // Sombra no chão
    c.drawOval(Rect.fromCenter(center: const Offset(cx, 32.6), width: 9, height: 3), Paint()..color = const Color(0x66000000));
    // Haste
    c.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTRB(cx - 1.3, 18, cx + 1.3, 32.5), const Radius.circular(1.3)),
      Paint()..color = const Color(0xFFE2E8F0),
    );
    // Quadrado: sombra, borda branca, fundo verde
    final box = RRect.fromRectAndRadius(Rect.fromCenter(center: const Offset(cx, 12), width: 22, height: 22), const Radius.circular(6));
    c.drawRRect(box.shift(const Offset(0, 1.5)),
        Paint()..color = const Color(0x66000000)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));
    c.drawRRect(box, Paint()..color = Colors.white);
    c.drawRRect(box.deflate(2), Paint()..color = AppColors.green);
    _icon(c, Icons.directions_bus_rounded, const Offset(cx, 12), 15, AppColors.night);
    c.restore();
  }

  static void _icon(Canvas c, IconData icon, Offset center, double size, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(fontFamily: icon.fontFamily, package: icon.fontPackage, fontSize: size, color: color, height: 1),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, center - Offset(tp.width / 2, tp.height / 2));
  }
}

/// Versão widget do [StopPin] (mapa reserva).
class StopPinIcon extends StatelessWidget {
  const StopPinIcon({super.key});

  @override
  Widget build(BuildContext context) => CustomPaint(size: StopPin.size, painter: _StopPinPainter());
}

class _StopPinPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) => StopPin.paint(canvas);

  @override
  bool shouldRepaint(_StopPinPainter old) => false;
}
