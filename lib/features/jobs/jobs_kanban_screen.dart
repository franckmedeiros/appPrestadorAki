import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_theme.dart';
import '../../core/currency_text_utils.dart';
import '../../widgets/app_list_card.dart';
import 'job_details_sheet.dart';
import 'jobs_repository.dart';
import 'models/job.dart';

/// Módulo "Serviços" (pedido do Franck) — no lugar do antigo atalho
/// "Pedidos" do Dashboard: os serviços em execução, que nascem
/// automaticamente no aceite final de um orçamento (ver
/// `BudgetsRepository.acceptFinal`/`JobsRepository`). Sem arrastar e
/// soltar — o prestador toca no card e escolhe a próxima etapa num
/// painel embaixo (`JobDetailsSheet`, mais simples e confiável no
/// celular do que um drag-and-drop de verdade).
///
/// Era um Kanban de 5 colunas lado a lado, rolando na horizontal — o
/// Franck reclamou que "ficou estranho" no celular (era preciso rolar
/// pros dois lados pra ver tudo). Troquei por uma lista única, rolando só
/// na vertical, com cada etapa virando uma seção com cabeçalho colorido
/// (esboço aprovado por ele — ver o rascunho publicado no chat).
class JobsKanbanScreen extends StatefulWidget {
  const JobsKanbanScreen({super.key});

  @override
  State<JobsKanbanScreen> createState() => _JobsKanbanScreenState();
}

class _JobsKanbanScreenState extends State<JobsKanbanScreen> {
  static const _sections = [
    JobStatus.novo,
    JobStatus.emAndamento,
    JobStatus.interrompido,
    JobStatus.aguardandoPagamento,
    JobStatus.concluido,
  ];

  /// O stream é criado UMA vez: reconstruir a tela (ao alternar
  /// ativos/arquivados, por exemplo) não pode reabrir o listener do
  /// Firestore.
  late final Stream<List<Job>> _stream = context.read<JobsRepository>().watchAll();

  bool _mostrandoArquivados = false;

  /// Ids arquivando/desarquivando "otimisticamente" — somem da lista
  /// assim que a pessoa desliza, antes mesmo de o Firestore confirmar.
  /// Sem isso, um `Dismissible` recém-removido pode reaparecer com a
  /// MESMA `key` antes do stream reemitir, e o Flutter derruba o app com
  /// "A dismissed Dismissible widget is still part of the tree" — bug já
  /// enfrentado na tela de Orçamentos, mesmo padrão de solução.
  final Set<String> _arquivandoAgora = {};

  /// Só serviço CONCLUÍDO pode ser arquivado, mesma regra combinada pros
  /// orçamentos ("só os já concluídos"): o que ainda está em andamento,
  /// interrompido ou aguardando pagamento precisa de ação e não pode
  /// sumir da lista por um deslize sem querer.
  bool _podeArquivar(Job job) => job.status == JobStatus.concluido;

  void _arquivar(Job job, bool arquivar) {
    setState(() => _arquivandoAgora.add(job.id));
    unawaited(_gravarArquivamento(job, arquivar));
  }

  Future<void> _gravarArquivamento(Job job, bool arquivar) async {
    try {
      await context.read<JobsRepository>().setArchived(job.id, arquivar);
    } catch (e) {
      if (!mounted) return;
      setState(() => _arquivandoAgora.remove(job.id));
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          content: Text(arquivar
              ? 'Não foi possível arquivar: $e'
              : 'Não foi possível desarquivar: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ));
      return;
    }
    if (!mounted) return;
    setState(() => _arquivandoAgora.remove(job.id));
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(arquivar ? 'Serviço arquivado.' : 'Serviço desarquivado.'),
      ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_mostrandoArquivados ? 'Serviços arquivados' : 'Serviços'),
        actions: [
          IconButton(
            tooltip: _mostrandoArquivados ? 'Ver serviços ativos' : 'Ver arquivados',
            icon: Icon(_mostrandoArquivados ? Icons.inbox_outlined : Icons.archive_outlined),
            onPressed: () => setState(() => _mostrandoArquivados = !_mostrandoArquivados),
          ),
        ],
      ),
      body: StreamBuilder<List<Job>>(
        stream: _stream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Não foi possível carregar os serviços.\n${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ),
            );
          }
          final jobs = (snapshot.data ?? [])
              .where((job) => job.archived == _mostrandoArquivados)
              .where((job) => !_arquivandoAgora.contains(job.id))
              .toList();
          if (jobs.isEmpty) {
            return _mostrandoArquivados ? const _ArquivadosVazio() : const _EmptyState();
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final status in _sections)
                if (jobs.any((job) => job.status == status))
                  _StatusSection(
                    status: status,
                    jobs: jobs.where((job) => job.status == status).toList(),
                    // Arquivado: sempre pode desarquivar. Ativo: só
                    // desliza o que já foi concluído (ver `_podeArquivar`).
                    podeDeslizar: (job) => _mostrandoArquivados || _podeArquivar(job),
                    arquivando: !_mostrandoArquivados,
                    aoDeslizar: _arquivar,
                  ),
            ],
          );
        },
      ),
    );
  }
}

