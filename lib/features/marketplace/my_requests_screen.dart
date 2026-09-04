import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/app_theme.dart';
import '../../core/auth_controller.dart';
import '../../core/currency_text_utils.dart';
import '../../core/date_text_utils.dart';
import '../../widgets/app_list_card.dart';
import '../budgets/models/budget.dart';
import '../budgets/widgets/aditivo_badge.dart';
import '../jobs/job_status_chip.dart';
import '../jobs/models/job.dart';
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

  // Pedido do Franck: "o tramite do serviço precisa aparecer no card do
  // cliente e a avaliação, só quando concluir todo o processo" — sem
  // isso, esta tela não sabia de nada depois que o orçamento virava
  // "aceito" (o Job/execução do serviço mora na subcoleção do
  // PRESTADOR, ver `BudgetRequestsRepository.watchMyJobsByBudgetId`).
  Stream<Map<String, Job>>? _jobsStream;

  // Pedido do Franck: opção de arquivar pedidos antigos em "Meus
  // orçamentos" — não é uma consulta separada (só um filtro local em
  // cima do mesmo `_stream`, ver `archivedByClient` em Budget), porque a
  // lista inteira do cliente já é pequena o bastante pra isso não pesar.
  bool _showArchived = false;

  void _ensureStream(String uid) {
    if (_streamForUid == uid) return;
    _streamForUid = uid;
    _stream = context.read<BudgetRequestsRepository>().watchMine();
    _jobsStream = context.read<BudgetRequestsRepository>().watchMyJobsByBudgetId();
  }

  /// Cria uma consulta NOVA de verdade, ignorando o cache de
  /// `_ensureStream` (que só recria quando o uid muda) — necessário
  /// porque, depois de um erro definitivo (ex.: PERMISSION_DENIED — o
  /// Firestore não tenta de novo sozinho depois desse tipo de
  /// erro, diferente de uma falha passageira de rede), só uma consulta
  /// nova destrava a tela. Isso pode acontecer numa corrida rara logo na
  /// abertura do app, se o listener desta aba (que fica viva o tempo
  /// todo — ver comentário da classe) for montado um instante antes do
  /// token de autenticação estar pronto.
  Future<void> _retry() async {
    // Força um token de autenticação NOVO antes de tentar de novo — se a
    // consulta anterior foi negada porque o listener foi montado com um
    // token velho/incompleto (corrida na abertura do app), só recriar a
    // stream com o MESMO token em cache não resolve nada; só um refresh
    // de verdade garante que o request chega ao servidor com um token
    // válido.
    try {
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
    } catch (_) {
      // Sem internet ou token impossível de renovar agora — segue e
      // tenta com o que tiver; pelo menos não trava o botão.
    }
    if (!mounted) return;
    setState(() => _stream = context.read<BudgetRequestsRepository>().watchMine());
  }

  Future<void> _signIn() async {
    if (await ensureClientAccount(context) && mounted) setState(() {});
  }

  Future<void> _setArchived(Budget budget, bool archived) async {
    try {
      await context.read<BudgetRequestsRepository>().setArchivedByClient(budget, archived);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(archived ? 'Não foi possível arquivar agora.' : 'Não foi possível desarquivar agora.')),
      );
    }
    // Stream — a lista já atualiza sozinha, mesmo raciocínio de _respond.
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

  /// Junta o QR Code de pagamento (quando o prestador já mandou cobrar —
  /// ver `Budget.paymentPixPayload`/`functions/src/jobs.ts`) com o que já
  /// existia no rodapé do card (aprovar/recusar, ou o link pra avaliar) —
  /// os dois podem coexistir (ex.: já pagou mas ainda não avaliou).
  Widget? _buildFooter(Budget budget, {required bool awaitingDecision, required bool canRate}) {
    final Widget? decisionOrRating = awaitingDecision
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
        : canRate && budget.providerDirectoryId != null
            ? Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => context.push('/prestador/${budget.providerDirectoryId}'),
                  icon: const Icon(Icons.star_outline, size: 16),
                  label: const Text('Avaliar este prestador'),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              )
            : null;

    final showPayment = budget.paymentPixPayload != null;
    if (!showPayment) return decisionOrRating;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PaymentSection(budget: budget),
        if (decisionOrRating != null) ...[const SizedBox(height: 10), decisionOrRating],
      ],
    );
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
      _jobsStream = null;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Meus orçamentos'),
        actions: [
          if (isClient)
            IconButton(
              tooltip: _showArchived ? 'Ver pedidos ativos' : 'Ver arquivados',
              icon: Icon(_showArchived ? Icons.inbox_outlined : Icons.archive_outlined),
              onPressed: () => setState(() => _showArchived = !_showArchived),
            ),
        ],
      ),
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
                      const SizedBox(height: 12),
                      Center(child: OutlinedButton(onPressed: _retry, child: const Text('Tentar de novo'))),
                    ],
                  );
                }
                // Filtro local de arquivados (ver `_showArchived` acima) —
                // não é uma consulta separada, `watchMine()` já traz tudo.
                final budgets = (snapshot.data ?? [])
                    .where((budget) => budget.archivedByClient == _showArchived)
                    .toList();
                if (budgets.isEmpty) {
                  return ListView(
                    children: [
                      const SizedBox(height: 80),
                      Icon(
                        _showArchived ? Icons.inbox_outlined : Icons.list_alt_outlined,
                        size: 48,
                        color: AppColors.muted,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _showArchived
                            ? 'Nenhum pedido arquivado.'
                            : 'Nenhum pedido de orçamento enviado ainda.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.muted),
                      ),
                    ],
                  );
                }
                // Pedido do Franck: "o tramite do serviço precisa aparecer
                // no card do cliente e a avaliação, só quando concluir
                // todo o processo" — junta o Job de cada orçamento (se
                // já existir um, ver `_jobsStream`) só nesta camada mais
                // interna, sem duplicar os estados de carregamento/erro
                // já tratados acima pro stream de orçamentos.
                return StreamBuilder<Map<String, Job>>(
                  stream: _jobsStream,
                  builder: (context, jobsSnapshot) {
                    final jobsByBudgetId = jobsSnapshot.data ?? const <String, Job>{};
                    return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: budgets.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final budget = budgets[index];
                    final status = budget.status;
                    final job = jobsByBudgetId[budget.id];
                    // Pedido do Franck: quando o prestador reenvia um
                    // aditivo, o cliente precisa poder aprovar/recusar
                    // igual a um orçamento comum enviado -- não fica
                    // "preso" no status Aceito antigo sem nenhuma ação
                    // disponível (ver BudgetsRepository.registerAditivo).
                    final awaitingDecision =
                        status == BudgetStatus.enviado || status == BudgetStatus.aditivoEnviado;
                    // Avaliação só libera quando o SERVIÇO concluir de
                    // verdade (Job.status == concluido) — não basta o
                    // orçamento estar "aceito", que acontece bem antes do
                    // serviço começar/terminar (ver
                    // BudgetRequestsRepository.hasAcceptedBudgetWith, que
                    // aplica a mesma regra na tela de avaliação de
                    // verdade).
                    final canRate = job?.status == JobStatus.concluido;
                    final category =
                        budget.category != null ? serviceCategoryFromWire(budget.category!) : null;
                    return AppListCard(
                      leading: AppListCard.iconAvatar(category?.icon ?? Icons.handyman_rounded),
                      title: budget.providerName ?? 'Prestador',
                      subtitle: budget.requestDescription ?? '',
                      // Pedido do Franck: "não consegue visualizar o
                      // orçamento, somente se eu enviar o pdf" — antes
                      // este card só mostrava um resumo (categoria/
                      // valor/status), sem os itens. Agora toca em
                      // qualquer parte do card (fora dos botões) pra ver
                      // o orçamento completo, igual ao PDF.
                      onTap: () => showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                        ),
                        builder: (context) => _BudgetDetailSheet(budget: budget),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Column(
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
                              // Pedido do Franck: "o tramite do serviço
                              // precisa aparecer no card do cliente" — só
                              // existe um Job depois do aceite final do
                              // prestador (ver BudgetsRepository.
                              // acceptFinal/JobsRepository.create).
                              if (job != null) ...[
                                const SizedBox(height: 3),
                                JobStatusChip(status: job.status),
                              ],
                              if (status != null &&
                                  status != BudgetStatus.pendente &&
                                  budget.totalCents > 0)
                                Text(
                                  formatCentsBRL(budget.totalCents),
                                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                                ),
                            ],
                          ),
                          // Arquivar/desarquivar (pedido do Franck) — cabe
                          // em qualquer status, por isso fica separado do
                          // fluxo de aprovar/recusar/avaliar abaixo.
                          PopupMenuButton<void>(
                            icon: const Icon(Icons.more_vert, size: 18, color: AppColors.muted),
                            padding: EdgeInsets.zero,
                            itemBuilder: (context) => [
                              PopupMenuItem(
                                onTap: () => _setArchived(budget, !budget.archivedByClient),
                                child: Text(budget.archivedByClient ? 'Desarquivar' : 'Arquivar'),
                              ),
                            ],
                          ),
                        ],
                      ),
                      // Só serviço CONCLUÍDO libera avaliação (ver
                      // BudgetRequestsRepository.hasAcceptedBudgetWith) —
                      // leva pro perfil público, onde a seção de avaliação
                      // de verdade mora (evita duplicar o formulário de
                      // estrelas em duas telas).
                      footer: _buildFooter(budget, awaitingDecision: awaitingDecision, canRate: canRate),
                    );
                  },
                    );
                  },
                );
              },
            ),
    );
  }
}

