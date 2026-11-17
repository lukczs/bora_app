import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/tokens.dart';

enum BoraButtonKind { primary, secondary, ghost, danger }

/// Botão padrão: sólido e direto, com carregamento e bloqueio de toque duplo.
/// [secondary] continua aceito por compatibilidade com as telas antigas.
class BoraButton extends StatelessWidget {
  const BoraButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.secondary = false,
    this.kind,
    this.icon,
    this.expand = true,
    this.compact = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final bool secondary;
  final BoraButtonKind? kind;
  final IconData? icon;
  final bool expand;
  final bool compact;

  BoraButtonKind get _kind => kind ?? (secondary ? BoraButtonKind.secondary : BoraButtonKind.primary);

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final (bg, fg, side) = switch (_kind) {
      BoraButtonKind.primary => (AppColors.green, AppColors.night, BorderSide.none),
      BoraButtonKind.secondary => (AppColors.surface, AppColors.text, BorderSide.none),
      BoraButtonKind.ghost => (Colors.transparent, AppColors.text, const BorderSide(color: AppColors.line)),
      BoraButtonKind.danger => (Colors.transparent, AppColors.danger, const BorderSide(color: Color(0x66F87171))),
    };

    final child = loading
        ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: fg))
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 20, color: fg), const SizedBox(width: Space.xs)],
              Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: AppText.button.copyWith(color: fg))),
            ],
          );

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 150),
      opacity: enabled || loading ? 1 : .4,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md), side: side),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          child: SizedBox(
            width: expand ? double.infinity : null,
            height: compact ? 44 : 54,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.lg),
              child: Center(widthFactor: 1, child: child),
            ),
          ),
        ),
      ),
    );
  }
}

/// Botão redondo flutuante (sobre o mapa): voltar, centralizar, camadas.
class RoundIconButton extends StatelessWidget {
  const RoundIconButton({super.key, required this.icon, required this.onPressed, this.tooltip, this.size = 48});
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;

  @override
  Widget build(BuildContext context) {
    final btn = Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(color: AppColors.surfaceRaised, shape: BoxShape.circle, boxShadow: Shadows.soft),
      child: Material(
        type: MaterialType.transparency,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onPressed, child: Icon(icon, color: AppColors.text, size: 22)),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}
