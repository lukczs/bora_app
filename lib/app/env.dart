import 'package:flutter/foundation.dart' show kIsWeb;

/// Cole aqui os dados do seu projeto Supabase (Settings > API).
/// A chave "anon" é pública por natureza: quem protege os dados é o RLS do banco.
/// Nunca coloque aqui a chave "service_role".
class Env {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'COLE_AQUI_A_URL', // ex.: https://abcdefgh.supabase.co
  );
  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'COLE_AQUI_A_CHAVE_ANON',
  );

  /// Token da OpenRouteService (rotas e endereços). Vazio = recursos de rota desligados.
  static const orsApiKey = String.fromEnvironment('ORS_API_KEY');

  /// ID do cliente OAuth "Aplicativo da Web" do Google Cloud (o mesmo colocado no
  /// Supabase). Com ele o botão "Continuar com Google" funciona, sem navegador.
  static const googleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
  static bool get googleAuthEnabled => googleWebClientId.isNotEmpty;

  /// Código por SMS (precisa de provedor de SMS no Supabase). Desligado = só e-mail e Google.
  static const smsEnabled = bool.fromEnvironment('SMS_ENABLED');
  static const appleAuthEnabled = bool.fromEnvironment('APPLE_AUTH');
  static const facebookAuthEnabled = bool.fromEnvironment('FACEBOOK_AUTH');

  /// Token público do Mapbox (busca de comércios e lugares). Vazio = busca só pela OpenRouteService.
  static const mapboxToken = String.fromEnvironment('MAPBOX_TOKEN');

  /// Usa o Google Maps (o workflow liga quando existe o secret MAPS_API_KEY).
  static const googleMapsEnabled = bool.fromEnvironment('GOOGLE_MAPS');

  static bool get isConfigured =>
      supabaseUrl.startsWith('https://') && !supabaseAnonKey.startsWith('COLE_AQUI');

  /// No navegador, o download dos blocos do mapa (OpenFreeMap/OpenStreetMap)
  /// é bloqueado por CORS — esses servidores não liberam fetch() direto de
  /// outro site. No celular isso não existe, então só a web passa por aqui.
  /// A função 'tile-proxy' (Supabase Edge Function) busca o bloco no servidor
  /// e devolve liberado.
  static String tileUrl(String url) {
    if (!kIsWeb) return url;
    // Templates de bloco têm placeholders tipo {z}/{x}/{y} que a biblioteca
    // do mapa substitui depois; precisam sobreviver ao encodeComponent sem
    // virar %7Bz%7D, senão a substituição não acha mais o {z} no texto.
    const marks = {'{z}': '\u0001Z\u0001', '{x}': '\u0001X\u0001', '{y}': '\u0001Y\u0001', '{s}': '\u0001S\u0001'};
    var marked = url;
    marks.forEach((k, v) => marked = marked.replaceAll(k, v));
    var encoded = Uri.encodeComponent(marked);
    marks.forEach((k, v) => encoded = encoded.replaceAll(v, k));
    return '$supabaseUrl/functions/v1/tile-proxy?url=$encoded';
  }
}