/// QR Code Pix pronto (já montado pelo servidor — ver `Budget.
/// paymentPixPayload`/`functions/src/jobs.ts`), mostrado direto em "Meus
/// orçamentos" — pedido do Franck: "deve aparecer em meus orçamentos o
/// qrcode pra pagar. deve ser enviado via app" (antes só dava pra pagar
/// escaneando a tela do PRESTADOR presencialmente, ver
/// JobDetailsSheet/_PaymentQrCode). Depois que o prestador confirma o
/// recebimento (`Budget.paymentPaidAt`, serviço concluído), vira um aviso
/// de "pago" em vez do QR Code — evita alguém pagar de novo por engano.
class _PaymentSection extends StatelessWidget {
  const _PaymentSection({required this.budget});

  final Budget budget;

  @override
  Widget build(BuildContext context) {
    if (budget.paymentPaidAt != null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.success.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          children: [
            Icon(Icons.check_circle_outline, size: 18, color: AppColors.success),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Pagamento confirmado pelo prestador.',
                style: TextStyle(fontSize: 12.5, color: AppColors.success, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
    }

    final payload = budget.paymentPixPayload;
    if (payload == null) return const SizedBox.shrink();
    final amountCents = budget.paymentAmountCents ?? budget.totalCents;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.muted.withValues(alpha: 0.15)),
      ),
      child: Column(
        children: [
          const Text('Pagamento via Pix disponível', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text(
            'Escaneie com o app do seu banco ou copie o código abaixo.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.5, color: AppColors.muted),
          ),
          const SizedBox(height: 12),
          QrImageView(data: payload, size: 160, backgroundColor: Colors.white),
          const SizedBox(height: 12),
          Text(
            formatCentsBRL(amountCents),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.primary),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: payload));
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('Código Pix copiado!')));
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copiar código Pix'),
          ),
        ],
      ),
    );
  }
}

