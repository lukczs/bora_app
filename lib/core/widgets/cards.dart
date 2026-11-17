import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/tokens.dart';

/// Cartão liso: fundo de superfície, cantos de 16, sem sombra nem borda forte.
class BoraCard extends StatelessWidget {
  const BoraCard({super.key, required this.child, this.onTap, this.padding = const EdgeInsets.all(Space.md), this.highlight = false});
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg - 4),
        side: highlight ? const BorderSide(color: AppColors.green, width: 1.5) : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
    );
  }
}

/// Selo pequeno de status.
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.icon, this.color = AppColors.green});
  final String text;
  final IconData? icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withAlpha(30), borderRadius: BorderRadius.circular(6)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 13, color: color), const SizedBox(width: 4)],
          Flexible(
            child: Text(text,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

/// Origem -> destino com a linha vertical entre os dois pontos (padrão Uber).
class RouteSummary extends StatelessWidget {
  const RouteSummary({super.key, required this.from, required this.to, this.fromDetail, this.toDetail});
  final String from;
  final String to;
  final String? fromDetail;
  final String? toDetail;

  @override
  Widget build(BuildContext context) {
    Widget line(String title, String? detail) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppText.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
            if (detail != null && detail.isNotEmpty) Text(detail, style: AppText.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        );
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 14,
            child: Column(
              children: [
                const SizedBox(height: 5),
                Container(width: 9, height: 9, decoration: const BoxDecoration(color: AppColors.text, shape: BoxShape.circle)),
                Expanded(child: Container(width: 1.5, margin: const EdgeInsets.symmetric(vertical: 3), color: AppColors.line)),
                Container(width: 9, height: 9, color: AppColors.green),
                const SizedBox(height: 5),
              ],
            ),
          ),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [line(from, fromDetail), const SizedBox(height: Space.md), line(to, toDetail)],
            ),
          ),
        ],
      ),
    );
  }
}

/// Quadrado de ícone usado em listas.
class IconTile extends StatelessWidget {
  const IconTile(this.icon, {super.key, this.color = AppColors.text, this.background = AppColors.surface, this.size = 40});
  final IconData icon;
  final Color color;
  final Color background;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(Radii.sm)),
        child: Icon(icon, size: size * .5, color: color),
      );
}

/// Linha de lista padrão: ícone, título, subtítulo e ação à direita.
class ListRow extends StatelessWidget {
  const ListRow({super.key, this.icon, required this.title, this.subtitle, this.trailing, this.onTap, this.danger = false, this.leading});
  final IconData? icon;
  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.danger : AppColors.text;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.page, vertical: Space.sm),
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: Space.md)]
            else if (icon != null) ...[IconTile(icon!, color: color), const SizedBox(width: Space.md)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppText.bodyStrong.copyWith(color: color)),
                  if (subtitle != null) ...[const SizedBox(height: 2), Text(subtitle!, style: AppText.caption)],
                ],
              ),
            ),
            if (trailing != null) trailing! else if (onTap != null) const Icon(Icons.chevron_right, color: AppColors.textFaint),
          ],
        ),
      ),
    );
  }
}

/// Título de seção em caixa alta discreta.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key, this.action, this.padding = const EdgeInsets.fromLTRB(Space.page, Space.lg, Space.page, Space.xs)});
  final String text;
  final Widget? action;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Row(
          children: [
            Expanded(child: Text(text.toUpperCase(), style: AppText.overline)),
            if (action != null) action!,
          ],
        ),
      );
}

/// Dado em destaque: valor grande e rótulo pequeno (preço, tempo, vagas).
class Metric extends StatelessWidget {
  const Metric({super.key, required this.value, required this.label, this.alignEnd = false});
  final String value;
  final String label;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [Text(value, style: AppText.number), Text(label, style: AppText.caption)],
      );
}

class Avatar extends StatelessWidget {
  const Avatar(this.initial, {super.key, this.size = 44});
  final String initial;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: const BoxDecoration(color: AppColors.line, shape: BoxShape.circle),
        child: Text(initial, style: AppText.subtitle.copyWith(fontSize: size * .4)),
      );
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.text, this.action});
  final IconData icon;
  final String title;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xl, horizontal: Space.md),
      child: Column(
        children: [
          IconTile(icon, size: 56, color: AppColors.textMuted),
          const SizedBox(height: Space.md),
          Text(title, textAlign: TextAlign.center, style: AppText.title),
          const SizedBox(height: Space.xs),
          Text(text, textAlign: TextAlign.center, style: AppText.body),
          if (action != null) ...[const SizedBox(height: Space.lg), action!],
        ],
      ),
    );
  }
}
