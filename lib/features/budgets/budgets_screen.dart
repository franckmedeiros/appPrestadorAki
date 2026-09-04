import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/app_theme.dart';
import '../../core/currency_text_utils.dart';
import '../../core/date_text_utils.dart';
import '../../widgets/app_list_card.dart';
import 'budget_form_screen.dart' show BudgetAcceptedResult;
import 'budgets_repository.dart';
import 'models/budget.dart';

/// Lista de orçamentos do módulo formal — inclui tanto os criados
/// manualmente pelo prestador quanto os que nasceram de um pedido de
/// cliente pelo marketplace (ver `Budget.isFromClientRequest`/
/// `BudgetStatus`). Ordenados por PRIORIDADE de ação (ver `_priority`
/// abaixo, pedido do Franck: "ordenar pelos status que precisa de
/// execução") — primeiro quem precisa do prestador agora (`pendente`/
/// `aprovado`), depois quem está esperando o cliente (`enviado`/
/// `aditivoEnviado`/orçamento manual sem status), por último quem já foi
/// resolvido (`aceito`/`recusado`); mais recente primeiro dentro de cada
/// grupo (ver BudgetsRepository.watchAll). Tocar num card abre pra
/// editar/tramitar, o botão flutuante cria um novo manualmente.
///
/// Orçamentos já resolvidos (`aceito`/`recusado`) podem ser arquivados
/// (deslizar o card — pedido do Franck: "criar a opção de arquivar") pra
/// sair desta lista sem apagar nada; o botão no topo alterna pra ver os
/// arquivados e desarquivar (ver `Budget.archivedByProvider`/
/// `BudgetsRepository.setArchivedByProvider`).
class BudgetsScreen extends StatefulWidget {
  const BudgetsScreen({super.key});

  @override
  State<BudgetsScreen> createState() => _BudgetsScreenState();
}

class _BudgetsScreenState extends State<BudgetsScreen> {
  late Stream<List<Budget>> _stream = context.read<BudgetsRepository>().watchAll();
  bool _showArchived = false;

  /// Ids arquivando/desarquivando "otimisticamente" — escondidos da lista
  /// assim que o usuário desliza, mesmo antes do Firestore confirmar (a
  /// atualização ao vivo do stream demora um instante). Sem isso, se
  /// nada mais mudasse a lista antes do stream reemitir, o
  /// `Dismissible` recém-removido reapareceria com a MESMA `key` e o
  /// Flutter derruba o app com "A dismissed Dismissible widget is still
  /// part of the tree".
  final Set<String> _pendingArchiveIds = {};

  Future<void> _retry() async {
    setState(() => _stream = context.read<BudgetsRepository>().watchAll());
  }

  /// Só orçamentos com um status "resolvido" fazem sentido arquivar (ver
  /// pedido do Franck respondido: "só os já concluídos") — um orçamento
  /// manual (sem status) ou ainda em aberto continua sem essa opção.
  bool _canArchive(Budget budget) =>
      budget.status == BudgetStatus.aceito || budget.status == BudgetStatus.recusado;

  void _archive(Budget budget, bool archived) {
    setState(() => _pendingArchiveIds.add(budget.id));
    unawaited(_setArchived(budget, archived));
  }

