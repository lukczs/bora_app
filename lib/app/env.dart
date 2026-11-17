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

  /// Liga o botão "Continuar com Google" (precisa do provedor Google configurado no Supabase).
  static const googleAuthEnabled = bool.fromEnvironment('GOOGLE_AUTH');

  static bool get isConfigured =>
      supabaseUrl.startsWith('https://') && !supabaseAnonKey.startsWith('COLE_AQUI');
}
