import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/env.dart';
import '../../app/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/masks.dart';
import '../../core/utils/validators.dart';
import '../../core/widgets/bora_button.dart';
import '../../core/widgets/step_scaffold.dart';
import '../../data/errors.dart';

/// País para o DDI.
class Country {
  const Country(this.flag, this.name, this.ddi, this.mask, this.minDigits);
  final String flag;
  final String name;
  final String ddi;
  final String? mask;
  final int minDigits;
}

const countries = [
  Country('🇧🇷', 'Brasil', '55', '(##) #####-####', 11),
  Country('🇵🇹', 'Portugal', '351', '### ### ###', 9),
  Country('🇦🇷', 'Argentina', '54', null, 10),
  Country('🇵🇾', 'Paraguai', '595', null, 9),
  Country('🇺🇾', 'Uruguai', '598', null, 8),
  Country('🇨🇱', 'Chile', '56', null, 9),
  Country('🇺🇸', 'Estados Unidos', '1', '(###) ###-####', 10),
];

/// Criar conta ou entrar: Google (um toque) ou e-mail e senha.
/// Celular com código por SMS só aparece quando o envio de SMS estiver ligado.
class ContactScreen extends ConsumerStatefulWidget {
  const ContactScreen({super.key, required this.signup});
  final bool signup;
  @override
  ConsumerState<ContactScreen> createState() => _ContactScreenState();
}

class _ContactScreenState extends ConsumerState<ContactScreen> {
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _password2 = TextEditingController();
  Country _country = countries.first;
  bool _usePhone = false;
  bool _showPassword = false;
  bool _loading = false;
  bool _googleLoading = false;

