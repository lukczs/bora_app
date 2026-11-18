import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show OAuthProvider;

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

/// Criar conta ou entrar: celular (com DDI) ou e-mail, e login social.
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
  Country _country = countries.first;
  bool _useEmail = false;

  /// No e-mail, o padrão é senha (funciona sem configurar nada no Supabase).
  /// O código por e-mail fica como opção.
  bool _emailCode = false;
  bool _showPassword = false;
  bool _loading = false;

  @override
  void dispose() {
    _phone.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    final store = ref.read(storeProvider);
    String channel, to;
    if (_useEmail) {
      to = _email.text.trim().toLowerCase();
      if (!RegExp(r'^[^@\s]+@[^@\s]+\.[a-z]{2,}$').hasMatch(to)) {
        showBoraError(context, 'Digite um e-mail válido.');
        return;
      }
      channel = 'email';
      if (!_emailCode) {
        final pass = _password.text;
        if (widget.signup &&
            (pass.length < 8 || !RegExp(r'\d').hasMatch(pass) || !RegExp(r'[A-Za-z]').hasMatch(pass))) {
          showBoraError(context, 'A senha precisa ter 8 caracteres ou mais, com letras e números.');
          return;
        }
        if (pass.isEmpty) {
          showBoraError(context, 'Digite a senha.');
          return;
        }
        setState(() => _loading = true);
        try {
          await store.devEmailSignIn(email: to, password: pass, create: widget.signup);
          // A sessão muda e o router leva para o cadastro ou para o início.
        } catch (e) {
          if (mounted) showBoraError(context, friendlyError(e));
        } finally {
          if (mounted) setState(() => _loading = false);
        }
        return;
      }
    } else {
      final digits = onlyDigits(_phone.text);
      if (digits.length < _country.minDigits) {
        showBoraError(context, 'Confira o número com DDD.');
        return;
      }
      to = '+${_country.ddi}$digits';
      channel = 'sms';
    }
    setState(() => _loading = true);
    try {
      if (channel == 'email') {
        await store.sendEmailCode(to, create: widget.signup);
      } else {
        await store.sendCode(to, create: widget.signup);
      }
      if (mounted) {
        context.push('/verify?channel=$channel&to=${Uri.encodeQueryComponent(to)}&signup=${widget.signup}');
      }
    } catch (e) {
      if (mounted) showBoraError(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _social(OAuthProvider p, bool enabled, String name) async {
    if (!enabled) {
      showBoraError(context, 'Entrar com $name ainda não foi ativado neste app.');
      return;
    }
    try {
      await ref.read(storeProvider).signInWithProvider(p);
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
    final subtitle = _useEmail
        ? (_emailCode
            ? 'Enviaremos um código para o seu e-mail.'
            : (widget.signup ? 'Use seu e-mail e crie uma senha.' : 'Entre com seu e-mail e senha.'))
        : 'Enviaremos um código por SMS para confirmar o número.';

    return StepScaffold(
      title: title,
      subtitle: subtitle,
      action: BoraButton(label: 'Continuar', loading: _loading, onPressed: _continue),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Celular | E-mail
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Celular'), icon: Icon(Icons.phone_iphone, size: 18)),
              ButtonSegment(value: true, label: Text('E-mail'), icon: Icon(Icons.mail_outline, size: 18)),
            ],
            selected: {_useEmail},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _useEmail = s.first),
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.resolveWith(
                  (st) => st.contains(WidgetState.selected) ? AppColors.text : AppColors.surface),
              foregroundColor: WidgetStateProperty.resolveWith(
                  (st) => st.contains(WidgetState.selected) ? AppColors.night : AppColors.text),
              side: const WidgetStatePropertyAll(BorderSide.none),
            ),
          ),
          const SizedBox(height: Space.lg),
          if (_useEmail) ...[
            TextField(
              controller: _email,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              autofillHints: const [AutofillHints.email],
              textInputAction: _emailCode ? TextInputAction.done : TextInputAction.next,
              onSubmitted: (_) => _emailCode ? _continue() : null,
              style: AppText.subtitle,
              decoration: const InputDecoration(labelText: 'E-mail', hintText: 'voce@exemplo.com'),
            ),
            if (!_emailCode) ...[
              const SizedBox(height: Space.sm),
              TextField(
                controller: _password,
                obscureText: !_showPassword,
                autofillHints: [widget.signup ? AutofillHints.newPassword : AutofillHints.password],
                onSubmitted: (_) => _continue(),
                decoration: InputDecoration(
                  labelText: widget.signup ? 'Crie uma senha' : 'Senha',
                  helperText: widget.signup ? '8 caracteres ou mais, com letras e números.' : null,
                  suffixIcon: IconButton(
                    icon: Icon(_showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                    onPressed: () => setState(() => _showPassword = !_showPassword),
                  ),
                ),
              ),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                onPressed: () => setState(() => _emailCode = !_emailCode),
                child: Text(_emailCode ? 'Prefiro usar senha' : 'Prefiro receber um código'),
              ),
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
                    autofocus: true,
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
          const SizedBox(height: Space.lg),
          const Row(
            children: [
              Expanded(child: Divider()),
              Padding(padding: EdgeInsets.symmetric(horizontal: Space.sm), child: Text('ou', style: AppText.caption)),
              Expanded(child: Divider()),
            ],
          ),
          const SizedBox(height: Space.lg),
          _SocialButton(
            label: 'Continuar com Google',
            mark: 'G',
            onTap: () => _social(OAuthProvider.google, Env.googleAuthEnabled, 'Google'),
          ),
          const SizedBox(height: Space.xs),
          _SocialButton(
            label: 'Continuar com Apple',
            icon: Icons.apple,
            onTap: () => _social(OAuthProvider.apple, Env.appleAuthEnabled, 'Apple'),
          ),
          const SizedBox(height: Space.xs),
          _SocialButton(
            label: 'Continuar com Facebook',
            icon: Icons.facebook,
            onTap: () => _social(OAuthProvider.facebook, Env.facebookAuthEnabled, 'Facebook'),
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
