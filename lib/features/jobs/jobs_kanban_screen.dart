import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/app_theme.dart';
import '../../core/auth_controller.dart';
import '../../core/currency_text_utils.dart';
import '../../core/pix_payload.dart';
import '../../widgets/app_list_card.dart';
import 'jobs_repository.dart';
import 'models/job.dart';

/// Módulo "Serviços" (pedido do Franck) — no lugar do antigo atalho
/// "Pedidos" do Dashboard: um Kanban dos serviços em execução, que nascem
/// automaticamente no aceite final de um orçamento (ver
/// `BudgetsRepository.acceptFinal`/`JobsRepository`). Sem arrastar e
/// soltar entre as raias — o prestador toca no card e escolhe a próxima
/// etapa num painel embaixo (mais simples e confiável no celular do que
/// um drag-and-drop de verdade).
class JobsKanbanScreen extends StatelessWidget {
  const JobsKanbanScreen({super.key});

  static const _columns = [
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
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final status in _columns)
                  _KanbanColumn(
                    status: status,
                    jobs: jobs.where((job) => job.status == status).toList(),
                  ),
              ],
            ),
          );
        },
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

class _KanbanColumn extends StatelessWidget {
  const _KanbanColumn({required this.status, required this.jobs});

  final JobStatus status;
  final List<Job> jobs;

  Color get _headerColor => switch (status) {
        JobStatus.novo => AppColors.primary,
        JobStatus.emAndamento => AppColors.warning,
        JobStatus.interrompido => AppColors.danger,
        JobStatus.aguardandoPagamento => AppColors.warning,
        JobStatus.concluido => AppColors.success,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      margin: const EdgeInsets.only(right: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: _headerColor.withValues(alpha: 0.12),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    status.label,
                    style: TextStyle(fontWeight: FontWeight.w700, color: _headerColor),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: _headerColor, borderRadius: BorderRadius.circular(10)),
                  child: Text('${jobs.length}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
          Container(
            constraints: const BoxConstraints(minHeight: 80),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
              border: Border.all(color: _headerColor.withValues(alpha: 0.15)),
            ),
            child: jobs.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('Vazio', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                  )
                : Column(
                    children: [
                      for (final job in jobs)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _JobCard(job: job),
                        ),
                    ],
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

  @override
  Widget build(BuildContext context) {
    return AppListCard(
      leading: AppListCard.iconAvatar(Icons.build_outlined),
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
        builder: (context) => _JobDetailsSheet(job: job),
      ),
    );
  }
}

/// Painel de detalhes + ações — aberto ao tocar num card. As ações
/// disponíveis mudam de acordo com a etapa atual (ver `_actionsFor`); é
/// aqui que o QR Code Pix aparece quando o serviço está "Aguardando
/// pagamento".
class _JobDetailsSheet extends StatefulWidget {
  const _JobDetailsSheet({required this.job});

  final Job job;

  @override
  State<_JobDetailsSheet> createState() => _JobDetailsSheetState();
}

class _JobDetailsSheetState extends State<_JobDetailsSheet> {
  bool _busy = false;

  Future<void> _changeStatus(
    JobStatus status, {
    bool markPaidNow = false,
    bool markCompletedNow = false,
  }) async {
    setState(() => _busy = true);
    try {
      await context.read<JobsRepository>().updateStatus(
            widget.job.id,
            status,
            markPaidNow: markPaidNow,
            markCompletedNow: markCompletedNow,
          );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final job = widget.job;
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
                decoration: BoxDecoration(color: AppColors.muted.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Text(job.customerName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
            const SizedBox(height: 4),
            Text(job.status.label, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
            const SizedBox(height: 16),
            if (job.category != null) _DetailRow(icon: Icons.category_outlined, text: job.category!),
            if (job.addressText != null && job.addressText!.isNotEmpty)
              _DetailRow(icon: Icons.place_outlined, text: job.addressText!),
            _DetailRow(icon: Icons.payments_outlined, text: formatCentsBRL(job.totalCents)),
            const SizedBox(height: 20),
            if (job.status == JobStatus.aguardandoPagamento) ...[
              _PaymentQrCode(job: job),
              const SizedBox(height: 20),
            ],
            if (_busy)
              const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()))
            else
              ..._actionsFor(job),
          ],
        ),
      ),
    );
  }

  List<Widget> _actionsFor(Job job) {
    switch (job.status) {
      case JobStatus.novo:
        return [
          ElevatedButton.icon(
            onPressed: () => _changeStatus(JobStatus.emAndamento),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Iniciar atendimento'),
          ),
        ];
      case JobStatus.emAndamento:
        return [
          ElevatedButton.icon(
            onPressed: () => _changeStatus(JobStatus.aguardandoPagamento),
            icon: const Icon(Icons.qr_code),
            label: const Text('Concluir execução e cobrar'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => _changeStatus(JobStatus.interrompido),
            icon: const Icon(Icons.pause),
            label: const Text('Interromper'),
          ),
        ];
      case JobStatus.interrompido:
        return [
          ElevatedButton.icon(
            onPressed: () => _changeStatus(JobStatus.emAndamento),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Retomar atendimento'),
          ),
        ];
      case JobStatus.aguardandoPagamento:
        return [
          ElevatedButton.icon(
            onPressed: () => _changeStatus(
              JobStatus.concluido,
              markPaidNow: true,
              markCompletedNow: true,
            ),
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Confirmar pagamento e concluir'),
          ),
        ];
      case JobStatus.concluido:
        return [
          Text(
            job.completedAt != null
                ? 'Concluído em ${_formatDate(job.completedAt!)}. O cliente foi avisado pra avaliar o serviço.'
                : 'Serviço concluído.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
          ),
        ];
    }
  }

  String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.muted),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13.5))),
        ],
      ),
    );
  }
}

/// QR Code Pix montado a partir da chave cadastrada pelo prestador (ver
/// EditProfileScreen — campo "Chave Pix") + o valor do serviço. Sem chave
/// cadastrada, mostra um aviso em vez de um QR Code inválido/vazio.
class _PaymentQrCode extends StatelessWidget {
  const _PaymentQrCode({required this.job});

  final Job job;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: context.read<AuthController>().fetchOwnProfileData(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final pixKey = snapshot.data?['pixKey'] as String?;
        if (pixKey == null || pixKey.trim().isEmpty) {
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFFFF4E5), borderRadius: BorderRadius.circular(12)),
            child: const Text(
              'Cadastre uma chave Pix em "Editar perfil" pra gerar o QR Code de cobrança.',
              style: TextStyle(fontSize: 12.5),
            ),
          );
        }
        final merchantName = context.read<AuthController>().displayName;
        final payload = PixPayload.build(
          pixKey: pixKey,
          amountCents: job.totalCents,
          merchantName: merchantName,
          referenceLabel: job.id,
        );
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.muted.withValues(alpha: 0.15)),
          ),
          child: Column(
            children: [
              const Text('Cobrança via Pix', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              QrImageView(data: payload, size: 180, backgroundColor: Colors.white),
              const SizedBox(height: 12),
              Text(
                formatCentsBRL(job.totalCents),
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
      },
    );
  }
}