  @override
  void dispose() {
    _phone.dispose();
    _email.dispose();
    _password.dispose();
    _password2.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (_usePhone) return _sendSms();
    final email = _email.text.trim().toLowerCase();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[a-z]{2,}$').hasMatch(email)) {
      showBoraError(context, 'Digite um e-mail válido.');
      return;
    }
    if (_password.text.length < 6) {
      showBoraError(context, 'A senha precisa ter pelo menos 6 caracteres.');
      return;
    }
    if (widget.signup && _password.text != _password2.text) {
      showBoraError(context, 'As duas senhas não estão iguais.');
      return;
    }
    setState(() => _loading = true);
    try {
      await ref.read(storeProvider).emailPasswordSignIn(email: email, password: _password.text, create: widget.signup);
      // deu certo: o app segue sozinho para o cadastro ou para o início
    } catch (e) {
      if (mounted) showBoraError(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendSms() async {
    final digits = onlyDigits(_phone.text);
    if (digits.length < _country.minDigits) {
      showBoraError(context, 'Confira o número com DDD.');
      return;
    }
    final to = '+${_country.ddi}$digits';
    setState(() => _loading = true);
    try {
      await ref.read(storeProvider).sendCode(to, create: widget.signup);
      if (mounted) context.push('/verify?channel=sms&to=${Uri.encodeQueryComponent(to)}&signup=${widget.signup}');
    } catch (e) {
      if (mounted) showBoraError(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _google() async {
    if (!Env.googleAuthEnabled) {
      showBoraError(context, 'Entrar com Google ainda não foi ativado neste app.');
      return;
    }
    setState(() => _googleLoading = true);
    try {
      await ref.read(storeProvider).signInWithGoogle();
    } catch (e) {
      if (mounted) showBoraError(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  Future<void> _forgot() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      showBoraError(context, 'Digite seu e-mail no campo acima e toque de novo em "Esqueci a senha".');
      return;
    }
    try {
      await ref.read(storeProvider).resetPassword(email);
      if (mounted) showBoraError(context, 'Se esse e-mail tiver conta, enviamos um link para criar uma senha nova.');
    } catch (e) {
      if (mounted) showBoraError(context, friendlyError(e));
    }
  }

  Future<void> _pickCountry() async {
    final c = await showModalBottomSheet<Country>(
      context: context,
      builder: (sheet) => ListView(
        shrinkWrap: true,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(Space.page, 0, Space.page, Space.xs),
            child: Text('Código do país', style: AppText.title),
          ),
          for (final c in countries)
            ListTile(
              leading: Text(c.flag, style: const TextStyle(fontSize: 22)),
              title: Text(c.name, style: AppText.bodyStrong),
              trailing: Text('+${c.ddi}', style: AppText.label),
              selected: c == _country,
              onTap: () => Navigator.of(sheet).pop(c),
            ),
          const SizedBox(height: Space.md),
        ],
      ),
    );
    if (c != null) {
      setState(() {
        _country = c;
        _phone.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.signup ? 'Crie sua conta' : 'Entrar no Bora';
    final subtitle = _usePhone
        ? 'Enviaremos um código por SMS para confirmar o número.'
        : (widget.signup ? 'Use sua conta Google ou crie com e-mail e senha.' : 'Entre com Google ou com seu e-mail e senha.');

    return StepScaffold(
      title: title,
      subtitle: subtitle,
      action: BoraButton(
        label: _usePhone ? 'Receber código' : (widget.signup ? 'Criar conta' : 'Entrar'),
        loading: _loading,
        onPressed: _continue,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (Env.googleAuthEnabled) ...[
            _SocialButton(
              label: _googleLoading ? 'Abrindo o Google…' : 'Continuar com Google',
              mark: 'G',
              onTap: _googleLoading ? () {} : _google,
            ),
            const SizedBox(height: Space.lg),
            const Row(
              children: [
                Expanded(child: Divider()),
                Padding(padding: EdgeInsets.symmetric(horizontal: Space.sm), child: Text('ou com e-mail', style: AppText.caption)),
                Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: Space.lg),
          ],
          if (Env.smsEnabled) ...[
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('E-mail'), icon: Icon(Icons.mail_outline, size: 18)),
                ButtonSegment(value: true, label: Text('Celular'), icon: Icon(Icons.phone_iphone, size: 18)),
              ],
              selected: {_usePhone},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _usePhone = s.first),
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.resolveWith(
                    (st) => st.contains(WidgetState.selected) ? AppColors.text : AppColors.surface),
                foregroundColor: WidgetStateProperty.resolveWith(
                    (st) => st.contains(WidgetState.selected) ? AppColors.night : AppColors.text),
                side: const WidgetStatePropertyAll(BorderSide.none),
              ),
            ),
            const SizedBox(height: Space.lg),
          ],
          if (!_usePhone) ...[
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              autofillHints: const [AutofillHints.email],
              textInputAction: TextInputAction.next,
              style: AppText.subtitle,
              decoration: const InputDecoration(labelText: 'E-mail', hintText: 'voce@exemplo.com', prefixIcon: Icon(Icons.mail_outline)),
            ),
            const SizedBox(height: Space.sm),
            TextField(
              controller: _password,
              obscureText: !_showPassword,
              autofillHints: [widget.signup ? AutofillHints.newPassword : AutofillHints.password],
              textInputAction: widget.signup ? TextInputAction.next : TextInputAction.done,
              onSubmitted: widget.signup ? null : (_) => _continue(),
              decoration: InputDecoration(
                labelText: widget.signup ? 'Crie uma senha' : 'Senha',
                helperText: widget.signup ? 'Pelo menos 6 caracteres' : null,
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  tooltip: _showPassword ? 'Esconder senha' : 'Mostrar senha',
                  icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _showPassword = !_showPassword),
                ),
              ),
            ),
            if (widget.signup) ...[
              const SizedBox(height: Space.sm),
              TextField(
                controller: _password2,
                obscureText: !_showPassword,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _continue(),
                decoration: const InputDecoration(labelText: 'Repita a senha', prefixIcon: Icon(Icons.lock_outline)),
              ),
            ] else
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: _forgot, child: const Text('Esqueci a senha')),
              ),
          ] else
            Row(
              children: [
                Material(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(Radii.md),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(Radii.md),
                    onTap: _pickCountry,
                    child: Container(
                      height: 58,
                      padding: const EdgeInsets.symmetric(horizontal: Space.sm),
                      alignment: Alignment.center,
                      child: Row(children: [
                        Text(_country.flag, style: const TextStyle(fontSize: 20)),
                        const SizedBox(width: 6),
                        Text('+${_country.ddi}', style: AppText.bodyStrong),
                        const Icon(Icons.arrow_drop_down, color: AppColors.textMuted),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(width: Space.xs),
                Expanded(
                  child: TextField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      if (_country.mask != null) MaskFormatter(_country.mask!) else FilteringTextInputFormatter.digitsOnly,
                    ],
                    onSubmitted: (_) => _continue(),
                    style: AppText.subtitle.copyWith(fontSize: 18, letterSpacing: .3),
                    decoration: InputDecoration(hintText: _country.ddi == '55' ? '(61) 99999-9999' : 'Número'),
                  ),
                ),
              ],
            ),
          const SizedBox(height: Space.md),
          Center(
            child: TextButton(
              onPressed: () => context.pushReplacement(widget.signup ? '/login' : '/signup'),
              child: Text(widget.signup ? 'Já tenho conta · Entrar' : 'Não tem conta? Criar conta',
                  style: const TextStyle(color: AppColors.textMuted)),
            ),
          ),
        ],
      ),
    );
  }
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({required this.label, required this.onTap, this.icon, this.mark});
  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final String? mark;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(Radii.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.md),
        onTap: onTap,
        child: SizedBox(
          height: 52,
          child: Row(
            children: [
              const SizedBox(width: Space.md),
              SizedBox(
                width: 24,
                child: icon != null
                    ? Icon(icon, color: AppColors.text, size: 22)
                    : Text(mark!, textAlign: TextAlign.center, style: AppText.title.copyWith(fontWeight: FontWeight.w800)),
              ),
              Expanded(child: Text(label, textAlign: TextAlign.center, style: AppText.bodyStrong)),
              const SizedBox(width: 24 + Space.md),
            ],
          ),
        ),
      ),
    );
  }
}