  Future<void> _setArchived(Budget budget, bool archived) async {
    try {
      await context.read<BudgetsRepository>().setArchivedByProvider(budget.id, archived);
    } catch (e) {
      if (!mounted) return;
      setState(() => _pendingArchiveIds.remove(budget.id));
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(archived
                ? 'Não foi possível arquivar: $e'
                : 'Não foi possível desarquivar: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      return;
    }
    if (!mounted) return;
    setState(() => _pendingArchiveIds.remove(budget.id));
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text(archived ? 'Orçamento arquivado.' : 'Orçamento desarquivado.')),
      );
  }

  /// Ordem de prioridade pra quem precisa de ação — pedido do Franck:
  /// "ordenar pelos status que precisa de execução". 0 = precisa do
  /// PRESTADOR agora; 1 = esperando o CLIENTE (ou orçamento manual, sem
  /// fluxo nenhum); 2 = já resolvido.
  int _priority(BudgetStatus? status) => switch (status) {
        null => 1,
        BudgetStatus.pendente => 0,
        BudgetStatus.aprovado => 0,
        BudgetStatus.enviado => 1,
        BudgetStatus.aditivoEnviado => 1,
        BudgetStatus.aceito => 2,
        BudgetStatus.recusado => 2,
      };

  /// Abre o formulário e, se ele fechar depois de um aceite final bem
  /// sucedido (ver `BudgetFormScreen._acceptFinal`/`BudgetAcceptedResult`),
  /// mostra onde o serviço foi parar — pedido do Franck: "quando o
  /// orçamento é concluído, poderia ter alguma coisa que pudesse nos
  /// mostrar que ele está no guia serviços agora... eu achei um pouco
  /// perdido". Um SnackBar com atalho pra "Serviços" em vez de deixar a
  /// pessoa procurar sozinha aonde o orçamento foi parar.
  Future<void> _openBudget(Budget? budget) async {
    final result = await context.push<Object?>('/orcamentos/editar', extra: budget);
    if (!mounted || result is! BudgetAcceptedResult) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(result.message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'Ver Serviços',
            onPressed: () => context.push('/servicos'),
          ),
        ),
      );
  }

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
      appBar: AppBar(
        title: Text(_showArchived ? 'Orçamentos arquivados' : 'Orçamentos'),
        actions: [
          IconButton(
            tooltip: _showArchived ? 'Ver orçamentos ativos' : 'Ver arquivados',
            icon: Icon(_showArchived ? Icons.inbox_outlined : Icons.archive_outlined),
            onPressed: () => setState(() => _showArchived = !_showArchived),
          ),
        ],
      ),
      floatingActionButton: _showArchived
          ? null
          : FloatingActionButton(
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
          final budgets = (snapshot.data ?? const <Budget>[])
              .where((budget) =>
                  budget.archivedByProvider == _showArchived &&
                  !_pendingArchiveIds.contains(budget.id))
              .toList();
          if (budgets.isEmpty) {
            return ListView(
              children: [
                const SizedBox(height: 80),
                Icon(
                  _showArchived ? Icons.archive_outlined : Icons.description_outlined,
                  size: 48,
                  color: AppColors.muted,
                ),
                const SizedBox(height: 12),
                Text(
                  _showArchived
                      ? 'Nenhum orçamento arquivado.'
                      : 'Nenhum orçamento ainda. Toque no + pra criar o primeiro.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.muted),
                ),
              ],
            );
          }
          // Quem precisa de ação primeiro, mais recente primeiro dentro de
          // cada grupo (ver `_priority`/comentário da classe).
          budgets.sort((a, b) {
            final diff = _priority(a.status).compareTo(_priority(b.status));
            if (diff != 0) return diff;
            return b.date.compareTo(a.date);
          });
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: budgets.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final budget = budgets[index];
              final status = budget.status;
              final card = AppListCard(
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
                    // `ConstrainedBox` aqui é o que impede um `status.label`
                    // comprido (ex.: "Aditivo enviado — aguardando
                    // aprovação", ou "Aprovado — falta confirmar") de pedir
                    // largura ilimitada pro selo — sem isso, o Row deste
                    // card sobrava quase nenhum espaço pro nome/data do
                    // cliente (Expanded do AppListCard), que aparecia
                    // espremido/quebrado letra por letra. Com a largura
                    // travada, o texto do selo quebra em até 2 linhas em
                    // vez de estourar a largura do card.
                    : ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 128),
                        child: Column(
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
                                textAlign: TextAlign.right,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
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
                      ),
                onTap: () => _openBudget(budget),
              );

              // Arquivado: sempre pode desarquivar. Ativo: só desliza
              // quem já foi resolvido (ver `_canArchive`) — em aberto
              // continua só tocável, pra não sumir por engano.
              if (!_showArchived && !_canArchive(budget)) return card;

              final archiving = !_showArchived;
              return Dismissible(
                key: ValueKey(budget.id),
                direction: DismissDirection.endToStart,
                onDismissed: (_) => _archive(budget, archiving),
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    color: (archiving ? AppColors.muted : AppColors.primary).withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    archiving ? Icons.archive_outlined : Icons.unarchive_outlined,
                    color: archiving ? AppColors.muted : AppColors.primary,
                  ),
                ),
                child: card,
              );
            },
          );
        },
      ),
    );
  }
}
