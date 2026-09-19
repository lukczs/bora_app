import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../data/errors.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/bora_button.dart';
import '../../core/widgets/step_scaffold.dart';

/// Verificação de identidade. A captura ainda é simulada (sem câmera/upload);
/// o status vem do banco: aprova na hora se app_config.auto_approve_identity = true.
class DocumentScreen extends ConsumerStatefulWidget {
  const DocumentScreen({super.key});
  @override
  ConsumerState<DocumentScreen> createState() => _DocumentScreenState();
}

class _DocumentScreenState extends ConsumerState<DocumentScreen> {
  bool _document = false;
  bool _selfie = false;
  bool _loading = false;

  Future<void> _submit() async {
    if (!_document || !_selfie) {
      showBoraError(context, 'Envie a foto do documento e a selfie para continuar.');
      return;
    }
    setState(() => _loading = true);
    try {
      await ref.read(storeProvider).submitIdentityDocuments();
      if (mounted) context.push('/onboarding/location');
    } catch (e) {
      if (mounted) showBoraError(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StepScaffold(
      step: 3,
      totalSteps: 4,
      title: 'Confirme que é você',
      subtitle:
          'Uma pessoa da equipe Bora confere o documento com a selfie. É isso que garante que todo mundo aqui é quem diz ser.',
      action: BoraButton(label: 'Enviar para verificação', loading: _loading, onPressed: _submit),
      child: Column(
        children: [
          _CaptureCard(
            icon: Icons.badge_outlined,
            title: 'Foto do documento',
            text: 'RG ou CNH, frente legível.',
            done: _document,
            onTap: () => setState(() => _document = true),
          ),
          const SizedBox(height: 14),
          _CaptureCard(
            icon: Icons.face_retouching_natural,
            title: 'Selfie',
            text: 'Rosto inteiro, sem óculos escuros ou boné.',
            done: _selfie,
            onTap: () => setState(() => _selfie = true),
          ),
          const SizedBox(height: 18),
          const Text('Nesta versão tocar no cartão simula a foto. O envio real da imagem entra junto com o painel de aprovação.'),
        ],
      ),
    );
  }
}

class _CaptureCard extends StatelessWidget {
  const _CaptureCard({
    required this.icon,
    required this.title,
    required this.text,
    required this.done,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String text;
  final bool done;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: done ? AppColors.green : AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        leading: Icon(icon, color: done ? AppColors.green : AppColors.textMuted, size: 30),
        title: Text(title, style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w700)),
        subtitle: Text(done ? 'Foto enviada' : text),
        trailing: Icon(done ? Icons.check_circle : Icons.photo_camera_outlined,
            color: done ? AppColors.green : AppColors.textMuted),
        onTap: onTap,
      ),
    );
  }
}
