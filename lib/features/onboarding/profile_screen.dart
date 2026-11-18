import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/bora_button.dart';
import '../../core/widgets/step_scaffold.dart';
import '../../data/errors.dart';

const onboardingSteps = 7;

/// Passo 1: nome, sobrenome, senha (opcional) e idioma.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});
  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _form = GlobalKey<FormState>();
  late final _first = TextEditingController(text: ref.read(storeProvider).me?.firstNameRaw ?? '');
  late final _last = TextEditingController(text: ref.read(storeProvider).me?.lastName ?? '');
  final _password = TextEditingController();
  bool _showPassword = false;
  late String _language = _deviceLanguage();
  bool _loading = false;

  String _deviceLanguage() {
    final saved = ref.read(storeProvider).me?.language;
    if (saved != null && saved != 'pt-BR') return saved;
    final code = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    return switch (code) { 'en' => 'en', 'es' => 'es', _ => 'pt-BR' };
  }

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final store = ref.read(storeProvider);
      if (_password.text.isNotEmpty) await store.setPassword(_password.text);
      await store.saveBasicProfile(firstName: _first.text, lastName: _last.text, language: _language);
      if (mounted) context.push('/onboarding/terms');
    } catch (e) {
      if (mounted) showBoraError(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(storeProvider);
    return StepScaffold(
      step: 1,
      totalSteps: onboardingSteps,
      canGoBack: false,
      title: 'Como podemos te chamar?',
      subtitle: 'Seu primeiro nome aparece para quem viaja com você. O nome completo só depois da reserva.',
      action: BoraButton(label: 'Continuar', loading: _loading, onPressed: _save),
      secondaryAction: TextButton(
        onPressed: store.signOut,
        child: const Text('Sair desta conta', style: TextStyle(color: AppColors.textMuted)),
      ),
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _first,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'Nome'),
                    validator: (v) => (v ?? '').trim().length < 2 ? 'Obrigatório' : null,
                  ),
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: TextFormField(
                    controller: _last,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'Sobrenome'),
                    validator: (v) => (v ?? '').trim().length < 2 ? 'Obrigatório' : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.md),
            TextFormField(
              controller: _password,
              obscureText: !_showPassword,
              autofillHints: const [AutofillHints.newPassword],
              decoration: InputDecoration(
                labelText: 'Senha (opcional)',
                helperText: 'Se você já criou senha, deixe em branco.',
                helperMaxLines: 2,
                suffixIcon: IconButton(
                  icon: Icon(_showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                  onPressed: () => setState(() => _showPassword = !_showPassword),
                ),
              ),
              validator: (v) {
                final p = v ?? '';
                if (p.isEmpty) return null;
                if (p.length < 8) return 'Use pelo menos 8 caracteres.';
                if (!RegExp(r'\d').hasMatch(p) || !RegExp(r'[A-Za-z]').hasMatch(p)) return 'Misture letras e números.';
                return null;
              },
            ),
            const SizedBox(height: Space.md),
            DropdownButtonFormField<String>(
              initialValue: _language,
              decoration: const InputDecoration(labelText: 'Idioma preferido', prefixIcon: Icon(Icons.language)),
              dropdownColor: AppColors.surfaceRaised,
              items: const [
                DropdownMenuItem(value: 'pt-BR', child: Text('Português (Brasil)')),
                DropdownMenuItem(value: 'en', child: Text('English')),
                DropdownMenuItem(value: 'es', child: Text('Español')),
              ],
              onChanged: (v) => setState(() => _language = v ?? 'pt-BR'),
            ),
            const SizedBox(height: Space.xs),
            const Text('Usado nos avisos e e-mails do Bora.', style: AppText.caption),
          ],
        ),
      ),
    );
  }
}

/// Passo 2: aceite dos Termos de Uso e do Aviso de Privacidade.
class TermsScreen extends ConsumerStatefulWidget {
  const TermsScreen({super.key});
  @override
  ConsumerState<TermsScreen> createState() => _TermsScreenState();
}

class _TermsScreenState extends ConsumerState<TermsScreen> {
  late bool _accepted = ref.read(storeProvider).me?.termsAccepted ?? false;
  bool _loading = false;

