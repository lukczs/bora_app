import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/bora_button.dart';
import '../../core/widgets/cards.dart';
import '../../core/widgets/step_scaffold.dart';
import '../../data/errors.dart';
import '../../domain/models.dart';
import '../places/place_picker.dart';
import 'event_widgets.dart';

/// Criar evento. Antes de salvar, procura evento parecido (mesmo lugar e dia)
/// para não duplicar. Devolve o id do evento com context.pop(id).
class CreateEventScreen extends ConsumerStatefulWidget {
  const CreateEventScreen({super.key});
  @override
  ConsumerState<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends ConsumerState<CreateEventScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _meeting = TextEditingController();
  final _description = TextEditingController();
  String _kind = 'esporte';
  Place? _venue;
  late DateTime _start;
  late DateTime _end;
  String? _communityId;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final t = DateTime.now().add(const Duration(days: 3));
    _start = DateTime(t.year, t.month, t.day, 20);
    _end = _start.add(const Duration(hours: 3));
  }

  @override
  void dispose() {
    _name.dispose();
    _meeting.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<DateTime?> _pickDateTime(DateTime initial) async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(now) ? now : initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 60)),
    );
    if (d == null || !mounted) return null;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial));
    if (t == null) return null;
    return DateTime(d.year, d.month, d.day, t.hour, t.minute);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_venue == null) {
      showBoraError(context, 'Escolha o local do evento.');
      return;
    }
    if (!_end.isAfter(_start)) {
      showBoraError(context, 'O fim precisa ser depois do começo.');
      return;
    }
    setState(() => _loading = true);
    final store = ref.read(storeProvider);
    try {
      // Já existe algo parecido? Oferece entrar nele.
      final similar = await store.similarEvents(_venue!.point, _start);
      if (similar.isNotEmpty && mounted) {
        final choice = await showModalBottomSheet<String>(
          context: context,
          builder: (sheet) => Padding(
            padding: const EdgeInsets.fromLTRB(Space.page, 0, Space.page, Space.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Já tem evento aí nesse dia', style: AppText.title),
                const SizedBox(height: Space.xxs),
                const Text('Juntar todo mundo no mesmo evento ajuda a achar carona.', style: AppText.body),
                const SizedBox(height: Space.md),
                for (final e in similar) ...[
                  EventCard(event: e, onTap: () => Navigator.of(sheet).pop(e.id)),
                  const SizedBox(height: Space.xs),
                ],
                const SizedBox(height: Space.xs),
                BoraButton(
                  label: 'É outro evento, criar mesmo assim',
                  kind: BoraButtonKind.ghost,
                  onPressed: () => Navigator.of(sheet).pop('__new__'),
                ),
              ],
            ),
          ),
        );
        if (choice == null) return;
        if (choice != '__new__') {
          if (mounted) context.pop(choice);
          return;
        }
      }
      final id = await store.createEvent(
        name: _name.text.trim(),
        kind: _kind,
        venueLabel: _venue!.label,
        point: _venue!.point,
        startsAt: _start,
        endsAt: _end,
        meetingPoint: _meeting.text.trim(),
        description: _description.text.trim(),
        communityId: _communityId,
      );
      if (mounted) context.pop(id);
    } catch (e) {
      if (mounted) showBoraError(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final communities = ref.watch(storeProvider).myCommunities.where((c) => c.myStatus == MemberStatus.active).toList();
    return StepScaffold(
      title: 'Criar evento',
      subtitle: 'Quem for ao mesmo lugar encontra carona de ida e de volta aqui.',
      action: BoraButton(label: 'Criar evento', loading: _loading, onPressed: _save),
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Nome', hintText: 'Ex.: Flamengo x Vasco'),
              validator: (v) => (v ?? '').trim().length < 3 ? 'Dê um nome ao evento.' : null,
            ),
            const SizedBox(height: Space.md),
            Wrap(
              spacing: Space.xs,
              runSpacing: Space.xs,
              children: [
                for (final e in eventKinds.entries)
                  ChoiceChip(
                    avatar: Icon(e.value.$2, size: 16, color: _kind == e.key ? AppColors.night : AppColors.textMuted),
                    label: Text(e.value.$1),
                    selected: _kind == e.key,
                    labelStyle: AppText.label.copyWith(color: _kind == e.key ? AppColors.night : AppColors.text),
                    onSelected: (_) => setState(() => _kind = e.key),
                  ),
              ],
            ),
            const SizedBox(height: Space.md),
            BoraCard(
              onTap: () async {
                final p = await PlaceSearchScreen.open(context, title: 'Onde vai ser?', hint: 'Estádio, casa de show, faculdade…');
                if (p != null) setState(() => _venue = p);
              },
              child: Row(children: [
                const IconTile(Icons.place_outlined),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Local', style: AppText.caption),
                    Text(_venue?.label ?? 'Escolher local', style: _venue == null ? AppText.body : AppText.bodyStrong),
                  ]),
                ),
                const Icon(Icons.chevron_right, color: AppColors.textFaint),
              ]),
            ),
            const SizedBox(height: Space.sm),
            Row(children: [
              Expanded(
                child: BoraCard(
                  onTap: () async {
                    final d = await _pickDateTime(_start);
                    if (d != null) {
                      setState(() {
                        final len = _end.difference(_start);
                        _start = d;
                        _end = d.add(len.isNegative ? const Duration(hours: 3) : len);
                      });
                    }
                  },
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Começa', style: AppText.caption),
                    Text(formatWhen(_start), style: AppText.bodyStrong),
                  ]),
                ),
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: BoraCard(
                  onTap: () async {
                    final d = await _pickDateTime(_end);
                    if (d != null) setState(() => _end = d);
                  },
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Termina (previsão)', style: AppText.caption),
                    Text(formatWhen(_end), style: AppText.bodyStrong),
                  ]),
                ),
              ),
            ]),
            const SizedBox(height: Space.md),
            TextFormField(
              controller: _meeting,
              decoration: const InputDecoration(
                labelText: 'Ponto de encontro na volta (opcional)',
                hintText: 'Ex.: Portão 3, estacionamento B',
                prefixIcon: Icon(Icons.flag_outlined),
              ),
            ),
            const SizedBox(height: Space.md),
            TextFormField(
              controller: _description,
              maxLines: 3,
              maxLength: 500,
              decoration: const InputDecoration(labelText: 'Detalhes (opcional)'),
            ),
            if (communities.isNotEmpty) ...[
              const SectionHeader('Quem pode ver', padding: EdgeInsets.only(top: Space.xs, bottom: Space.xs)),
              DropdownButtonFormField<String?>(
                initialValue: _communityId,
                dropdownColor: AppColors.surfaceRaised,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.visibility_outlined)),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Todo mundo no Bora')),
                  for (final c in communities) DropdownMenuItem(value: c.id, child: Text('Só a comunidade ${c.name}')),
                ],
                onChanged: (v) => setState(() => _communityId = v),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
