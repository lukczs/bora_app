import 'package:flutter/material.dart';
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

/// Entrada no estilo Uber: logo, uma pergunta, um campo, um botão.
/// O resto (Google, e-mail) fica abaixo, com menos peso.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});
  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  final _phone = TextEditingController();
  bool _loading = false;
  bool _googleLoading = false;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (!isValidBrMobile(_phone.text)) {
      showBoraError(context, 'Digite um celular com DDD. Exemplo: (61) 99999-9999.');
      return;
    }
    final e164 = toE164Br(_phone.text);
    setState(() => _loading = true);
    try {
      await ref.read(storeProvider).sendCode(e164);
      if (mounted) context.push('/otp?phone=${Uri.encodeQueryComponent(e164)}');
    } catch (e) {
      if (mounted) showBoraError(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _google() async {
    setState(() => _googleLoading = true);
    try {
      await ref.read(storeProvider).signInWithGoogle();
    } catch (e) {
      if (mounted) showBoraError(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, c) => SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: Space.page),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: c.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: Space.lg),
                      Row(
                        children: [
                          Image.asset('assets/logo.png', width: 36, height: 36),
                          const SizedBox(width: Space.xs),
                          Text('Bora', style: AppText.title.copyWith(fontWeight: FontWeight.w800, letterSpacing: -.3)),
                        ],
                      ),
                      const SizedBox(height: Space.xxl),
                      const Text('Mesmo caminho?\nBora junto.', style: AppText.display),
                      const SizedBox(height: Space.sm),
                      const Text('Caronas entre pessoas verificadas do DF, com embarque em paradas que você já conhece.',
                          style: AppText.body),
                      const SizedBox(height: Space.xl),
                      const Text('Qual é o seu celular?', style: AppText.label),
                      const SizedBox(height: Space.xs),
                      Row(
                        children: [
                          Container(
                            height: 58,
                            padding: const EdgeInsets.symmetric(horizontal: Space.md),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(Radii.md)),
                            child: const Text('🇧🇷  +55', style: AppText.bodyStrong),
                          ),
                          const SizedBox(width: Space.xs),
                          Expanded(
                            child: TextField(
                              controller: _phone,
                              keyboardType: TextInputType.phone,
                              inputFormatters: [MaskFormatter('(##) #####-####')],
                              onSubmitted: (_) => _continue(),
                              style: AppText.subtitle.copyWith(fontSize: 18, letterSpacing: .3),
                              decoration: const InputDecoration(hintText: '(61) 99999-9999'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: Space.md),
                      BoraButton(label: 'Continuar', loading: _loading, onPressed: _continue),
                      const SizedBox(height: Space.lg),
                      const Row(
                        children: [
                          Expanded(child: Divider()),
                          Padding(padding: EdgeInsets.symmetric(horizontal: Space.sm), child: Text('ou', style: AppText.caption)),
                          Expanded(child: Divider()),
                        ],
                      ),
                      const SizedBox(height: Space.lg),
                      if (Env.googleAuthEnabled) ...[
                        BoraButton(
                          label: 'Continuar com Google',
                          kind: BoraButtonKind.secondary,
                          icon: Icons.g_mobiledata_rounded,
                          loading: _googleLoading,
                          onPressed: _google,
                        ),
                        const SizedBox(height: Space.sm),
                      ],
                      BoraButton(
                        label: 'Continuar com e-mail',
                        kind: BoraButtonKind.ghost,
                        icon: Icons.mail_outline,
                        onPressed: () => context.push('/dev-login'),
                      ),
                      const Spacer(),
                      const SizedBox(height: Space.lg),
                      const Text(
                        'Ao continuar, você concorda em receber um SMS com o código de acesso. '
                        'Seu número não é mostrado para outros usuários.',
                        style: AppText.caption,
                      ),
                      const SizedBox(height: Space.md),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
