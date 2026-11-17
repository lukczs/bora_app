import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/tokens.dart';

/// Moldura das telas de formulário: progresso fino no topo, título forte,
/// explicação curta, conteúdo rolável e ação fixa no rodapé.
class StepScaffold extends StatelessWidget {
  const StepScaffold({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
    required this.action,
    this.step,
    this.totalSteps = 3,
    this.canGoBack = true,
    this.secondaryAction,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final Widget action;
  final Widget? secondaryAction;
  final int? step;
  final int totalSteps;
  final bool canGoBack;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: canGoBack,
          titleSpacing: canGoBack ? 0 : Space.page,
          title: step == null
              ? null
              : Padding(
                  padding: const EdgeInsets.only(right: Space.page),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: step! / totalSteps,
                      minHeight: 3,
                      backgroundColor: AppColors.line,
                    ),
                  ),
                ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(Space.page, Space.xs, Space.page, Space.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (step != null) ...[
                        Text('Passo $step de $totalSteps', style: AppText.label),
                        const SizedBox(height: Space.xs),
                      ],
                      Text(title, style: AppText.headline),
                      if (subtitle != null) ...[
                        const SizedBox(height: Space.xs),
                        Text(subtitle!, style: AppText.body),
                      ],
                      const SizedBox(height: Space.lg),
                      child,
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.page, 0, Space.page, Space.md),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [action, if (secondaryAction != null) ...[const SizedBox(height: Space.xs), secondaryAction!]],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void showBoraError(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Página simples padronizada (lista com título grande), para perfil, viagens etc.
class PageScaffold extends StatelessWidget {
  const PageScaffold({super.key, required this.title, required this.children, this.actions, this.onRefresh, this.showBack = false, this.bottom});
  final String title;
  final List<Widget> children;
  final List<Widget>? actions;
  final Future<void> Function()? onRefresh;
  final bool showBack;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final list = ListView(
      padding: const EdgeInsets.only(bottom: Space.xl),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.page, Space.xs, Space.page, Space.xs),
          child: Text(title, style: AppText.display.copyWith(fontSize: 30)),
        ),
        ...children,
      ],
    );
    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: showBack, actions: actions, toolbarHeight: 48),
      body: onRefresh == null
          ? list
          : RefreshIndicator(color: AppColors.green, backgroundColor: AppColors.surface, onRefresh: onRefresh!, child: list),
      bottomNavigationBar: bottom,
    );
  }
}
