import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/bora_button.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 210,
                height: 210,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0x2EFFFFFF),
                  border: Border.all(color: const Color(0x4DFFFFFF)),
                ),
                child: Image.asset('assets/logo.png', width: 170, height: 170),
              ),
              const SizedBox(height: 32),
              Text('Mesmo caminho? Bora junto.', style: t.headlineMedium, textAlign: TextAlign.center),
              const SizedBox(height: 14),
              Text(
                'Caronas entre moradores do DF, com pessoas verificadas e pontos de embarque que você já conhece.',
                style: t.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              BoraButton(label: 'Entrar com meu celular', onPressed: () => context.push('/phone')),
              const SizedBox(height: 12),
              BoraButton(
                label: 'Entrar com e-mail (modo dev)',
                secondary: true,
                onPressed: () => context.push('/dev-login'),
              ),
              const SizedBox(height: 12),
              const Text('O modo dev existe só enquanto o SMS não está configurado.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
