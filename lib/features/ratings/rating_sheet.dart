import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/bora_button.dart';
import '../../core/widgets/cards.dart';
import '../../core/widgets/step_scaffold.dart';
import '../../data/errors.dart';
import '../../domain/models.dart';

bool _asking = false;

/// Pergunta, uma por vez, as avaliações pendentes (as puladas nesta abertura
/// do app não voltam). Pode chamar à vontade: se já está perguntando, não faz nada.
Future<void> askPendingRatings(BuildContext context, WidgetRef ref) async {
  if (_asking) return;
  _asking = true;
  try {
    final store = ref.read(storeProvider);
    while (context.mounted) {
      final next = store.pendingRatings.where((p) => !store.skippedRatings.contains(p.bookingId)).firstOrNull;
      if (next == null) break;
      final done = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppColors.surfaceRaised,
        builder: (_) => RatingSheet(pending: next),
      );
      if (done != true) {
        store.skippedRatings.add(next.bookingId);
      }
    }
  } finally {
    _asking = false;
  }
}

class RatingSheet extends ConsumerStatefulWidget {
  const RatingSheet({super.key, required this.pending});
  final PendingRating pending;

  @override
  ConsumerState<RatingSheet> createState() => _RatingSheetState();
}

class _RatingSheetState extends ConsumerState<RatingSheet> {
  int _stars = 0;
  final Set<String> _tags = {};
  final _comment = TextEditingController();
  bool _sending = false;

  static const _driverTags = ['Pontual', 'Direção segura', 'Carro limpo', 'Simpático(a)', 'Rota certinha'];
  static const _passengerTags = ['Pontual', 'Estava na parada', 'Educado(a)', 'Simpático(a)'];
  static const _labels = ['', 'Ruim', 'Fraca', 'Ok', 'Boa', 'Excelente'];

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() => _sending = true);
    try {
      await ref.read(storeProvider).rateTrip(widget.pending.bookingId, _stars,
          tags: _tags.toList(), comment: _comment.text.trim().isEmpty ? null : _comment.text.trim());
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showBoraError(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.pending;
    final tags = p.ratingDriver ? _driverTags : _passengerTags;
    return Padding(
      padding: EdgeInsets.fromLTRB(Space.page, Space.lg, Space.page, Space.lg + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: Avatar(p.person.initial, size: 64)),
          const SizedBox(height: Space.sm),
          Text(p.ratingDriver ? 'Como foi a carona com ${p.person.firstName}?' : 'Como foi levar ${p.person.firstName}?',
              textAlign: TextAlign.center, style: AppText.title),
          if (p.from != null && p.to != null)
            Padding(
              padding: const EdgeInsets.only(top: Space.xxs),
              child: Text('${p.from} → ${p.to}', textAlign: TextAlign.center, style: AppText.caption, maxLines: 2),
            ),
          const SizedBox(height: Space.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 1; i <= 5; i++)
                IconButton(
                  iconSize: 40,
                  tooltip: '$i estrela${i == 1 ? '' : 's'}',
                  onPressed: () => setState(() => _stars = i),
                  icon: Icon(i <= _stars ? Icons.star_rounded : Icons.star_outline_rounded,
                      color: i <= _stars ? AppColors.warning : AppColors.textFaint),
                ),
            ],
          ),
          Text(_labels[_stars], textAlign: TextAlign.center, style: AppText.label.copyWith(color: AppColors.warning)),
          if (_stars > 0) ...[
            const SizedBox(height: Space.sm),
            Wrap(
              spacing: Space.xs,
              runSpacing: Space.xs,
              alignment: WrapAlignment.center,
              children: [
                for (final t in tags)
                  FilterChip(
                    label: Text(t),
                    selected: _tags.contains(t),
                    onSelected: (on) => setState(() => on ? _tags.add(t) : _tags.remove(t)),
                  ),
              ],
            ),
            const SizedBox(height: Space.sm),
            TextField(
              controller: _comment,
              maxLength: 300,
              maxLines: 2,
              decoration: const InputDecoration(hintText: 'Quer contar mais alguma coisa? (opcional)'),
            ),
          ],
          const SizedBox(height: Space.sm),
          BoraButton(label: 'Enviar avaliação', loading: _sending, onPressed: _stars == 0 ? null : _send),
          BoraButton(label: 'Agora não', kind: BoraButtonKind.ghost, onPressed: () => Navigator.of(context).pop(false)),
        ],
      ),
    );
  }
}
