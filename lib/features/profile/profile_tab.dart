import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/bora_button.dart';
import '../../core/widgets/cards.dart';
import '../../domain/models.dart';

/// Resumo do perfil, carros e sair.
class ProfileTab extends ConsumerWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(storeProvider);
    final me = store.me;
    if (me == null) return const SizedBox.shrink();
    final vehicles = store.myVehicles;
    final contact = me.emergencyContact;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        children: [
          Text(me.fullName ?? '', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              switch (me.identityStatus) {
                VerificationStatus.approved => const Pill('Identidade verificada', icon: Icons.verified_user),
                VerificationStatus.pending || VerificationStatus.inReview =>
                  const Pill('Em verificação', icon: Icons.hourglass_top, color: AppColors.warning),
                VerificationStatus.rejected =>
                  const Pill('Verificação recusada', icon: Icons.error_outline, color: AppColors.danger),
              },
              if (me.ratingCount > 0)
                Pill('Nota ${me.ratingAvg.toStringAsFixed(1).replaceAll('.', ',')} em ${me.ratingCount} viagens',
                    icon: Icons.star, color: AppColors.warning),
              if (me.womenOnlyPref)
                const Pill('Viaja só com mulheres', icon: Icons.female, color: Color(0xFFF0ABFC)),
            ],
          ),
          const SizedBox(height: 24),
          Text('Contato de emergência', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          BoraCard(
            child: contact == null
                ? const Text('Nenhum contato cadastrado.')
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${contact.name} (${contact.relation})',
                          style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(contact.phone),
                    ],
                  ),
          ),
          const SizedBox(height: 24),
          Text('Meus carros', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          for (final v in vehicles) ...[
            BoraCard(
              onTap: () => context.push('/vehicle?id=${v.id}'),
              child: Row(
                children: [
                  const Icon(Icons.directions_car, color: AppColors.green),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(v.label,
                            style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w700)),
                        Text('Placa ${v.plate}, ${v.seats} vagas'),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: AppColors.textMuted),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          BoraButton(label: 'Cadastrar carro', secondary: true, onPressed: () => context.push('/vehicle')),
          const SizedBox(height: 28),
          BoraButton(
            label: 'Sair da conta',
            secondary: true,
            onPressed: store.signOut,
          ),
        ],
      ),
    );
  }
}
