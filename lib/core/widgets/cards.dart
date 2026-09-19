import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class BoraCard extends StatelessWidget {
  const BoraCard({super.key, required this.child, this.onTap, this.padding = const EdgeInsets.all(18)});
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
    );
  }
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.icon, this.color = AppColors.green});
  final String text;
  final IconData? icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withAlpha(36),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withAlpha(150)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 14, color: color), const SizedBox(width: 5)],
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

/// Origem -> destino com a linha vertical entre os dois pontos.
class RouteSummary extends StatelessWidget {
  const RouteSummary({super.key, required this.from, required this.to});
  final String from;
  final String to;

  @override
  Widget build(BuildContext context) {
    const strong = TextStyle(color: AppColors.text, fontSize: 15, fontWeight: FontWeight.w600);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            const SizedBox(height: 4),
            const Icon(Icons.radio_button_checked, size: 14, color: AppColors.green),
            Container(width: 2, height: 20, color: AppColors.line),
            const Icon(Icons.location_on, size: 16, color: AppColors.mint),
          ],
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(from, style: strong, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 16),
              Text(to, style: strong, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ],
    );
  }
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
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        children: [
          Icon(icon, size: 40, color: AppColors.textMuted),
          const SizedBox(height: 12),
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.text, fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(text, textAlign: TextAlign.center),
          if (action != null) ...[const SizedBox(height: 18), action!],
        ],
      ),
    );
  }
}
