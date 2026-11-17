import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/bora_button.dart';
import '../../core/widgets/step_scaffold.dart';
import '../../data/errors.dart';

/// Verificação: casinhas do código, reenvio com contagem e troca de contato.
class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key, required this.channel, required this.to, required this.signup});

  /// 'sms' ou 'email'
  final String channel;
  final String to;
  final bool signup;

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  static const length = 6; // o Supabase envia 6 dígitos (é o mínimo dele)
  final _code = TextEditingController();
  final _focus = FocusNode();
  bool _loading = false;
  int _wait = 60;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _wait = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_wait <= 1) t.cancel();
      if (mounted) setState(() => _wait--);
    });
  }

  Future<void> _verify() async {
    if (_loading || _code.text.length != length) return;
    setState(() => _loading = true);
    try {
      final store = ref.read(storeProvider);
      if (widget.channel == 'email') {
        await store.verifyEmailCode(email: widget.to, code: _code.text);
      } else {
        await store.verifyCode(phoneE164: widget.to, code: _code.text);
      }
      // A sessão muda e o router leva para o cadastro ou para o início.
    } catch (e) {
      if (mounted) {
        _code.clear();
        setState(() {});
        showBoraError(context, friendlyError(e));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    try {
      final store = ref.read(storeProvider);
      if (widget.channel == 'email') {
        await store.sendEmailCode(widget.to, create: widget.signup);
      } else {
        await store.sendCode(widget.to, create: widget.signup);
      }
      _startTimer();
      if (mounted) showBoraError(context, 'Código reenviado.');
    } catch (e) {
      if (mounted) showBoraError(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final via = widget.channel == 'email' ? 'por e-mail para' : 'por SMS para';
    return StepScaffold(
      title: 'Digite o código',
      subtitle: 'Enviamos $length dígitos $via ${widget.to}.',
      action: BoraButton(
        label: 'Confirmar',
        loading: _loading,
        onPressed: _code.text.length == length ? _verify : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => _focus.requestFocus(),
            child: Stack(
              children: [
                // Campo invisível que recebe o teclado (e o preenchimento automático do SMS).
                Opacity(
                  opacity: 0,
                  child: SizedBox(
                    height: 60,
                    child: TextField(
                      controller: _code,
                      focusNode: _focus,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      autofillHints: const [AutofillHints.oneTimeCode],
                      maxLength: length,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: (v) {
                        setState(() {});
                        if (v.length == length) _verify();
                      },
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (var i = 0; i < length; i++) ...[
                      Expanded(child: _Box(char: i < _code.text.length ? _code.text[i] : '', active: i == _code.text.length)),
                      if (i < length - 1) const SizedBox(width: Space.xs),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.lg),
          Row(
            children: [
              Expanded(
                child: _wait > 0
                    ? Text('Reenviar código em 0:${_wait.toString().padLeft(2, '0')}', style: AppText.label)
                    : TextButton(
                        style: TextButton.styleFrom(padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
                        onPressed: _resend,
                        child: const Text('Reenviar código'),
                      ),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(widget.channel == 'email' ? 'Trocar e-mail' : 'Trocar número',
                    style: const TextStyle(color: AppColors.textMuted)),
              ),
            ],
          ),
          if (widget.channel == 'email') ...[
            const SizedBox(height: Space.sm),
            const Text('Não achou? Olhe também a caixa de spam.', style: AppText.caption),
          ],
        ],
      ),
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({required this.char, required this.active});
  final String char;
  final bool active;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: 60,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: active ? AppColors.green : Colors.transparent, width: 1.5),
        ),
        child: Text(char, style: AppText.headline),
      );
}
