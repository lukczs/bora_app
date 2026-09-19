import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/errors.dart';
import '../../core/widgets/bora_button.dart';
import '../../core/widgets/step_scaffold.dart';

class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key, required this.phoneE164});
  final String phoneE164;
  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final _code = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await ref.read(storeProvider).verifyCode(phoneE164: widget.phoneE164, code: _code.text);
      // Nada de navegar aqui: a sessão muda e o router redireciona sozinho.
    } catch (e) {
      if (mounted) {
        _code.clear();
        showBoraError(context, friendlyError(e));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StepScaffold(
      title: 'Digite o código',
      subtitle: 'Enviamos 6 dígitos por SMS para ${widget.phoneE164}.',
      action: BoraButton(label: 'Confirmar código', loading: _loading, onPressed: _verify),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _code,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 30, letterSpacing: 14, fontWeight: FontWeight.w700),
            decoration: const InputDecoration(counterText: '', hintText: '000000'),
            onChanged: (v) {
              if (v.length == 6) _verify();
            },
          ),
          const SizedBox(height: 16),
          const Text('Não chegou? Volte e confira o número. Números de teste usam o código fixo cadastrado no painel do Supabase.'),
        ],
      ),
    );
  }
}
