import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/app_theme.dart';
import '../../core/auth_controller.dart';
import '../../core/currency_text_utils.dart';
import '../../core/pix_payload.dart';
import '../budgets/budget_pdf.dart' show BudgetPdfProvider;
import '../budgets/budget_pdf_preview_screen.dart';
import '../budgets/budgets_repository.dart';
import '../marketplace/models/service_category.dart';
import 'job_status_chip.dart';
import 'jobs_repository.dart';
import 'models/job.dart';
import 'recibo_pdf.dart';

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
  bool _gerandoRecibo = false;

  /// Confere se o prestador já tem uma chave Pix cadastrada ANTES de
  /// deixar o serviço ir pra "Aguardando pagamento" — pedido do Franck:
  /// "quando o prestador for enviar o pagamento e não ter configurado a
  /// chave pix, avisar pro usuário para ajustar e não envia o pagamento".
  /// Antes disso a checagem só acontecia depois, dentro do QR Code
  /// (`_PaymentQrCode` — mostra um aviso em vez de QR vazio), mas a
  /// transição de status já tinha acontecido: o cliente via "Aguardando
  /// pagamento" sem ter como pagar de verdade. Mesmo `fetchOwnProfileData`
  /// que `_PaymentQrCode` usa, então lê o mesmo campo `pixKey`.
  Future<void> _startCharging() async {
    final profile = await context.read<AuthController>().fetchOwnProfileData();
    final pixKey = profile['pixKey'] as String?;
    if (pixKey == null || pixKey.trim().isEmpty) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Cadastre sua chave Pix'),
          content: const Text(
            'Antes de cobrar esse serviço, configure sua chave Pix em '
            '"Editar perfil" — sem ela não dá pra gerar o QR Code de '
            'cobrança e o cliente não vai conseguir pagar.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Entendi'),
            ),
          ],
        ),
      );
      return;
    }
    if (!mounted) return;
    await _changeStatus(JobStatus.aguardandoPagamento);
  }

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
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: AppColors.borda,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // O nome do cliente é o título desta folha, então ganha o
            // mesmo corpo dos títulos de tela. Antes era 18, do tamanho
            // de um subtítulo qualquer.
            Text(
              job.customerName,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 26,
                height: 1.1,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 14),
            // A etapa era uma linha de texto cinza, igual a todas as
            // outras. Virou selo: é o estado do serviço, a única coisa
            // aqui que muda a cada toque nos botões abaixo.
            Align(
              alignment: Alignment.centerLeft,
              child: JobStatusChip(status: job.status),
            ),
            const SizedBox(height: 14),
            if (job.category != null)
              _DetailRow(icon: Icons.category_outlined, text: job.category!),
            if (job.addressText != null && job.addressText!.isNotEmpty)
              _DetailRow(icon: Icons.place_outlined, text: job.addressText!),
            const SizedBox(height: 10),
            // O valor saía como mais uma linha de ícone + texto de 13,5,
            // do lado da categoria e do endereço. É o número que o
            // prestador confere antes de confirmar o pagamento.
            Text(
              formatCentsBRL(job.totalCents),
              style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                height: 1.1,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 20),
            // Pedido do Franck: "ter a opção de reenviar o pagamento e
            // ficar disponível sempre que o cliente/prestador precisar
            // ver" — antes sumia assim que o Job virava "concluído", sem
            // jeito de conferir/copiar o código Pix de novo depois (ex.:
            // cliente perdeu a mensagem, ou quer conferir o valor
            // cobrado). Continua não aparecendo nas etapas anteriores
            // (novo/em andamento/interrompido), só faz sentido depois que
            // a cobrança já foi gerada pelo menos uma vez.
            if (job.status == JobStatus.aguardandoPagamento || job.status == JobStatus.concluido) ...[
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
            onPressed: _startCharging,
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
          const SizedBox(height: 14),
          // O recibo só existe aqui, no serviço concluído: recibo é
          // comprovante de pagamento RECEBIDO, e emitir antes disso seria
          // dar quitação de dinheiro que não entrou.
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  onPressed: _gerandoRecibo ? null : () => _comORecibo(visualizar: true),
                  icon: _gerandoRecibo
                      ? const SizedBox(
                          height: 15,
                          width: 15,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.visibility_outlined, size: 17),
                  label: const Text('Ver recibo'),
                ),
              ),
              Expanded(
                child: TextButton.icon(
                  onPressed: _gerandoRecibo ? null : () => _comORecibo(visualizar: false),
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 17),
                  label: const Text('Enviar recibo'),
                ),
              ),
            ],
          ),
        ];
    }
  }

  /// Monta o recibo e abre pra ver, ou entrega pro compartilhar.
  ///
  /// O número é reservado aqui (ver
  /// `JobsRepository.garantirNumeroDeRecibo`) — na primeira emissão, e
  /// só nela. Sem número, não emite: recibo sem número não serve de
  /// comprovante, e imprimir um assim seria pior do que avisar que não
  /// deu.
  Future<void> _comORecibo({required bool visualizar}) async {
    setState(() => _gerandoRecibo = true);
    try {
      final job = widget.job;
      final jobs = context.read<JobsRepository>();
      final numero = job.reciboNumber ?? await jobs.garantirNumeroDeRecibo(job.id);
      if (numero == null) {
        if (mounted) _avisar('Não foi possível emitir o recibo agora. Tenta de novo.');
        return;
      }

      if (!mounted) return;
      final auth = context.read<AuthController>();
      final perfil = await auth.fetchOwnProfileData();

      if (!mounted) return;
      final budgetId = job.budgetId;
      final numeroDoOrcamento =
          budgetId == null ? null : await context.read<BudgetsRepository>().numeroDoDocumento(budgetId);

      final bytes = await buildReciboPdf(
        job,
        BudgetPdfProvider(
          name: auth.displayName,
          logoUrl: perfil['logoUrl'] as String?,
          subtitle: _subtituloDoCabecalho(perfil),
          cidade: _cidadeDoPrestador(perfil),
        ),
        numeroDoRecibo: numero,
        numeroDoOrcamento: numeroDoOrcamento,
      );

      if (!mounted) return;
      final nomeDoArquivo = 'recibo_${numero.toString().padLeft(4, '0')}_${job.customerName}.pdf';
      if (visualizar) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => BudgetPdfPreviewScreen(
              bytes: bytes,
              fileName: nomeDoArquivo,
              title: 'Recibo nº ${numero.toString().padLeft(4, '0')}',
            ),
          ),
        );
      } else {
        await Printing.sharePdf(bytes: bytes, filename: nomeDoArquivo);
      }
    } catch (_) {
      if (mounted) _avisar('Não foi possível gerar o recibo. Tenta de novo.');
    } finally {
      if (mounted) setState(() => _gerandoRecibo = false);
    }
  }

  void _avisar(String mensagem) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensagem)));
  }

  /// "Eletricista · Criciúma/SC" — mesma linha do cabeçalho do orçamento
  /// (ver BudgetFormScreen), pros dois documentos chegarem iguais no
  /// mesmo cliente.
  String? _subtituloDoCabecalho(Map<String, dynamic> perfil) {
    final categoriaId = (perfil['category'] as String? ?? '').trim();
    final categoria = categoriaId.isEmpty ? '' : serviceCategoryFromWire(categoriaId).label;
    final local = _cidadeDoPrestador(perfil) ?? '';
    final partes = [categoria, local].where((p) => p.isNotEmpty).toList();
    if (partes.isEmpty) return null;
    return partes.join(' · ');
  }

  String? _cidadeDoPrestador(Map<String, dynamic> perfil) {
    final cidade = (perfil['city'] as String? ?? '').trim();
    final uf = (perfil['state'] as String? ?? '').trim();
    final local = [cidade, uf].where((p) => p.isNotEmpty).join('/');
    return local.isEmpty ? null : local;
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
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 14, color: AppColors.ink),
            ),
          ),
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
            decoration: BoxDecoration(
              color: AppColors.warningSuave,
              borderRadius: BorderRadius.circular(AppMetrics.raioDeCartao),
            ),
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
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              job.status == JobStatus.concluido
                  ? 'Pagamento confirmado — Pix pra conferência'
                  : 'Cobrança via PIX',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 12),
            // O QR num cartão BRANCO, e não no creme do fundo: leitor de
            // QR Code espera preto sobre branco, e fundo creme reduz o
            // contraste que o aparelho do cliente precisa pra ler.
            Container(
              padding: const EdgeInsets.all(AppMetrics.paddingDeCartao),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppMetrics.raioDeCartao),
                border: Border.all(color: AppColors.borda),
              ),
              child: Column(
                children: [
                  QrImageView(
                    data: payload,
                    size: 190,
                    backgroundColor: Colors.white,
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Escaneie com o app do seu banco ou copie o código abaixo.',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            // Copiar virou uma linha de cartão, não um botão contornado:
            // ela tem a mesma largura e o mesmo canto dos cartões acima,
            // e deixa de competir com o botão de confirmar logo abaixo,
            // que é a ação de verdade desta tela.
            Material(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppMetrics.raioDeCartao),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppMetrics.raioDeCartao),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: payload));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Código Pix copiado!')),
                  );
                },
                child: Container(
                  height: AppMetrics.alturaDeControle,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(
                      AppMetrics.raioDeCartao,
                    ),
                    border: Border.all(color: AppColors.borda),
                  ),
                  child: const Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Copiar código PIX',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                      Icon(Icons.copy, size: 20, color: AppColors.primary),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
