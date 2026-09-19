import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/bora_button.dart';
import '../../core/widgets/cards.dart';
import '../../core/widgets/step_scaffold.dart';
import '../../data/errors.dart';
import '../../domain/models.dart';
import 'communities_tab.dart';

// =====================================================================
// Entrar por código
// =====================================================================
class JoinCommunityScreen extends ConsumerStatefulWidget {
  const JoinCommunityScreen({super.key});
  @override
  ConsumerState<JoinCommunityScreen> createState() => _JoinCommunityScreenState();
}

class _JoinCommunityScreenState extends ConsumerState<JoinCommunityScreen> {
  final _code = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    if (_code.text.trim().length < 4) {
      showBoraError(context, 'Digite o código de convite completo.');
      return;
    }
    setState(() => _loading = true);
    try {
      final joined = await ref.read(storeProvider).joinCommunity(_code.text);
      if (!mounted) return;
      showBoraError(
          context, joined ? 'Você entrou na comunidade.' : 'Pedido enviado. Um administrador precisa aprovar sua entrada.');
      context.pop();
    } catch (e) {
      if (mounted) showBoraError(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StepScaffold(
      title: 'Entrar em uma comunidade',
      subtitle: 'O código tem 8 letras e números. Quem já participa encontra o código na tela da comunidade.',
      action: BoraButton(label: 'Entrar na comunidade', loading: _loading, onPressed: _join),
      child: TextField(
        controller: _code,
        autofocus: true,
        textCapitalization: TextCapitalization.characters,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
          LengthLimitingTextInputFormatter(8),
        ],
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 26, letterSpacing: 6, fontWeight: FontWeight.w700),
        decoration: const InputDecoration(hintText: 'A1B2C3D4'),
        onSubmitted: (_) => _join(),
      ),
    );
  }
}

// =====================================================================
// Criar
// =====================================================================
class CreateCommunityScreen extends ConsumerStatefulWidget {
  const CreateCommunityScreen({super.key});
  @override
  ConsumerState<CreateCommunityScreen> createState() => _CreateCommunityScreenState();
}

class _CreateCommunityScreenState extends ConsumerState<CreateCommunityScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();
  CommunityKind _kind = CommunityKind.group;
  bool _needsApproval = false;
  String? _anchor;
  bool _loading = false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await ref.read(storeProvider).createCommunity(
            name: _name.text.trim(),
            description: _description.text.trim(),
            kind: _kind,
            joinMode: _needsApproval ? CommunityJoinMode.approval : CommunityJoinMode.inviteCode,
            anchorStopId: _anchor,
          );
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) showBoraError(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stops = ref.watch(storeProvider).graph.boardable;
    return StepScaffold(
      title: 'Criar comunidade',
      subtitle: 'Cada pessoa pode criar até 3. Poucas comunidades grandes funcionam melhor que muitas pequenas.',
      action: BoraButton(label: 'Criar comunidade', loading: _loading, onPressed: _create),
      child: Form(
        key: _form,
        child: Column(
          children: [
            TextFormField(
              controller: _name,
              maxLength: 60,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nome', hintText: 'Turma ADS Noite', counterText: ''),
              validator: (v) => (v ?? '').trim().length < 3 ? 'O nome precisa de pelo menos 3 letras.' : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _description,
              maxLines: 2,
              maxLength: 160,
              decoration: const InputDecoration(labelText: 'Para quem é (opcional)', counterText: ''),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<CommunityKind>(
              value: _kind,
              decoration: const InputDecoration(labelText: 'Tipo'),
              items: [
                for (final k in CommunityKind.values)
                  DropdownMenuItem(value: k, child: Text(communityKindLabel[k]!)),
              ],
              onChanged: (v) => setState(() => _kind = v ?? CommunityKind.group),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String?>(
              value: _anchor,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Ponto em comum (opcional)'),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Nenhum')),
                for (final s in stops)
                  DropdownMenuItem<String?>(value: s.id, child: Text(s.name, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => _anchor = v),
            ),
            const SizedBox(height: 6),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _needsApproval,
              onChanged: (v) => setState(() => _needsApproval = v),
              title: const Text('Aprovar cada entrada',
                  style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w600)),
              subtitle: const Text('Desligado: quem tiver o código entra na hora.'),
            ),
          ],
        ),
      ),
    );
  }
}

