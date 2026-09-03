import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/app_theme.dart';
import '../../core/currency_text_utils.dart';
import '../../core/date_text_utils.dart';
import '../../widgets/app_list_card.dart';
import 'budgets_repository.dart';
import 'models/budget.dart';

/// Lista de orçamentos do módulo formal — inclui tanto os criados
/// manualmente pelo prestador quanto os que nasceram de um pedido de
/// cliente pelo marketplace (ver `Budget.isFromClientRequest`/
/// `BudgetStatus`); esses últimos aparecem sempre no topo, com um selo de
/// status, até saírem de `pendente` (pedido do Franck: "ficar como
/// pendente para fazer/enviar o orçamento"). Mais recente primeiro dentro
/// de cada grupo (ver BudgetsRepository.watchAll); tocar num card abre
/// pra editar/tramitar, o botão flutuante cria um novo manualmente.
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

  Color _statusColor(BudgetStatus status) => switch (status) {
        BudgetStatus.pendente => AppColors.primary,
        BudgetStatus.enviado => Colors.orange,
        BudgetStatus.aprovado => Colors.blue,
        BudgetStatus.aceito => Colors.green,
        BudgetStatus.aditivoEnviado => Colors.deepPurple,
        BudgetStatus.recusado => AppColors.danger,
      };

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
          final budgets = [...(snapshot.data ?? const <Budget>[])];
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
          // Pedidos ainda pendentes de envio sempre no topo — são os que
          // precisam de ação do prestador (ver comentário da classe).
          budgets.sort((a, b) {
            final aPending = a.status == BudgetStatus.pendente ? 0 : 1;
            final bPending = b.status == BudgetStatus.pendente ? 0 : 1;
            if (aPending != bPending) return aPending.compareTo(bPending);
            return b.date.compareTo(a.date);
          });
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: budgets.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final budget = budgets[index];
              final status = budget.status;
              return AppListCard(
                leading: AppListCard.iconAvatar(
                  status == BudgetStatus.pendente
                      ? Icons.mark_email_unread_outlined
                      : Icons.description_outlined,
                ),
                title: budget.customerName,
                subtitle: status == BudgetStatus.pendente && (budget.requestDescription ?? '').isNotEmpty
                    ? budget.requestDescription
                    : formatDateLong(budget.date),
                trailing: status == null
                    ? Text(
                        formatCentsBRL(budget.totalCents),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: _statusColor(status).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              status.label,
                              style: TextStyle(
                                color: _statusColor(status),
                                fontWeight: FontWeight.w700,
                                fontSize: 10,
                              ),
                            ),
                          ),
                          if (status != BudgetStatus.pendente && budget.totalCents > 0) ...[
                            const SizedBox(height: 4),
                            Text(
                              formatCentsBRL(budget.totalCents),
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                            ),
                          ],
                        ],
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
