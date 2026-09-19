import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// O botão-pílula de vidro verde do app antigo, agora com carregamento e
/// estado desabilitado (o antigo deixava tocar duas vezes e duplicar requisição).
class BoraButton extends StatelessWidget {
  const BoraButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.secondary = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final bool secondary;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final accent = secondary ? AppColors.textMuted : AppColors.green;

    return Opacity(
      opacity: enabled || loading ? 1 : .45,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          boxShadow: secondary || !enabled
              ? null
              : const [
                  BoxShadow(color: Color(0x4D22C55E), blurRadius: 18, offset: Offset(0, 8)),
                ],
        ),
        child: Material(
          color: secondary ? const Color(0x0FFFFFFF) : const Color(0x2922C55E),
          shape: StadiumBorder(side: BorderSide(color: accent.withAlpha(190))),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? onPressed : null,
            child: SizedBox(
              width: double.infinity,
              height: 58,
              child: Center(
                child: loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.mint),
                      )
                    : Text(
                        label,
                        style: TextStyle(
                          color: secondary ? AppColors.text : AppColors.mint,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .4,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
