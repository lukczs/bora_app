import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Espaçamentos (grade de 4).
class Space {
  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const xxl = 48.0;

  /// Margem lateral padrão das telas.
  static const page = 20.0;
}

class Radii {
  static const sm = 10.0;
  static const md = 14.0;
  static const lg = 20.0;
  static const sheet = 24.0;
}

/// Tipografia: uma família só (a do sistema), hierarquia por peso e tamanho.
class AppText {
  static const display = TextStyle(
      fontSize: 32, fontWeight: FontWeight.w800, height: 1.1, letterSpacing: -.8, color: AppColors.text);
  static const headline = TextStyle(
      fontSize: 24, fontWeight: FontWeight.w800, height: 1.2, letterSpacing: -.4, color: AppColors.text);
  static const title = TextStyle(fontSize: 18, fontWeight: FontWeight.w700, height: 1.3, color: AppColors.text);
  static const subtitle = TextStyle(fontSize: 16, fontWeight: FontWeight.w600, height: 1.35, color: AppColors.text);
  static const body = TextStyle(fontSize: 15, fontWeight: FontWeight.w400, height: 1.45, color: AppColors.textMuted);
  static const bodyStrong = TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 1.4, color: AppColors.text);
  static const label = TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.3, color: AppColors.textMuted);
  static const caption = TextStyle(fontSize: 12, fontWeight: FontWeight.w500, height: 1.3, color: AppColors.textFaint);
  static const overline = TextStyle(
      fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.1, color: AppColors.textFaint);
  static const button = TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: .1);
  static const number = TextStyle(
      fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -.3, color: AppColors.text,
      fontFeatures: [FontFeature.tabularFigures()]);
}

class Shadows {
  static const floating = [BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 8))];
  static const soft = [BoxShadow(color: Color(0x40000000), blurRadius: 12, offset: Offset(0, 4))];
}
