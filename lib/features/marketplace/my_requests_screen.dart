import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../core/auth_controller.dart';
import '../../core/currency_text_utils.dart';
import '../../core/date_text_utils.dart';
import '../../widgets/app_list_card.dart';
import '../budgets/models/budget.dart';
import 'budget_requests_repository.dart';
import 'client_auth_gate.dart';
import 'models/service_category.dart';

/// "Meus orçamentos" — pedidos de orçamento que o cliente fez pelo
/// marketplace, em qualquer prestador (ver
/// `BudgetRequestsRepository.watchMine`, `collectionGroup('budgets')`).
///
/// Antes disso existia uma coleção à parte, `serviceRequests`, com um
/// "Pedido" que só virava um orçamento de verdade depois que o prestador
/// respondia — o Franck pediu pra tirar essa etapa do meio: o pedido do
/// cliente já nasce como um orçamento (ver `Budget`/`BudgetStatus`), essa
/// tela mostra exatamente esses orçamentos.
class MyRequestsScreen extends StatefulWidget {
  const MyRequestsScreen({super.key});

  @override
  State<MyRequestsScreen> createState() => _MyRequestsScreenState();
}

class _MyRequestsScreenState extends State<MyRequestsScreen> {
  // Stream em vez de Future recarregado manualmente: esta tela é uma aba
  // do shell único do app (StatefulShellRoute.indexedStack — ver
  // UnifiedShell), que fica viva o tempo todo, e o envio de um novo
  // pedido acontece em OUTRA tela empilhada por cima
  // (RequestQuoteFormScreen) — não existia nenhum jeito natural de avisar
  // esta aqui pra recarregar. Ver BudgetRequestsRepository.watchMine.
  Stream<List<Budget>>? _stream;
  String? _streamForUid;

  void _ensureStream(String uid) {
    if (_streamForUid == uid) return;
    _streamForUid = uid;
    _stream = context.read<BudgetRequestsRepository>().watchMine();
  }

  Future<void> _signIn() async {
    if (await ensureClientAccount(context) && mounted) setState(() {});
  }

  Future<void> _respond(Budget budget, bool approved) async {
    try {
      final repository = context.read<BudgetRequestsRepository>();
      if (approved) {
        await repository.approve(budget);
      } else {
        await repository.reject(budget);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível responder agora. Tenta de novo.')),
      );
    }
    // Não precisa recarregar manualmente: a tela usa watchMine() (Stream),
    // então a lista já atualiza sozinha quando o status muda.
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    // `auth.providerIdOrNull` em vez de `auth.providerId`: evita um crash
    // real visto em produção (Null check operator used on a null value)
    // quando `status` ainda diz "authenticated" num rebuild transitório
    // logo depois de sair da conta, mas o Firebase Auth de verdade já
    // não tem mais `currentUser`. Se isso acontecer, só trata como "sem
    // conta" por esse frame — o próximo rebuild já corrige sozinho.
    final uid = auth.status == AuthStatus.authenticated ? auth.providerIdOrNull : null;
    final isClient = uid != null;
    if (isClient) {
      _ensureStream(uid);
    } else {
      _stream = null;
      _streamForUid = null;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Meus orçamentos')),
      body: !isClient
          ? ClientSignInPrompt(
              icon: Icons.list_alt_outlined,
              message: 'Crie uma conta grátis para acompanhar seus pedidos de orçamento.',
              onPressed: _signIn,
            )
          : StreamBuilder<List<Budget>>(
              stream: _stream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                // Antes o erro era engolido (`snapshot.data ?? []` direto)
                // e a tela mostrava "nenhum pedido" mesmo quando a
                // consulta falhava de verdade (ex.: índice composto do
                // collectionGroup ainda não pronto, ou regra negando) —
                // ficava impossível saber a diferença de "vazio" pra
                // "quebrado". Agora mostra o erro de verdade.
                if (snapshot.hasError) {
                  return ListView(
                    children: [
                      const SizedBox(height: 80),
                      const Icon(Icons.error_outline, size: 48, color: AppColors.danger),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          'Não foi possível carregar seus orçamentos.\n${snapshot.error}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.muted, fontSize: 12),
                        ),
                      ),
                    ],
                  );
                }
                final budgets = snapshot.data ?? [];
                if (budgets.isEmpty) {
                  return ListView(
                    children: const [
                      SizedBox(height: 80),
                      Icon(Icons.list_alt_outlined, size: 48, color: AppColors.muted),
                      SizedBox(height: 12),
                      Text('Nenhum pedido de orçamento enviado ainda.',
                          textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
                    ],
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: budgets.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final budget = budgets[index];
                    final status = budget.status;
                    final awaitingDecision = status == BudgetStatus.enviado;
                    final accepted = status == BudgetStatus.aceito;
                    final category =
                        budget.category != null ? serviceCategoryFromWire(budget.category!) : null;
                    return AppListCard(
                      leading: AppListCard.iconAvatar(category?.icon ?? Icons.handyman_rounded),
                      title: budget.providerName ?? 'Prestador',
                      subtitle: budget.requestDescription ?? '',
                      trailing: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          // Pedido do Franck: mostrar a data do pedido no
                          // card (a lista já vem ordenada da mais recente
                          // pra mais antiga — ver
                          // BudgetRequestsRepository.watchMine).
                          Text(
                            budget.createdAt != null
                                ? formatDateDdMmYyyy(budget.createdAt!)
                                : formatDateDdMmYyyy(budget.date),
                            style: const TextStyle(fontSize: 11, color: AppColors.muted),
                          ),
                          const SizedBox(height: 2),
                          Text(status?.label ?? '',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                          if (status != null &&
                              status != BudgetStatus.pendente &&
                              budget.totalCents > 0)
                            Text(
                              formatCentsBRL(budget.totalCents),
                              style: const TextStyle(fontSize: 12, color: AppColors.muted),
                            ),
                        ],
                      ),
                      // Só orçamentos aceitos liberam avaliação (ver
                      // BudgetRequestsRepository.hasAcceptedBudgetWith) —
                      // leva pro perfil público, onde a seção de avaliação
                      // de verdade mora (evita duplicar o formulário de
                      // estrelas em duas telas).
                      footer: awaitingDecision
                          ? Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(
                                  onPressed: () => _respond(budget, false),
                                  style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                                  child: const Text('Recusar'),
                                ),
                                const SizedBox(width: 8),
                                FilledButton(
                                  onPressed: () => _respond(budget, true),
                                  child: const Text('Aprovar'),
                                ),
                              ],
                            )
                          : accepted && budget.providerDirectoryId != null
                              ? Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton.icon(
                                    onPressed: () =>
                                        context.push('/prestador/${budget.providerDirectoryId}'),
                                    icon: const Icon(Icons.star_outline, size: 16),
                                    label: const Text('Avaliar este prestador'),
                                    style: TextButton.styleFrom(
                                      padding: EdgeInsets.zero,
                                      minimumSize: const Size(0, 32),
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  ),
                                )
                              : null,
                    );
                  },
                );
              },
            ),
    );
  }
}
