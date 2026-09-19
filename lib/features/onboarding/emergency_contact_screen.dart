import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../data/errors.dart';
import '../../core/utils/masks.dart';
import '../../core/utils/validators.dart';
import '../../core/widgets/bora_button.dart';
import '../../core/widgets/step_scaffold.dart';
import '../../domain/models.dart';

class EmergencyContactScreen extends ConsumerStatefulWidget {
  const EmergencyContactScreen({super.key});
  @override
  ConsumerState<EmergencyContactScreen> createState() => _EmergencyContactScreenState();
}

class _EmergencyContactScreenState extends ConsumerState<EmergencyContactScreen> {
  static const _relations = ['Mãe', 'Pai', 'Irmã ou irmão', 'Cônjuge', 'Amiga ou amigo', 'Outro'];

  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  String? _relation;
  bool _loading = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await ref.read(storeProvider).saveEmergencyContact(
            EmergencyContact(
                name: _name.text.trim(), phone: toE164Br(_phone.text), relation: _relation!),
          );
      if (mounted) context.push('/onboarding/document');
    } catch (e) {
      if (mounted) showBoraError(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StepScaffold(
      step: 2,
      totalSteps: 4,
      title: 'Contato de emergência',
      subtitle:
          'Sempre que uma carona começar, essa pessoa recebe um link para acompanhar sua viagem em tempo real.',
      action: BoraButton(label: 'Salvar contato', loading: _loading, onPressed: _save),
      child: Form(
        key: _form,
        child: Column(
          children: [
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nome do contato'),
              validator: (v) => (v ?? '').trim().length < 2 ? 'Digite o nome do contato.' : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              inputFormatters: [MaskFormatter('(##) #####-####')],
              decoration:
                  const InputDecoration(labelText: 'Celular do contato', hintText: '(61) 99999-9999'),
              validator: (v) => isValidBrMobile(v ?? '') ? null : 'Digite um celular com DDD.',
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              value: _relation,
              decoration: const InputDecoration(labelText: 'Quem é essa pessoa para você'),
              items: [for (final r in _relations) DropdownMenuItem(value: r, child: Text(r))],
              onChanged: (v) => setState(() => _relation = v),
              validator: (v) => v == null ? 'Selecione uma opção.' : null,
            ),
          ],
        ),
      ),
    );
  }
}
