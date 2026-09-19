import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../data/errors.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/masks.dart';
import '../../core/utils/validators.dart';
import '../../core/widgets/bora_button.dart';
import '../../core/widgets/step_scaffold.dart';
import '../../domain/models.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});
  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _cpf = TextEditingController();
  final _birth = TextEditingController();
  Gender? _gender;
  bool _womenOnly = false;
  bool _loading = false;

  @override
  void dispose() {
    _name.dispose();
    _cpf.dispose();
    _birth.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_gender == null) {
      showBoraError(context, 'Selecione uma opção em "Como você se identifica".');
      return;
    }
    setState(() => _loading = true);
    try {
      await ref.read(storeProvider).submitRegistration(
            fullName: _name.text.trim(),
            cpfDigits: onlyDigits(_cpf.text),
            birthDate: parseBrDate(_birth.text)!,
            gender: _gender!,
            womenOnlyPref: _womenOnly,
          );
      if (mounted) context.push('/onboarding/emergency');
    } catch (e) {
      if (mounted) showBoraError(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StepScaffold(
      step: 1,
      totalSteps: 4,
      canGoBack: false,
      title: 'Quem é você?',
      subtitle: 'Seus dados passam por verificação. CPF e telefone nunca aparecem para outras pessoas.',
      action: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BoraButton(label: 'Salvar e continuar', loading: _loading, onPressed: _save),
          TextButton(
            onPressed: () => ref.read(storeProvider).signOut(),
            child: const Text('Sair desta conta', style: TextStyle(color: AppColors.textMuted)),
          ),
        ],
      ),
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nome completo'),
              validator: (v) => (v ?? '').trim().split(RegExp(r'\s+')).length < 2
                  ? 'Digite nome e sobrenome, como no documento.'
                  : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _cpf,
              keyboardType: TextInputType.number,
              inputFormatters: [MaskFormatter('###.###.###-##')],
              decoration: const InputDecoration(labelText: 'CPF', hintText: '000.000.000-00'),
              validator: (v) => isValidCpf(v ?? '') ? null : 'CPF inválido. Confira os números.',
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _birth,
              keyboardType: TextInputType.number,
              inputFormatters: [MaskFormatter('##/##/####')],
              decoration: const InputDecoration(labelText: 'Data de nascimento', hintText: 'dd/mm/aaaa'),
              validator: (v) {
                final d = parseBrDate(v ?? '');
                if (d == null) return 'Data inválida. Use dd/mm/aaaa.';
                if (!isAdult(d)) return 'É preciso ter 18 anos ou mais para usar o Bora.';
                return null;
              },
            ),
            const SizedBox(height: 22),
            const Text('Como você se identifica',
                style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              children: [
                for (final (g, label) in const [
                  (Gender.female, 'Mulher'),
                  (Gender.male, 'Homem'),
                  (Gender.other, 'Outro'),
                ])
                  ChoiceChip(
                    label: Text(label),
                    selected: _gender == g,
                    onSelected: (_) => setState(() => _gender = g),
                    selectedColor: const Color(0x3322C55E),
                    backgroundColor: AppColors.surface,
                    side: BorderSide(color: _gender == g ? AppColors.green : AppColors.line),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            const Text('Essa informação é conferida na verificação de identidade.'),
            if (_gender == Gender.female) ...[
              const SizedBox(height: 18),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _womenOnly,
                onChanged: (v) => setState(() => _womenOnly = v),
                title: const Text('Viajar só com mulheres',
                    style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w600)),
                subtitle:
                    const Text('Como passageira, você só verá motoristas mulheres. Dá para mudar depois.'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
