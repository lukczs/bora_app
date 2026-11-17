import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'map_types.dart';

/// Desenha os marcadores do Bora como imagem (o Google Maps só aceita bitmap).
/// Tudo é pintado em pixels lógicos e multiplicado pela densidade da tela.
class MarkerArt {
  MarkerArt(this.dpr);
  final double dpr;

  final Map<String, Future<MarkerImage>> _cache = {};

  Future<MarkerImage> image(PinKind kind, {String? label}) {
    final key = '$kind|${label ?? ''}';
    return _cache.putIfAbsent(key, () => _paint(kind, label));
  }

  Future<MarkerImage> _paint(PinKind kind, String? label) async {
    return switch (kind) {
      PinKind.stop => _render(const Size(26, 26), (c, s) => _busBadge(c, Offset(s.width / 2, s.height / 2), 22), anchor: const Offset(.5, .5)),
      PinKind.stopNamed => _labeled(label ?? '', AppColors.surfaceRaised, AppColors.text, badge: true),
      PinKind.highlight => _labeled(label ?? '', AppColors.green, AppColors.night, badge: false),
      PinKind.car => _render(const Size(40, 40), (c, s) => _car(c, s, mine: false), anchor: const Offset(.5, .5)),
      PinKind.carMine => _render(const Size(44, 44), (c, s) => _car(c, s, mine: true), anchor: const Offset(.5, .5)),
      PinKind.you => _render(const Size(30, 30), _you, anchor: const Offset(.5, .5)),
      PinKind.origin => _render(const Size(18, 18), (c, s) {
          c.drawCircle(s.center(Offset.zero), 8, Paint()..color = AppColors.night);
          c.drawCircle(s.center(Offset.zero), 5.5, Paint()..color = AppColors.text);
        }, anchor: const Offset(.5, .5)),
      PinKind.destination => _render(const Size(22, 22), (c, s) {
          c.drawRect(Offset.zero & s, Paint()..color = AppColors.night);
          c.drawRect(const Rect.fromLTWH(4, 4, 14, 14), Paint()..color = AppColors.text);
        }, anchor: const Offset(.5, .5)),
    };
  }

  // Selo de parada (estilo Moovit): quadrado verde arredondado com ônibus.
  void _busBadge(Canvas c, Offset center, double size) {
    final r = RRect.fromRectAndRadius(Rect.fromCenter(center: center, width: size, height: size), Radius.circular(size * .28));
    c.drawRRect(r.inflate(1.5), Paint()..color = AppColors.night);
    c.drawRRect(r, Paint()..color = AppColors.green);
    _icon(c, Icons.directions_bus_rounded, center, size * .68, AppColors.night);
  }

  void _icon(Canvas c, IconData icon, Offset center, double size, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(fontFamily: icon.fontFamily, package: icon.fontPackage, fontSize: size, color: color, height: 1),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, center - Offset(tp.width / 2, tp.height / 2));
  }

  void _car(Canvas c, Size s, {required bool mine}) {
    final center = s.center(Offset.zero);
    final r = s.width / 2 - 3;
    c.drawCircle(center + const Offset(0, 1.5), r + 1, Paint()..color = const Color(0x55000000)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
    c.drawCircle(center, r, Paint()..color = mine ? AppColors.green : AppColors.surfaceRaised);
    c.drawCircle(center, r, Paint()..color = mine ? AppColors.night : AppColors.green..style = PaintingStyle.stroke..strokeWidth = 2.2);
    // Seta pequena no topo indica a direção (o marcador gira com o carro).
    final tip = Path()
      ..moveTo(center.dx, center.dy - r - 2)
      ..lineTo(center.dx - 4.5, center.dy - r + 4)
      ..lineTo(center.dx + 4.5, center.dy - r + 4)
      ..close();
    c.drawPath(tip, Paint()..color = mine ? AppColors.night : AppColors.green);
    _icon(c, Icons.directions_car_filled, center, r * 1.15, mine ? AppColors.night : AppColors.text);
  }

  void _you(Canvas c, Size s) {
    final center = s.center(Offset.zero);
    c.drawCircle(center, 14, Paint()..color = const Color(0x3338BDF8));
    c.drawCircle(center, 8.5, Paint()..color = Colors.white);
    c.drawCircle(center, 6, Paint()..color = AppColors.user);
  }

  // Etiqueta com nome + ponteiro embaixo; o ponto de ancoragem é a ponta.
  Future<MarkerImage> _labeled(String text, Color bg, Color fg, {required bool badge}) {
    final shown = text.length > 34 ? '${text.substring(0, 33)}…' : text;
    final tp = TextPainter(
      text: TextSpan(text: shown, style: TextStyle(color: fg, fontSize: 12.5, fontWeight: FontWeight.w700, height: 1.2)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    const padH = 9.0, padV = 6.0, badgeSize = 18.0, gap = 6.0, pointer = 7.0;
    final contentW = (badge ? badgeSize + gap : 0) + tp.width;
    final w = contentW + padH * 2;
    final h = math.max(tp.height, badge ? badgeSize : 0) + padV * 2;
    final size = Size(w + 4, h + pointer + 4);
    return _render(size, (c, s) {
      final box = RRect.fromRectAndRadius(Rect.fromLTWH(2, 2, w, h), const Radius.circular(9));
      c.drawRRect(box.shift(const Offset(0, 1.5)), Paint()..color = const Color(0x55000000)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5));
      final p = Paint()..color = bg;
      c.drawRRect(box, p);
      final cx = 2 + w / 2;
      c.drawPath(
          Path()
            ..moveTo(cx - 6, 2 + h - .5)
            ..lineTo(cx, 2 + h + pointer)
            ..lineTo(cx + 6, 2 + h - .5)
            ..close(),
          p);
      var x = 2 + padH;
      if (badge) {
        _busBadge(c, Offset(x + badgeSize / 2, 2 + h / 2), badgeSize);
        x += badgeSize + gap;
      }
      tp.paint(c, Offset(x, 2 + (h - tp.height) / 2));
    }, anchor: Offset(.5, 1 - 2 / size.height));
  }

  Future<MarkerImage> _render(Size size, void Function(Canvas, Size) draw, {required Offset anchor}) async {
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec)..scale(dpr);
    draw(canvas, size);
    final img = await rec.endRecording().toImage((size.width * dpr).ceil(), (size.height * dpr).ceil());
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return MarkerImage(data!.buffer.asUint8List(), anchor);
  }
}

class MarkerImage {
  const MarkerImage(this.png, this.anchor);
  final Uint8List png;
  final Offset anchor;
}
