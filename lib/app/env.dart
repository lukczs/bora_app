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
}
