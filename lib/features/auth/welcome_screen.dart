import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/bora_button.dart';

/// Primeira tela: marca, uma frase e as duas portas de entrada.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.page),
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
              const Spacer(),
              const Text('Mesmo caminho?\nBora junto.', style: AppText.display),
              const SizedBox(height: Space.sm),
              const Text(
                'Caronas entre pessoas verificadas do DF, com embarque em paradas que você já conhece.',
                style: AppText.body,
              ),
              const SizedBox(height: Space.xl),
              BoraButton(label: 'Criar conta', onPressed: () => context.push('/signup')),
              const SizedBox(height: Space.sm),
              BoraButton(label: 'Entrar', kind: BoraButtonKind.ghost, onPressed: () => context.push('/login')),
              const SizedBox(height: Space.lg),
              const Text(
                'Rateio de custo entre pessoas, sem lucro para o motorista.',
                style: AppText.caption,
              ),
              const SizedBox(height: Space.md),
            ],
          ),
        ),
      ),
    );
  }
}
