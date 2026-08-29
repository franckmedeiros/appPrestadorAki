import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/app_theme.dart';
import '../../core/currency_text_utils.dart';
import '../../core/date_text_utils.dart';
import '../../widgets/app_list_card.dart';
import 'budgets_repository.dart';
import 'models/budget.dart';

/// Lista de orçamentos do módulo formal (ligado a Clientes cadastrados —
/// diferente do "Pedidos" do marketplace). Mais recente primeiro (ver
/// BudgetsRepository.watchAll); tocar num card abre pra editar, o botão
/// flutuante cria um novo.
class BudgetsScreen extends StatefulWidget {
  const BudgetsScreen({super.key});

  @override
  State<BudgetsScreen> createState() => _BudgetsScreenState();
}

class _BudgetsScreenState extends State<BudgetsScreen> {
  late Stream<List<Budget>> _stream = context.read<BudgetsRepository>().watchAll();

  Future<void> _retry() async {
    setState(() => _stream = context.read<BudgetsRepository>().watchAll());
  }

  Future<void> _openBudget(Budget? budget) => context.push('/orcamentos/editar', extra: budget);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Orçamentos')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openBudget(null),
        child: const Icon(Icons.add),
      ),
      body: StreamBuilder<List<Budget>>(
        stream: _stream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ListView(
              children: [
                const SizedBox(height: 80),
                const Icon(Icons.error_outline, size: 48, color: AppColors.danger),
                const SizedBox(height: 12),
                const Text('Não foi possível carregar os orçamentos.', textAlign: TextAlign.center),
                const SizedBox(height: 12),
                Center(child: OutlinedButton(onPressed: _retry, child: const Text('Tentar de novo'))),
              ],
            );
          }
          final budgets = snapshot.data ?? [];
          if (budgets.isEmpty) {
            return ListView(
              children: const [
                SizedBox(height: 80),
                Icon(Icons.description_outlined, size: 48, color: AppColors.muted),
                SizedBox(height: 12),
                Text(
                  'Nenhum orçamento ainda. Toque no + pra criar o primeiro.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted),
                ),
              ],
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: budgets.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final budget = budgets[index];
              return AppListCard(
                leading: AppListCard.iconAvatar(Icons.description_outlined),
                title: budget.customerName,
                subtitle: formatDateLong(budget.date),
                trailing: Text(
                  formatCentsBRL(budget.totalCents),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                onTap: () => _openBudget(budget),
              );
            },
          );
        },
      ),
    );
  }
}
