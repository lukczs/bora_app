import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/cards.dart';
import '../../core/widgets/step_scaffold.dart';
import '../../domain/models.dart';

/// Perfil no padrão de conta do Uber: cabeçalho com nome e selos, seções em lista.
class ProfileTab extends ConsumerWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(storeProvider);
    final me = store.me;
    if (me == null) return const SizedBox.shrink();
    final contact = me.emergencyContact;
    final initial = (me.fullName ?? '?').trim().isEmpty ? '?' : me.fullName!.trim()[0].toUpperCase();

    return PageScaffold(
      title: 'Conta',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.page, Space.sm, Space.page, Space.md),
          child: Row(
            children: [
              Avatar(initial, size: 60),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(me.fullName ?? '', style: AppText.title),
                    const SizedBox(height: Space.xxs),
                    Wrap(spacing: Space.xs, runSpacing: Space.xxs, children: [
                      switch (me.identityStatus) {
                        VerificationStatus.approved => const Pill('Verificado', icon: Icons.verified_user_outlined),
                        VerificationStatus.pending || VerificationStatus.inReview =>
                          const Pill('Em verificação', icon: Icons.hourglass_top, color: AppColors.warning),
                        VerificationStatus.rejected => const Pill('Recusado', icon: Icons.error_outline, color: AppColors.danger),
                      },
                      if (me.ratingCount > 0)
                        Pill(me.ratingAvg.toStringAsFixed(1).replaceAll('.', ','), icon: Icons.star_rounded, color: AppColors.warning),
                    ]),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SectionHeader('Segurança'),
        ListRow(
          icon: Icons.emergency_outlined,
          title: 'Contato de emergência',
          subtitle: contact == null ? 'Nenhum contato cadastrado' : '${contact.name} · ${contact.relation}',
          onTap: () => context.push('/onboarding/emergency'),
        ),
        if (me.womenOnlyPref)
          const ListRow(icon: Icons.female, title: 'Viajo só com mulheres', subtitle: 'Só aparecem motoristas mulheres'),
        const SectionHeader('Carros'),
        for (final v in store.myVehicles)
          ListRow(
            icon: Icons.directions_car_outlined,
            title: v.label,
            subtitle: 'Placa ${v.plate} · ${v.seats} ${v.seats == 1 ? 'vaga' : 'vagas'}',
            onTap: () => context.push('/vehicle?id=${v.id}'),
          ),
        ListRow(
          icon: Icons.add,
          title: 'Cadastrar carro',
          trailing: const SizedBox.shrink(),
          onTap: () => context.push('/vehicle'),
        ),
        const SectionHeader('App'),
        ListRow(
          icon: Icons.info_outline,
          title: 'Sobre o Bora',
          subtitle: 'Carona solidária no DF · mapas © OpenStreetMap',
          trailing: const SizedBox.shrink(),
          onTap: () => showAboutDialog(context: context, applicationName: 'Bora', applicationVersion: '0.3'),
        ),
        ListRow(icon: Icons.logout, title: 'Sair da conta', danger: true, trailing: const SizedBox.shrink(), onTap: store.signOut),
      ],
    );
  }
}
