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
class JobsKanbanScreen extends StatelessWidget {
  const JobsKanbanScreen({super.key});

  static const _sections = [
    JobStatus.novo,
    JobStatus.emAndamento,
    JobStatus.interrompido,
    JobStatus.aguardandoPagamento,
    JobStatus.concluido,
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Serviços')),
      body: StreamBuilder<List<Job>>(
        stream: context.read<JobsRepository>().watchAll(),
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
          final jobs = snapshot.data ?? [];
          if (jobs.isEmpty) {
            return const _EmptyState();
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final status in _sections)
                if (jobs.any((job) => job.status == status))
                  _StatusSection(
                    status: status,
                    jobs: jobs.where((job) => job.status == status).toList(),
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
  const _StatusSection({required this.status, required this.jobs});

  final JobStatus status;
  final List<Job> jobs;

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
                child: _JobCard(job: job),
              ),
            ),
        ],
      ),
    );
  }
}

class _JobCard extends StatelessWidget {
  const _JobCard({required this.job});

  final Job job;

  IconData get _icon => switch (job.status) {
        JobStatus.aguardandoPagamento => Icons.qr_code,
        JobStatus.concluido => Icons.check_circle_outline,
        _ => Icons.build_outlined,
      };

  @override
  Widget build(BuildContext context) {
    return AppListCard(
      leading: AppListCard.iconAvatar(_icon),
      title: job.customerName,
      subtitle: job.category ?? job.addressText,
      trailing: const Icon(Icons.chevron_right, color: AppColors.muted, size: 20),
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
