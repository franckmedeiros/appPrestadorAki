import 'package:flutter/material.dart';
import '../../core/app_theme.dart';

/// Tela de orçamentos — layout do protótipo clicável, ainda sem integração
/// com a API (endpoints /budgets/*, próxima história do backlog depois de
/// auth + clientes).
class BudgetsScreen extends StatelessWidget {
  const BudgetsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Orçamentos')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          SizedBox(height: 60),
          Icon(Icons.description_outlined, size: 48, color: AppColors.muted),
          SizedBox(height: 12),
          Text(
            'Integração com /budgets ainda pendente.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted),
          ),
          Text(
            'Próxima história do backlog (ver prestadoraki-backlog.xlsx).',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
