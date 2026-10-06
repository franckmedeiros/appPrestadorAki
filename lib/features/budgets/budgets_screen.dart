import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/app_theme.dart';
import '../../core/currency_text_utils.dart';
import '../../core/date_text_utils.dart';
import '../../widgets/app_list_card.dart';
import '../../widgets/botao_com_seta.dart';
import '../../widgets/cabecalho_de_tela.dart';
import '../../widgets/selo_de_estado.dart';
import '../jobs/job_status_chip.dart';
import '../jobs/models/job.dart';
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

  /// Etapa do serviço no rodapé do card + atalho pra "Serviços".
  ///
  /// Pedido do Franck: do lado do prestador, um orçamento "Aceito"
  /// também não contava o resto da história — dava pra achar que o
  /// trabalho já tinha acabado, quando na verdade ele ainda nem começou.
  /// Agora o card mostra a etapa real e oferece o caminho pra agir.
  ///
  /// A etapa vem do próprio orçamento (`Budget.serviceStatus`, espelhado
  /// pelas Cloud Functions — ver functions/src/jobs.ts). O prestador
  /// poderia ler os serviços direto, já que eles são dele; usar o mesmo
  /// campo do cliente evita uma segunda consulta e garante que os dois
  /// lados mostrem exatamente a mesma coisa.
  ///
  /// Null quando ainda não existe serviço — orçamentos pendentes,
  /// enviados ou recusados não têm o que mostrar aqui.
  /// Arquivar/desarquivar pelo MENU, convivendo com o deslize (decisão do
  /// Franck de manter os dois): deslizar é rápido pra quem já sabe, mas é
  /// um gesto invisível que ninguém descobre sozinho — o menu é o caminho
  /// que se acha olhando.
  ///
  /// Fica no rodapé do card, e não ao lado do selo de status como na tela
  /// do cliente, por um motivo concreto: o `trailing` daqui já está no
  /// limite. Tem um `ConstrainedBox` de 128px ali justamente porque um
  /// rótulo de status comprido espremia o nome do cliente até quebrar
  /// letra por letra; enfiar mais 28px de menu naquele espaço traria o
  /// problema de volta.
  Widget _menuArquivar(Budget budget) {
    final arquivado = budget.archivedByProvider;
    return PopupMenuButton<void>(
      icon: const Icon(Icons.more_vert, size: 18, color: AppColors.muted),
      padding: EdgeInsets.zero,
      tooltip: arquivado ? 'Desarquivar' : 'Arquivar',
      itemBuilder: (context) => [
        PopupMenuItem(
          // `_archive`, e não `_setArchived` direto: é ele que tira o card
          // da lista na hora, o que o `Dismissible` exige pra não
          // reaparecer com a mesma key e derrubar o app.
          onTap: () => _archive(budget, !arquivado),
          child: Text(arquivado ? 'Desarquivar' : 'Arquivar'),
        ),
      ],
    );
  }

  /// Rodapé do card: o andamento do serviço (quando existe) e o menu de
  /// arquivar (onde faz sentido). Null quando não há nem um nem outro —
  /// o AppListCard omite o rodapé inteiro nesse caso.
  Widget? _rodape(Budget budget) {
    final status = budget.status;
    final servico = _rodapeDoServico(budget);
    // Mesma regra do deslize (`_canArchive`), mais a lista de arquivados,
    // onde sempre dá pra devolver.
    final podeArquivar = _showArchived || _canArchive(budget);
    if (status == null && servico == null && !podeArquivar) return null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // O selo de estado desceu do canto direito pro rodapé do
            // card. Lá em cima ele disputava largura com o nome do
            // cliente — tanto que precisava de um `ConstrainedBox` de
            // 128px, e mesmo assim rótulos como "Aditivo enviado —
            // aguardando aprovação" quebravam em duas linhas de letra
            // miúda. Aqui embaixo ele tem a largura do card inteiro e
            // pode ser escrito por extenso.
            if (status != null)
              Flexible(
                child: SeloDeEstado(status.label, tom: _tomDoStatus(status)),
              )
            else
              const Spacer(),
            if (podeArquivar) _menuArquivar(budget),
          ],
        ),
        if (servico != null) ...[const SizedBox(height: 10), servico],
      ],
    );
  }

  Widget? _rodapeDoServico(Budget budget) {
    final wire = budget.serviceStatus;
    if (wire == null || wire.isEmpty) return null;
    return Row(
      children: [
        JobStatusChip(status: jobStatusFromWire(wire)),
        const Spacer(),
        TextButton.icon(
          // Leva pro Kanban de Serviços, onde ele avança a etapa. Não dá
          // pra abrir o serviço específico direto: a tela agrupa por
          // raia e não recebe um id — chegar nela já resolve o "e agora,
          // onde eu mexo nisso?".
          onPressed: () => context.push('/servicos'),
          icon: const Icon(Icons.arrow_forward, size: 15),
          label: const Text('Ver serviço'),
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size(0, 30),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  /// O tom do selo de cada estado.
  ///
  /// Antes cada estado tinha uma cor solta do Material (laranja, azul,
  /// verde, roxo). Seis cores sem parentesco nenhum entre si, e nenhuma
  /// delas dizendo o que importa: se a bola está com VOCÊ ou com o
  /// cliente. Agora são três grupos — o que precisa de você (marca), o
  /// que espera o cliente (espera) e o que já acabou (positivo ou
  /// negativo) — que é a mesma divisão que a lista usa pra ordenar.
  TomDoSelo _tomDoStatus(BudgetStatus status) => switch (status) {
        BudgetStatus.pendente => TomDoSelo.marca,
        BudgetStatus.aprovado => TomDoSelo.marca,
        BudgetStatus.enviado => TomDoSelo.espera,
        BudgetStatus.aditivoEnviado => TomDoSelo.espera,
        BudgetStatus.aceito => TomDoSelo.positivo,
        BudgetStatus.recusado => TomDoSelo.negativo,
      };

  /// A linha de apoio embaixo do nome do cliente: o número do documento
  /// e o valor ("Nº 0042 · R$ 1.500,00").
  ///
  /// Num orçamento ainda pendente não existe nem número nem valor — ele
  /// é um PEDIDO que chegou e ainda não foi preenchido. Aí a linha mostra
  /// o que o cliente escreveu, que é a única coisa que há pra ler.
  String _linhaDeApoio(Budget budget) {
    if (budget.status == BudgetStatus.pendente) {
      final pedido = (budget.requestDescription ?? '').trim();
      if (pedido.isNotEmpty) return pedido;
      return formatDateLong(budget.date);
    }
    final partes = <String>[];
    final numero = budget.documentNumber;
    if (numero != null && numero > 0) {
      partes.add('Nº ${numero.toString().padLeft(4, '0')}');
    }
    if (budget.totalCents > 0) partes.add(formatCentsBRL(budget.totalCents));
    if (partes.isEmpty) return formatDateLong(budget.date);
    return partes.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: CabecalhoDeTela(
              titulo: _showArchived ? 'Arquivados' : 'Orçamentos',
              area: AreaDoApp.prestador,
              aoVoltar: context.canPop() ? () => context.pop() : null,
              acao: IconButton(
                tooltip: _showArchived ? 'Ver orçamentos ativos' : 'Ver arquivados',
                icon: Icon(
                  _showArchived ? Icons.inbox_outlined : Icons.archive_outlined,
                  size: 22,
                ),
                color: AppColors.primary,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                onPressed: () => setState(() => _showArchived = !_showArchived),
              ),
            ),
          ),
          Expanded(child: _lista()),
          // O botão deixou de ser o círculo flutuante do Material e virou
          // uma barra fixa no pé da tela, como no desenho. O "+" sozinho
          // num canto não dizia o que ia criar; aqui está escrito.
          if (!_showArchived)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppMetrics.margemLateral,
                8,
                AppMetrics.margemLateral,
                12,
              ),
              child: BotaoComSeta(
                rotulo: 'Novo orçamento',
                icone: Icons.add,
                comCaixa: false,
                aoTocar: () => _openBudget(null),
              ),
            ),
        ],
      ),
    );
  }

  Widget _lista() {
    return StreamBuilder<List<Budget>>(
        stream: _stream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ListView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppMetrics.margemLateral,
              ),
              children: [
                const SizedBox(height: 60),
                const Icon(Icons.error_outline, size: 40, color: AppColors.danger),
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
              padding: const EdgeInsets.symmetric(
                horizontal: AppMetrics.margemLateral,
              ),
              children: [
                const SizedBox(height: 60),
                Icon(
                  _showArchived ? Icons.archive_outlined : Icons.description_outlined,
                  size: 40,
                  color: AppColors.muted,
                ),
                const SizedBox(height: 12),
                Text(
                  _showArchived
                      ? 'Nenhum orçamento arquivado.'
                      : 'Nenhum orçamento ainda. Use o botão abaixo pra criar o primeiro.',
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
            padding: const EdgeInsets.fromLTRB(
              AppMetrics.margemLateral,
              0,
              AppMetrics.margemLateral,
              8,
            ),
            itemCount: budgets.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
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
                // Número e valor numa linha só embaixo do nome ("Nº 0042
                // · R$ 1.500,00"). Antes o valor ficava do lado direito,
                // empilhado embaixo do selo, e a data vinha aqui — mas
                // quem procura um orçamento numa lista procura pelo
                // cliente e pelo número, não pela data.
                subtitle: _linhaDeApoio(budget),
                trailing: const Icon(
                  Icons.chevron_right,
                  color: AppColors.muted,
                  size: 22,
                ),
                onTap: () => _openBudget(budget),
                footer: _rodape(budget),
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
                    color: archiving ? AppColors.borda : AppColors.primarySuave,
                    borderRadius: BorderRadius.circular(AppMetrics.raioDeCartao),
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
    );
  }
}
