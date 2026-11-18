import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models.dart';

const _messages = <String, String>{
  'invalid_route_length': 'A rota precisa ter entre 500 m e 120 km.',
  'route_outside_area': 'Por enquanto o Bora funciona só no DF e Entorno.',
  'route_without_stops': 'Essa rota não passa perto de nenhuma parada de ônibus. Tente outro caminho.',
  'invalid_route': 'Não foi possível ler a rota. Calcule de novo.',
  'removed_by_driver': 'O motorista removeu você desta viagem.',
  'too_early_to_start': 'Dá para iniciar a corrida só a partir de 1 hora antes da saída.',
  'ride_already_in_progress': 'Você já tem outra corrida em andamento. Encerre ela primeiro.',
  'booking_not_active': 'Essa reserva já foi resolvida (embarcou, desceu ou cancelou).',
  'pickup_already_passed': 'O carro já passou dessa parada. Escolha uma parada mais à frente.',
  'cannot_remove_passenger': 'Só dá para remover quem ainda não embarcou.',

  'cpf_already_registered': 'Este CPF já está cadastrado em outra conta.',
  'invalid_cpf': 'CPF inválido.',
  'invalid_first_name': 'Digite o seu nome.',
  'invalid_last_name': 'Digite o seu sobrenome.',
  'event_limit_reached': 'Você já tem 5 eventos futuros. Cancele um para criar outro.',
  'event_in_past': 'A data do evento já passou.',
  'event_end_before_start': 'O fim precisa ser depois do começo.',
  'event_too_long': 'O evento pode durar no máximo 3 dias.',
  'event_not_found': 'Evento não encontrado ou cancelado.',
  'route_not_to_event': 'A rota de ida precisa terminar perto do local do evento.',
  'route_not_from_event': 'A rota de volta precisa sair de perto do local do evento.',
  'terms_required': 'É preciso aceitar os Termos de Uso para continuar.',
  'must_be_adult': 'É preciso ter 18 anos ou mais para usar o Bora.',
  'identity_locked': 'Seus dados já foram verificados e não podem ser alterados por aqui.',
  'identity_not_verified': 'Sua identidade ainda está em verificação. Isso libera após a aprovação.',
  'emergency_contact_required': 'Cadastre um contato de emergência para continuar.',
  'registration_incomplete': 'Complete seus dados antes de continuar.',
  'women_only_not_allowed': 'A opção "apenas mulheres" só está disponível para motoristas mulheres.',
  'vehicle_not_found': 'Carro não encontrado. Cadastre um carro antes de publicar.',
  'invalid_seats': 'O número de vagas não cabe nesse carro.',
  'departure_in_past': 'O horário de saída já passou. Escolha outro horário.',
  'invalid_path': 'Ainda não conhecemos um trajeto entre essas duas paradas.',
  'not_a_member': 'Você não participa dessa comunidade.',
  'seats_below_booked': 'Já existem vagas reservadas. Não dá para oferecer menos que isso.',
  'ride_unavailable': 'Esta viagem não está mais disponível.',
  'cannot_book_own_ride': 'Você não pode reservar a própria viagem.',
  'ride_full': 'As vagas desta viagem acabaram de ser preenchidas.',
  'women_only_ride': 'Esta viagem é exclusiva para mulheres.',
  'driver_not_allowed_by_preference': 'Sua preferência é viajar só com motoristas mulheres.',
  'already_booked': 'Você já tem uma vaga reservada nesta viagem.',
  'stops_not_on_route': 'Essas paradas não estão no trajeto desta viagem.',
  'cannot_cancel': 'Só dá para cancelar antes do embarque.',
  'community_limit_reached': 'Você já criou 3 comunidades, que é o limite por pessoa.',
  'invalid_invite_code': 'Código de convite não encontrado. Confira as letras e os números.',
  'banned_from_community': 'Você não pode entrar nesta comunidade.',
  'owner_cannot_leave': 'Quem criou a comunidade não pode sair dela.',
  'not_allowed': 'Você não tem permissão para fazer isso.',
  'vehicles_plate_key': 'Esta placa já está cadastrada.',
  'violates foreign key': 'Este carro está ligado a uma viagem e não pode ser excluído.',
  'Token has expired or is invalid': 'Código incorreto ou expirado. Peça um novo.',
  'Invalid login credentials': 'E-mail ou senha incorretos.',
  'Email not confirmed': 'Confirme o e-mail antes de entrar (ou desative a confirmação no painel do Supabase).',
  'User already registered': 'Este e-mail já tem conta. Use "Entrar".',
  'Signups not allowed for otp': 'Não encontramos uma conta com esse contato. Toque em "Criar conta".',
  'otp_expired': 'Código vencido. Peça outro.',
  'For security purposes, you can only request this after': 'Espere alguns segundos antes de pedir outro código.',
  'email rate limit exceeded': 'Muitos e-mails enviados agora. Tente de novo em alguns minutos ou use o celular.',
  'Unsupported phone provider': 'O envio de SMS ainda não está configurado no Supabase. Use o e-mail por enquanto.',
  'Password should be at least': 'A senha precisa ter pelo menos 6 caracteres.',
};

/// Converte qualquer erro (banco, auth, rede) numa frase para a pessoa ler.
String friendlyError(Object e) {
  if (e is BoraException) return e.message;
  final raw = switch (e) {
    PostgrestException(:final message) => message,
    AuthException(:final message) => message,
    _ => e.toString(),
  };
  for (final entry in _messages.entries) {
    if (raw.contains(entry.key)) return entry.value;
  }
  if (raw.contains('SocketException') || raw.contains('Failed host lookup') || raw.contains('ClientException')) {
    return 'Sem conexão. Confira sua internet e tente de novo.';
  }
  return 'Não deu certo agora. Detalhe técnico: $raw';
}
