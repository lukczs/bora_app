import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models.dart';

const _messages = <String, String>{
  'cpf_already_registered': 'Este CPF já está cadastrado em outra conta.',
  'invalid_cpf': 'CPF inválido.',
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