/// Uma etapa do Kanban (ex.: "Em andamento") como seção da lista: um
/// cabeçalho colorido (bolinha + nome + contagem, tingido a 12% de
/// opacidade — mesma paleta de `JobStatus.color`) seguido dos cards
/// dessa etapa. Etapas sem nenhum serviço não aparecem (ver o `if` na
/// tela) — não faz sentido mostrar uma seção vazia numa lista vertical
/// (diferente do Kanban antigo, onde as colunas ficavam todas visíveis
/// lado a lado mesmo vazias, pra dar noção do fluxo completo).
class _StatusSection extends StatelessWidget {
  const _StatusSection({
    required this.status,
    required this.jobs,
    required this.podeDeslizar,
    required this.arquivando,
    required this.aoDeslizar,
  });

  final JobStatus status;
  final List<Job> jobs;

  /// Se este card aceita o gesto de deslizar. Cards que não aceitam
  /// continuam só tocáveis, pra não sumirem por engano.
  final bool Function(Job) podeDeslizar;

  /// `true` na lista de ativos (deslizar arquiva), `false` na de
  /// arquivados (deslizar devolve).
  final bool arquivando;

  final void Function(Job job, bool arquivar) aoDeslizar;

  @override
  Widget build(BuildContext context) {
    final color = status.color;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    status.label,
                    style: TextStyle(fontWeight: FontWeight.w700, color: color, fontSize: 13),
                  ),
                ),
                Text(
                  '${jobs.length}',
                  style: TextStyle(fontWeight: FontWeight.w700, color: color, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          for (final job in jobs)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              // Concluído fica em opacidade reduzida — já não precisa de
              // ação, então some um pouco pra não competir visualmente
              // com o que ainda está em aberto (mesma ideia do rascunho).
              child: Opacity(
                opacity: status == JobStatus.concluido ? 0.75 : 1,
                child: podeDeslizar(job)
                    ? Dismissible(
                        key: ValueKey(job.id),
                        direction: DismissDirection.endToStart,
                        onDismissed: (_) => aoDeslizar(job, arquivando),
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          decoration: BoxDecoration(
                            color: (arquivando ? AppColors.muted : AppColors.primary)
                                .withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            arquivando ? Icons.archive_outlined : Icons.unarchive_outlined,
                            color: arquivando ? AppColors.muted : AppColors.primary,
                          ),
                        ),
                        child: _JobCard(job: job, aoArquivar: aoDeslizar),
                      )
                    : _JobCard(job: job, aoArquivar: null),
              ),
            ),
        ],
      ),
    );
  }
}

class _JobCard extends StatelessWidget {
  const _JobCard({required this.job, required this.aoArquivar});

  final Job job;

  /// Null quando este card não pode ser arquivado (serviço ainda em
  /// aberto) — aí o menu nem aparece, em vez de aparecer desabilitado.
  final void Function(Job job, bool arquivar)? aoArquivar;

  IconData get _icon => switch (job.status) {
        JobStatus.aguardandoPagamento => Icons.qr_code,
        JobStatus.concluido => Icons.check_circle_outline,
        _ => Icons.build_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final arquivar = aoArquivar;
    return AppListCard(
      leading: AppListCard.iconAvatar(_icon),
      title: job.customerName,
      subtitle: job.category ?? job.addressText,
      // Menu de arquivar ao lado da seta, convivendo com o deslize
      // (decisão do Franck de manter os dois caminhos): deslizar é rápido
      // pra quem já sabe, mas é invisível — ninguém descobre sozinho. A
      // seta continua ali porque é ela que diz "dá pra tocar e abrir".
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (arquivar != null)
            PopupMenuButton<void>(
              icon: const Icon(Icons.more_vert, size: 18, color: AppColors.muted),
              padding: EdgeInsets.zero,
              tooltip: job.archived ? 'Desarquivar' : 'Arquivar',
              itemBuilder: (context) => [
                PopupMenuItem(
                  onTap: () => arquivar(job, !job.archived),
                  child: Text(job.archived ? 'Desarquivar' : 'Arquivar'),
                ),
              ],
            ),
          const Icon(Icons.chevron_right, color: AppColors.muted, size: 20),
        ],
      ),
      footer: Text(
        formatCentsBRL(job.totalCents),
        style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink),
      ),
      onTap: () => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (context) => JobDetailsSheet(job: job),
      ),
    );
  }
}

/// Vazio da lista de arquivados — mensagem própria, porque o texto de
/// "nenhum serviço ainda" (que explica de onde vêm os serviços) mandaria
/// a pessoa procurar no lugar errado.
class _ArquivadosVazio extends StatelessWidget {
  const _ArquivadosVazio();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.archive_outlined, size: 40, color: AppColors.muted),
            SizedBox(height: 12),
            Text('Nenhum serviço arquivado',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            SizedBox(height: 6),
            Text(
              'Na lista de serviços, deslize um card concluído\npra guardá-lo aqui.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, fontSize: 13, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.build_outlined, color: AppColors.primary, size: 30),
            ),
            const SizedBox(height: 16),
            const Text('Nenhum serviço ainda', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 6),
            const Text(
              'Serviços aparecem aqui automaticamente assim que você der o\n'
              'aceite final de um orçamento.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
