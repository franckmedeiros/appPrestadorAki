import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/app_theme.dart';
import '../../core/auth_controller.dart';
import '../../core/currency_text_utils.dart';
import '../../core/pix_payload.dart';
import 'jobs_repository.dart';
import 'models/job.dart';

/// Painel de detalhes + ações de um Job — aberto ao tocar num card, tanto
/// no Kanban de "Serviços" quanto (pedido do Franck) direto no card de um
/// compromisso do Dashboard. As ações disponíveis mudam de acordo com a
/// etapa atual (ver `_actionsFor`); é aqui que o QR Code Pix aparece
/// quando o serviço está "Aguardando pagamento". Extraído de
/// JobsKanbanScreen pra virar um widget público reaproveitável — mesmo
/// fluxo guiado (com os gates de negócio de cada transição) em vez de um
/// seletor livre de status, que deixaria escapar coisas como o QR Code
/// ou o `markPaidNow`/`markCompletedNow` do aceite de pagamento.
class JobDetailsSheet extends StatefulWidget {
  const JobDetailsSheet({super.key, required this.job});

  final Job job;

  @override
  State<JobDetailsSheet> createState() => _JobDetailsSheetState();
}

class _JobDetailsSheetState extends State<JobDetailsSheet> {
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
