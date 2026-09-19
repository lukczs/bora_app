import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/bora_button.dart';
import '../../core/widgets/cards.dart';
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

    return SafeArea(
      child: RefreshIndicator(
        color: AppColors.green,
        onRefresh: store.refreshCommunities,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          children: [
            Text('Comunidades', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 8),
            const Text(
                'Grupos de pessoas que já se conhecem. Quem divide uma comunidade com você aparece primeiro nas buscas.'),
            const SizedBox(height: 20),
            BoraButton(label: 'Entrar com código de convite', onPressed: () => context.push('/community/join')),
            const SizedBox(height: 12),
            BoraButton(label: 'Criar comunidade', secondary: true, onPressed: () => context.push('/community/new')),
            const SizedBox(height: 24),
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
                              style: const TextStyle(color: AppColors.text, fontSize: 17, fontWeight: FontWeight.w800)),
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
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}
