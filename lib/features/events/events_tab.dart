import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/bora_button.dart';
import '../../core/widgets/cards.dart';
import '../../core/widgets/step_scaffold.dart';
import '../../data/errors.dart';
import '../../domain/models.dart';
import 'event_widgets.dart';

/// Aba Eventos: o que vem por aí, criar evento e entrar por código.
class EventsTab extends ConsumerStatefulWidget {
  const EventsTab({super.key});
  @override
  ConsumerState<EventsTab> createState() => _EventsTabState();
}

class _EventsTabState extends ConsumerState<EventsTab> {
  List<BoraEvent>? _events;
  String? _error;
  String _kind = 'todos';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final e = await ref.read(storeProvider).upcomingEvents();
      if (mounted) {
        setState(() {
          _events = e;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _open(String id) async {
    await context.push('/event/$id');
    _load();
  }

  Future<void> _byCode() async {
    final code = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Código do evento'),
        content: TextField(
          controller: code,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(hintText: 'Ex.: 7F3A2C'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(d).pop(false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.of(d).pop(true), child: const Text('Abrir')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final e = await ref.read(storeProvider).eventByCode(code.text);
      if (!mounted) return;
      if (e == null) {
        showBoraError(context, 'Nenhum evento com esse código.');
      } else {
        _open(e.id);
      }
    } catch (err) {
      if (mounted) showBoraError(context, friendlyError(err));
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = _events;
    final list = all == null ? null : (_kind == 'todos' ? all : all.where((e) => e.kind == _kind).toList());
    final thisWeek = list?.where((e) => e.startsAt.isBefore(DateTime.now().add(const Duration(days: 7)))).toList() ?? [];
    final later = list?.where((e) => !e.startsAt.isBefore(DateTime.now().add(const Duration(days: 7)))).toList() ?? [];

    return PageScaffold(
      title: 'Eventos',
      onRefresh: _load,
      actions: [
        IconButton(tooltip: 'Tenho um código', icon: const Icon(Icons.qr_code_2), onPressed: _byCode),
      ],
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: Space.page),
          child: Text('Jogos, shows e festas com carona combinada. Reserve a vaga dias antes.', style: AppText.body),
        ),
        const SizedBox(height: Space.md),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.page),
          child: BoraButton(
            label: 'Criar evento',
            icon: Icons.add,
            onPressed: () async {
              final id = await context.push<String>('/event/new');
              if (id != null) {
                _open(id);
              } else {
                _load();
              }
            },
          ),
        ),
        const SizedBox(height: Space.md),
        SizedBox(
          height: 38,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Space.page),
            children: [
              for (final k in ['todos', ...eventKinds.keys])
                Padding(
                  padding: const EdgeInsets.only(right: Space.xs),
                  child: ChoiceChip(
                    label: Text(k == 'todos' ? 'Todos' : eventKinds[k]!.$1),
                    selected: _kind == k,
                    labelStyle: AppText.label.copyWith(color: _kind == k ? AppColors.night : AppColors.text),
                    onSelected: (_) => setState(() => _kind = k),
                  ),
                ),
            ],
          ),
        ),
        if (_error != null)
          Padding(padding: const EdgeInsets.all(Space.page), child: Text(_error!, style: AppText.body))
        else if (list == null)
          const Padding(padding: EdgeInsets.all(Space.xl), child: Center(child: CircularProgressIndicator()))
        else if (list.isEmpty)
          const EmptyState(
            icon: Icons.local_activity_outlined,
            title: 'Nenhum evento por enquanto',
            text: 'Vai a um jogo, show ou festa? Crie o evento e chame a galera para dividir a carona.',
          )
        else ...[
          if (thisWeek.isNotEmpty) const SectionHeader('Esta semana'),
          for (final e in thisWeek)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.page, 0, Space.page, Space.xs),
              child: EventCard(event: e, onTap: () => _open(e.id)),
            ),
          if (later.isNotEmpty) const SectionHeader('Mais pra frente'),
          for (final e in later)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.page, 0, Space.page, Space.xs),
              child: EventCard(event: e, onTap: () => _open(e.id)),
            ),
        ],
      ],
    );
  }
}
