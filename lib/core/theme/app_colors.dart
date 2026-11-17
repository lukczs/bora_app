import 'package:flutter/material.dart';

/// Paleta do Bora (inalterada): azul-noite + verde Bora.
/// As cores derivadas abaixo são só variações de opacidade das mesmas.
class AppColors {
  static const night = Color(0xFF0F172A); // fundo
  static const surface = Color(0xFF1B2540); // cartões e campos
  static const line = Color(0xFF2C3A5C); // bordas
  static const green = Color(0xFF22C55E); // ação principal
  static const mint = Color(0xFFD8FFE8); // texto sobre verde translúcido
  static const text = Color(0xFFFFFFFF);
  static const textMuted = Color(0xFFCBD5E1);
  static const danger = Color(0xFFF87171);
  static const warning = Color(0xFFFBBF24);

  // Derivadas
  static const surfaceRaised = Color(0xFF222E4D); // sheet e cartões sobre o mapa
  static const textFaint = Color(0x99CBD5E1);
  static const greenSoft = Color(0x2622C55E);
  static const scrim = Color(0x990F172A);
  static const user = Color(0xFF38BDF8); // "você está aqui"
}
