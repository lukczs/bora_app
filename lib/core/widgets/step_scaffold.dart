import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Moldura das telas de cadastro: barra de progresso (é uma sequência de verdade),
/// título, explicação, conteúdo rolável e ação fixa no rodapé.
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
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final Widget action;
  final int? step;
  final int totalSteps;
  final bool canGoBack;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: canGoBack,
          title: step == null
              ? null
              : Row(
                  children: [
                    for (var i = 0; i < totalSteps; i++)
                      Expanded(
                        child: Container(
                          height: 4,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            color: i < step! ? AppColors.green : AppColors.line,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: t.headlineMedium),
                      if (subtitle != null) ...[
                        const SizedBox(height: 10),
                        Text(subtitle!, style: t.bodyLarge),
                      ],
                      const SizedBox(height: 28),
                      child,
                    ],
                  ),
                ),
              ),
              Padding(padding: const EdgeInsets.fromLTRB(24, 0, 24, 20), child: action),
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
