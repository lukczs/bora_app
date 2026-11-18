import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/format.dart';
import '../../domain/models.dart';

const eventKinds = <String, (String, IconData)>{
  'esporte': ('Esporte', Icons.sports_soccer),
  'show': ('Show', Icons.music_note),
  'festa': ('Festa', Icons.celebration),
  'faculdade': ('Faculdade', Icons.school),
  'outro': ('Outro', Icons.local_activity),
};

const _months = ['JAN', 'FEV', 'MAR', 'ABR', 'MAI', 'JUN', 'JUL', 'AGO', 'SET', 'OUT', 'NOV', 'DEZ'];

/// Selo de data no estilo de ingresso: mês em cima, dia grande embaixo.
class DateBadge extends StatelessWidget {
  const DateBadge(this.date, {super.key, this.live = false});
  final DateTime date;
  final bool live;

  @override
  Widget build(BuildContext context) => Container(
        width: 52,
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: live ? AppColors.green : AppColors.night,
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
        child: Column(children: [
          Text(live ? 'AGORA' : _months[date.month - 1],
              style: AppText.overline.copyWith(fontSize: 10, color: live ? AppColors.night : AppColors.green)),
          Text('${date.day}', style: AppText.headline.copyWith(fontSize: 22, color: live ? AppColors.night : AppColors.text)),
        ]),
      );
}

class EventCard extends StatelessWidget {
  const EventCard({super.key, required this.event, required this.onTap});
  final BoraEvent event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final e = event;
    final kind = eventKinds[e.kind] ?? eventKinds['outro']!;
    final rides = e.ridesIda + e.ridesVolta;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(Radii.lg - 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.lg - 4),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Space.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DateBadge(e.startsAt, live: e.happeningNow),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(kind.$2, size: 14, color: AppColors.textMuted),
                      const SizedBox(width: 4),
                      Text('${kind.$1} · ${weekdayShort(e.startsAt.weekday)} ${formatTime(e.startsAt)}', style: AppText.caption),
                    ]),
                    const SizedBox(height: 2),
                    Text(e.name, style: AppText.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
                    Text(
                      [e.venueLabel, if (e.distanceM != null) formatKm(e.distanceM!)].join(' · '),
                      style: AppText.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: Space.xs),
                    Wrap(spacing: Space.sm, runSpacing: 4, children: [
                      _Stat(Icons.directions_car_filled, rides == 0 ? 'Sem caronas ainda' : '$rides ${rides == 1 ? 'carona' : 'caronas'}',
                          highlight: rides > 0),
                      if (e.seats > 0) _Stat(Icons.event_seat_outlined, '${e.seats} vagas'),
                      if (e.interested > 0) _Stat(Icons.front_hand_outlined, '${e.interested} procurando'),
                      if (e.communityName != null) _Stat(Icons.groups_outlined, e.communityName!),
                    ]),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.icon, this.text, {this.highlight = false});
  final IconData icon;
  final String text;
  final bool highlight;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: highlight ? AppColors.green : AppColors.textMuted),
        const SizedBox(width: 3),
        Text(text, style: AppText.caption.copyWith(color: highlight ? AppColors.green : AppColors.textMuted)),
      ]);
}
