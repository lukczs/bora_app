import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/errors.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/bora_button.dart';
import '../../core/widgets/step_scaffold.dart';

class LocationScreen extends ConsumerStatefulWidget {
  const LocationScreen({super.key});
  @override
  ConsumerState<LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends ConsumerState<LocationScreen> {
  bool _loading = false;

  Future<void> _finish({required bool ask}) async {
    setState(() => _loading = true);
    try {
      if (ask) await ref.read(storeProvider).locate(askPermission: true);
      // Concluir o cadastro muda o status, e o router leva para a Home.
      await ref.read(storeProvider).finishOnboarding();
    } catch (e) {
      if (mounted) showBoraError(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StepScaffold(
      step: 4,
      totalSteps: 4,
      title: 'Onde você está?',
      subtitle:
          'Com a sua localização o Bora sugere o ponto de embarque mais próximo e mostra a viagem para o seu contato de emergência.',
      action: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BoraButton(label: 'Permitir localização', loading: _loading, onPressed: () => _finish(ask: true)),
          TextButton(
            onPressed: _loading ? null : () => _finish(ask: false),
            child: const Text('Agora não', style: TextStyle(color: AppColors.textMuted)),
          ),
        ],
      ),
      child: const Column(
        children: [
          _Reason(Icons.place_outlined, 'Parada mais próxima',
              'Sem digitar endereço: o app já abre no ponto de embarque perto de você.'),
          _Reason(Icons.shield_outlined, 'Viagem acompanhada',
              'A posição só é compartilhada durante a carona, e só com o seu contato.'),
          _Reason(Icons.visibility_off_outlined, 'Fora da viagem, nada é rastreado',
              'O Bora não acompanha você quando não há carona em andamento.'),
        ],
      ),
    );
  }
}

class _Reason extends StatelessWidget {
  const _Reason(this.icon, this.title, this.text);
  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.green, size: 26),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(text),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