// =====================================================================
// Detalhe: código, membros, aprovar, remover, sair
// =====================================================================
class CommunityDetailScreen extends ConsumerStatefulWidget {
  const CommunityDetailScreen({super.key, required this.communityId});
  final String communityId;
  @override
  ConsumerState<CommunityDetailScreen> createState() => _CommunityDetailScreenState();
}

class _CommunityDetailScreenState extends ConsumerState<CommunityDetailScreen> {
  List<CommunityMemberView>? _members;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final members = await ref.read(storeProvider).communityMembers(widget.communityId);
      if (mounted) setState(() => _members = members);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _setStatus(String userId, MemberStatus status) async {
    try {
      await ref.read(storeProvider).setMemberStatus(widget.communityId, userId, status);
      await _load();
    } catch (e) {
      if (mounted) showBoraError(context, friendlyError(e));
    }
  }

  Future<void> _leave() async {
    try {
      await ref.read(storeProvider).leaveCommunity(widget.communityId);
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) showBoraError(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(storeProvider);
    final c = store.myCommunities.where((x) => x.id == widget.communityId).firstOrNull;
    if (c == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('Comunidade não encontrada.')));
    }
    final me = store.me!;

    return Scaffold(
      appBar: AppBar(title: Text(c.name)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        children: [
          Pill(communityKindLabel[c.kind]!),
          if (c.description.isNotEmpty) ...[const SizedBox(height: 12), Text(c.description)],
          if (c.anchorStopId != null) ...[
            const SizedBox(height: 8),
            Text('Ponto em comum: ${store.stop(c.anchorStopId!).name}', style: const TextStyle(color: AppColors.text)),
          ],
          const SizedBox(height: 20),
          BoraCard(
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: c.inviteCode));
              if (context.mounted) showBoraError(context, 'Código copiado. Mande para quem você quer convidar.');
            },
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Código de convite'),
                      const SizedBox(height: 4),
                      Text(c.inviteCode,
                          style: const TextStyle(
                              color: AppColors.mint, fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: 4)),
                    ],
                  ),
                ),
                const Icon(Icons.copy, color: AppColors.green),
              ],
            ),
          ),
          const SizedBox(height: 26),
          Text('Membros', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          if (_error != null) Text(_error!),
          if (_members == null && _error == null)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator(color: AppColors.green)),
            ),
          for (final m in _members ?? const <CommunityMemberView>[]) ...[
            BoraCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: const Color(0x3322C55E),
                    child: Text(m.person.initial,
                        style: const TextStyle(color: AppColors.mint, fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(m.person.fullName,
                            style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w700)),
                        Text(switch ((m.status, m.role)) {
                          (MemberStatus.pending, _) => 'Pediu para entrar',
                          (_, MemberRole.owner) => 'Criou a comunidade',
                          (_, MemberRole.admin) => 'Administra',
                          _ => m.person.ratingLabel,
                        }),
                      ],
                    ),
                  ),
                  if (c.iAmAdmin && m.person.id != me.id && m.role != MemberRole.owner) ...[
                    if (m.status == MemberStatus.pending)
                      IconButton(
                        tooltip: 'Aprovar entrada',
                        icon: const Icon(Icons.check_circle, color: AppColors.green),
                        onPressed: () => _setStatus(m.person.id, MemberStatus.active),
                      ),
                    IconButton(
                      tooltip: 'Remover da comunidade',
                      icon: const Icon(Icons.person_remove_outlined, color: AppColors.danger),
                      onPressed: () => _setStatus(m.person.id, MemberStatus.banned),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 16),
          if (c.myRole != MemberRole.owner)
            BoraButton(label: 'Sair da comunidade', secondary: true, onPressed: _leave),
        ],
      ),
    );
  }
}
