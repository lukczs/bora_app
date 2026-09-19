import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../data/errors.dart';
import '../../core/utils/masks.dart';
import '../../core/utils/validators.dart';
import '../../core/widgets/bora_button.dart';
import '../../core/widgets/step_scaffold.dart';

class PhoneScreen extends ConsumerStatefulWidget {
  const PhoneScreen({super.key});
  @override
  ConsumerState<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends ConsumerState<PhoneScreen> {
  final _phone = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _send() async {
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

  @override
  Widget build(BuildContext context) {
    return StepScaffold(
      title: 'Qual é o seu celular?',
      subtitle: 'Vamos enviar um código por SMS. Serve tanto para criar sua conta quanto para entrar nela.',
      action: BoraButton(label: 'Enviar código', loading: _loading, onPressed: _send),
      child: TextField(
        controller: _phone,
        autofocus: true,
        keyboardType: TextInputType.phone,
        inputFormatters: [MaskFormatter('(##) #####-####')],
        onSubmitted: (_) => _send(),
        style: const TextStyle(fontSize: 20, letterSpacing: .5),
        decoration: const InputDecoration(labelText: 'Celular com DDD', hintText: '(61) 99999-9999'),
      ),
    );
  }
}