/// Orçamento completo (itens, quantidade, preço, desconto, total,
/// observações) — pedido do Franck: "não consegue visualizar o
/// orçamento, somente se eu enviar o pdf". Mesma informação do PDF
/// (`buildBudgetPdf`), só que direto no app, sem precisar o prestador
/// gerar/compartilhar nada.
class _BudgetDetailSheet extends StatelessWidget {
  const _BudgetDetailSheet({required this.budget});

  final Budget budget;

  @override
  Widget build(BuildContext context) {
    final category = budget.category != null ? serviceCategoryFromWire(budget.category!) : null;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.muted.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    budget.providerName ?? 'Prestador',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                  ),
                ),
                // Mesmo selo (AditivoBadge) que o prestador vê ao
                // editar (ver BudgetFormScreen) — o cliente também
                // precisa saber que o valor foi revisado desde o pedido
                // original.
                if (budget.revisionNumber > 0) AditivoBadge(number: budget.revisionNumber),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              category != null ? '${category.label} · ${formatDateDdMmYyyy(budget.date)}' : formatDateDdMmYyyy(budget.date),
              style: const TextStyle(color: AppColors.muted, fontSize: 13),
            ),
            if ((budget.addressText ?? '').isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.location_on_outlined, size: 16, color: AppColors.muted),
                  const SizedBox(width: 6),
                  Expanded(child: Text(budget.addressText!, style: const TextStyle(fontSize: 13))),
                ],
              ),
            ],
            const SizedBox(height: 18),
            const Text('Itens', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.ink)),
            const SizedBox(height: 8),
            // Pedido do Franck: "eu sempre preciso ver o orçamento
            // original e o aditivo... seja como um item a mais no
            // orçamento, marcando como aditivo" — cada item acrescentado
            // por um aditivo (ver BudgetItem.aditivoNumber) ganha o
            // mesmo selo aqui, ao lado dos itens originais (nunca
            // escondidos).
            for (final item in budget.items)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(item.description,
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                              ),
                              if (item.aditivoNumber != null) ...[
                                const SizedBox(width: 8),
                                AditivoBadge(number: item.aditivoNumber!, compact: true),
                              ],
                            ],
                          ),
                          Text(item.quantityLabel, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                        ],
                      ),
                    ),
                    Text(formatCentsBRL(item.totalCents), style: const TextStyle(fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Subtotal', style: TextStyle(fontSize: 13, color: AppColors.muted)),
                Text(formatCentsBRL(budget.subtotalCents), style: const TextStyle(fontSize: 13, color: AppColors.muted)),
              ],
            ),
            if (budget.discountCents > 0) ...[
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Desconto', style: TextStyle(fontSize: 13, color: AppColors.muted)),
                  Text('- ${formatCentsBRL(budget.discountCents)}', style: const TextStyle(fontSize: 13, color: AppColors.muted)),
                ],
              ),
            ],
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.primary)),
                Text(
                  formatCentsBRL(budget.totalCents),
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.primary),
                ),
              ],
            ),
            if ((budget.observations ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('Observações', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.ink)),
              const SizedBox(height: 4),
              Text(budget.observations!.trim(), style: const TextStyle(fontSize: 13, color: AppColors.ink)),
            ],
          ],
        ),
      ),
    );
  }
}
