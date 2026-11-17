import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/bora_button.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/cards.dart';
import '../../core/widgets/step_scaffold.dart';
import '../../domain/models.dart';

const communityKindLabel = {
  CommunityKind.education: 'Turma ou faculdade',
  CommunityKind.company: 'Empresa',
  CommunityKind.residential: 'Condomínio',
  CommunityKind.corridor: 'Corredor',
  CommunityKind.group: 'Grupo',
};

class CommunitiesTab extends ConsumerWidget {
  const CommunitiesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(storeProvider);
    final mine = store.myCommunities;

    return PageScaffold(
      title: 'Comunidades',
      onRefresh: store.refreshCommunities,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.page),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
                'Grupos de pessoas que já se conhecem. Quem divide uma comunidade com você aparece primeiro nas buscas.',
                style: AppText.body),
            const SizedBox(height: Space.md),
            Row(children: [
              Expanded(child: BoraButton(label: 'Entrar com código', icon: Icons.vpn_key_outlined, onPressed: () => context.push('/community/join'))),
              const SizedBox(width: Space.sm),
              Expanded(child: BoraButton(label: 'Criar', icon: Icons.add, kind: BoraButtonKind.secondary, onPressed: () => context.push('/community/new'))),
            ]),
            const SizedBox(height: Space.lg),
            if (mine.isEmpty)
              const EmptyState(
                icon: Icons.groups_outlined,
                title: 'Você ainda não está em nenhuma comunidade',
                text: 'Peça o código de convite para alguém da sua turma, empresa ou condomínio. Ou crie a primeira.',
              ),
            for (final c in mine) ...[
              BoraCard(
                onTap: c.myStatus == MemberStatus.active ? () => context.push('/community/${c.id}') : null,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(c.name,
                              style: AppText.subtitle),
                        ),
                        if (c.myStatus == MemberStatus.pending)
                          const Pill('Aguardando aprovação', color: AppColors.warning)
                        else
                          Pill(communityKindLabel[c.kind]!),
                      ],
                    ),
                    if (c.description.isNotEmpty) ...[const SizedBox(height: 8), Text(c.description)],
                    const SizedBox(height: 12),
                    Text(c.memberCount == 1 ? '1 membro' : '${c.memberCount} membros',
                        style: const TextStyle(color: AppColors.text)),
                  ],
                ),
              ),
              const SizedBox(height: Space.sm),
            ],
          ],
          ),
        ),
      ],
    );
  }
}
