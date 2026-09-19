import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/widgets/bora_button.dart';
import '../../core/widgets/step_scaffold.dart';
import '../../data/errors.dart';

/// Entrada por e-mail e senha, só para desenvolvimento: funciona num projeto
/// Supabase recém-criado, sem configurar provedor de SMS. Remover antes de lançar.
class DevLoginScreen extends ConsumerStatefulWidget {
  const DevLoginScreen({super.key});
  @override
  ConsumerState<DevLoginScreen> createState() => _DevLoginScreenState();
}

class _DevLoginScreenState extends ConsumerState<DevLoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _go({required bool create}) async {
    if (!_email.text.contains('@') || _password.text.length < 6) {
      showBoraError(context, 'Digite um e-mail e uma senha com pelo menos 6 caracteres.');
      return;
    }
    setState(() => _loading = true);
    try {
      await ref
          .read(storeProvider)
          .devEmailSignIn(email: _email.text.trim(), password: _password.text, create: create);
    } catch (e) {
      if (mounted) showBoraError(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StepScaffold(
      title: 'Entrar com e-mail',
      subtitle: 'Modo de desenvolvimento. Crie quantas contas quiser para testar motorista e passageiro.',
      action: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BoraButton(label: 'Entrar', loading: _loading, onPressed: () => _go(create: false)),
          const SizedBox(height: 12),
          BoraButton(
              label: 'Criar conta de teste', secondary: true, onPressed: _loading ? null : () => _go(create: true)),
        ],
      ),
      child: Column(
        children: [
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'E-mail', hintText: 'ana@teste.com'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Senha'),
          ),
        ],
      ),
    );
  }
}