  Future<void> _save() async {
    setState(() => _loading = true);
    try {
      await ref.read(storeProvider).acceptTerms();
      if (mounted) context.push('/onboarding/payment');
    } catch (e) {
      if (mounted) showBoraError(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _read(String title, List<(String, String)> items) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .75,
        builder: (_, sc) => ListView(
          controller: sc,
          padding: const EdgeInsets.fromLTRB(Space.page, 0, Space.page, Space.xl),
          children: [
            Text(title, style: AppText.headline),
            const SizedBox(height: Space.md),
            for (final (h, t) in items) ...[
              Text(h, style: AppText.subtitle),
              const SizedBox(height: Space.xxs),
              Text(t, style: AppText.body),
              const SizedBox(height: Space.md),
            ],
            const Text('Versão de teste do projeto acadêmico. O texto jurídico final ainda será revisado.', style: AppText.caption),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StepScaffold(
      step: 2,
      totalSteps: onboardingSteps,
      title: 'Termos e privacidade',
      subtitle: 'O Bora é carona solidária: pessoas dividindo o custo de um caminho que já iam fazer.',
      action: BoraButton(label: 'Aceitar e continuar', loading: _loading, onPressed: _accepted ? _save : null),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Point(Icons.handshake_outlined, 'Sem lucro', 'O valor é um rateio de custo, com teto. O motorista não ganha dinheiro com a carona.'),
          _Point(Icons.verified_user_outlined, 'Pessoas verificadas', 'Todo mundo confirma identidade antes de viajar.'),
          _Point(Icons.lock_outline, 'Seus dados', 'CPF, telefone e documento nunca aparecem para outros usuários. Localização só durante a carona.'),
          const SizedBox(height: Space.sm),
          Row(children: [
            TextButton(onPressed: () => _read('Termos de Uso', _terms), child: const Text('Ler os Termos de Uso')),
            TextButton(onPressed: () => _read('Aviso de Privacidade', _privacy), child: const Text('Aviso de Privacidade')),
          ]),
          const SizedBox(height: Space.xs),
          Material(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(Radii.md),
            child: CheckboxListTile(
              value: _accepted,
              onChanged: (v) => setState(() => _accepted = v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
              title: const Text('Li e concordo com os Termos de Uso e o Aviso de Privacidade do Bora.', style: AppText.bodyStrong),
            ),
          ),
        ],
      ),
    );
  }
}

const _terms = [
  ('Carona solidária', 'O Bora aproxima pessoas que fazem o mesmo caminho. Não é transporte remunerado: o motorista divide custos e não tem lucro.'),
  ('Conta', 'A conta é pessoal. Você precisa ter 18 anos ou mais e informar dados verdadeiros.'),
  ('Conduta', 'Respeito, pontualidade e segurança. Quem desrespeitar outras pessoas pode ser removido de viagens e comunidades.'),
  ('Pagamento', 'O valor sugerido é pago direto ao motorista (Pix ou dinheiro). O app cobra uma taxa fixa por viagem para se manter.'),
];

const _privacy = [
  ('O que coletamos', 'Nome, telefone ou e-mail, CPF, data de nascimento, contato de emergência e, durante a carona, a localização.'),
  ('Para que usamos', 'Verificar identidade, encontrar caronas no seu caminho e proteger quem viaja.'),
  ('O que os outros veem', 'Antes da reserva: primeiro nome, nota e o carro. Depois: nome completo e placa. Nunca CPF, telefone ou documento.'),
  ('Seus direitos (LGPD)', 'Você pode pedir uma cópia dos seus dados ou a exclusão da conta a qualquer momento.'),
];

class _Point extends StatelessWidget {
  const _Point(this.icon, this.title, this.text);
  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: Space.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AppColors.green, size: 24),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: AppText.bodyStrong),
                Text(text, style: AppText.body),
              ]),
            ),
          ],
        ),
      );
}

/// Passo 3: como prefere acertar o rateio (opcional).
class PaymentScreen extends ConsumerStatefulWidget {
  const PaymentScreen({super.key});
  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> {
  late String? _pref = ref.read(storeProvider).me?.paymentPref;
  bool _loading = false;

  Future<void> _save(String? pref) async {
    setState(() => _loading = true);
    try {
      await ref.read(storeProvider).setPaymentPref(pref);
      if (mounted) context.push('/onboarding/location');
    } catch (e) {
      if (mounted) showBoraError(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget option(String value, IconData icon, String title, String text, {bool soon = false}) {
      final selected = _pref == value;
      return Padding(
        padding: const EdgeInsets.only(bottom: Space.sm),
        child: Material(
          color: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.md),
            side: BorderSide(color: selected ? AppColors.green : Colors.transparent, width: 1.5),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(Radii.md),
            onTap: soon ? null : () => setState(() => _pref = value),
            child: Padding(
              padding: const EdgeInsets.all(Space.md),
              child: Row(
                children: [
                  Icon(icon, color: soon ? AppColors.textFaint : AppColors.text),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title, style: AppText.bodyStrong.copyWith(color: soon ? AppColors.textFaint : null)),
                      Text(text, style: AppText.caption),
                    ]),
                  ),
                  if (soon)
                    const Text('Em breve', style: AppText.caption)
                  else
                    Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off,
                        color: selected ? AppColors.green : AppColors.textFaint),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return StepScaffold(
      step: 3,
      totalSteps: onboardingSteps,
      title: 'Como você prefere pagar?',
      subtitle: 'O rateio é pago direto ao motorista no fim da carona. Isso só ajuda ele a se organizar; dá para mudar depois.',
      action: BoraButton(label: 'Continuar', loading: _loading, onPressed: _pref == null ? null : () => _save(_pref)),
      secondaryAction: TextButton(
        onPressed: _loading ? null : () => _save(null),
        child: const Text('Pular por enquanto', style: TextStyle(color: AppColors.textMuted)),
      ),
      child: Column(
        children: [
          option('pix', Icons.pix, 'Pix', 'Na hora, pela chave do motorista.'),
          option('dinheiro', Icons.payments_outlined, 'Dinheiro', 'Leve trocado.'),
          option('cartao', Icons.credit_card, 'Cartão no app', 'Pagamento dentro do Bora.', soon: true),
        ],
      ),
    );
  }
}
