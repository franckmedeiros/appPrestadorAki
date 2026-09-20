import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_theme.dart';
import '../../core/currency_text_utils.dart';
import '../../core/date_text_utils.dart';
import '../agenda/appointments_repository.dart';
import '../agenda/models/appointment.dart';
import '../budgets/budgets_repository.dart';
import '../budgets/models/budget.dart';
import '../jobs/jobs_repository.dart';
import '../jobs/models/job.dart';
import '../marketplace/widgets/provider_listing_card.dart' show abrirWhatsapp;
import 'models/customer.dart';

/// A página de um cliente: contato, o que vem a seguir, quanto ele já
/// pagou, quanto deve, e tudo que já foi feito pra ele.
///
/// POR QUE ESTA TELA EXISTE: "Clientes" era um cadastro — nome, telefone,
/// endereço — e mais nada. Pra saber se o João já pagou, o prestador
/// precisava abrir Orçamentos, achar os do João, abrir Serviços, cruzar na
/// cabeça. A informação existia, espalhada. Aqui ela se junta, e a
/// pergunta "quem me deve dinheiro?" passa a ter resposta por pessoa, não
/// só um total no Financeiro.
///
/// NADA NOVO É GRAVADO. Tudo vem do que o app já tinha: `Customer`, os
/// orçamentos daquele cliente, os serviços nascidos deles e os
/// compromissos marcados.
///
/// COMO OS SERVIÇOS SE LIGAM AO CLIENTE: `Job` não tem `customerId` — só
/// `customerName`, que é um retrato do nome na hora do aceite. Casar por
/// nome seria frágil (dois "João Silva", um nome corrigido depois). Então
/// a ligação é feita pelo ORÇAMENTO: `Budget.customerId` diz de quem é, e
/// `Job.budgetId` aponta pro orçamento que o originou. Nome nenhum é
/// comparado.
class CustomerDetailScreen extends StatelessWidget {
  const CustomerDetailScreen({super.key, required this.customer});

  final Customer customer;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Cliente'),
        actions: [
          IconButton(
            tooltip: 'Editar cadastro',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => context.push('/clientes/editar', extra: customer),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _CartaoDeContato(customer: customer),
          const SizedBox(height: 16),
          _ProximoCompromisso(customer: customer),
          const SizedBox(height: 16),
          _HistoricoEFinanceiro(customer: customer),
        ],
      ),
    );
  }
}

class _CartaoDeContato extends StatelessWidget {
  const _CartaoDeContato({required this.customer});

  final Customer customer;

  /// WhatsApp quando houver; senão o telefone comum. Um prestador que
  /// cadastrou só "telefone" não deveria ficar sem botão nenhum.
  String? get _numeroParaWhatsapp {
    final w = (customer.whatsapp ?? '').trim();
    if (w.isNotEmpty) return w;
    final p = (customer.phone ?? '').trim();
    return p.isEmpty ? null : p;
  }

  Future<void> _ligar(BuildContext context, String numero) async {
    final digits = numero.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return;
    final abriu = await launchUrl(Uri(scheme: 'tel', path: digits));
    if (!abriu && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir o telefone.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final numero = _numeroParaWhatsapp;
    final local = customer.locationLabel;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.muted.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.primary, AppColors.primaryDark],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  _iniciais(customer.name),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customer.name.isEmpty ? 'Cliente' : customer.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    if (local.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(Icons.location_on_outlined,
                              size: 13, color: AppColors.muted),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              local,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
                            ),
                          ),
                        ],
                      ),
                    ],
                    // Selo só pra quem veio do marketplace: explica por que
                    // esse cadastro apareceu sozinho na lista.
                    if (customer.clientUid != null) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'Cliente do app',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (numero != null) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => abrirWhatsapp(context, numero),
                    icon: const Icon(Icons.chat_outlined, size: 18, color: AppColors.ink),
                    label: const Text('WhatsApp', style: TextStyle(color: AppColors.ink)),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                      side: BorderSide(color: AppColors.muted.withValues(alpha: 0.3)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _ligar(context, numero),
                    icon: const Icon(Icons.call_outlined, size: 18, color: AppColors.ink),
                    label: const Text('Ligar', style: TextStyle(color: AppColors.ink)),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                      side: BorderSide(color: AppColors.muted.withValues(alpha: 0.3)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              numero,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ],
        ],
      ),
    );
  }

  static String _iniciais(String nome) {
    final partes = nome.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (partes.isEmpty) return '?';
    if (partes.length == 1) return partes.first.substring(0, 1).toUpperCase();
    return (partes.first.substring(0, 1) + partes.last.substring(0, 1)).toUpperCase();
  }
}

/// O próximo compromisso marcado com este cliente.
class _ProximoCompromisso extends StatefulWidget {
  const _ProximoCompromisso({required this.customer});

  final Customer customer;

  @override
  State<_ProximoCompromisso> createState() => _ProximoCompromissoState();
}

class _ProximoCompromissoState extends State<_ProximoCompromisso> {
  /// Do início de HOJE em diante, não de "agora": um serviço marcado pras
  /// 9h continua sendo o próximo compromisso às 10h, quando o prestador
  /// ainda está nele.
  late final Stream<List<Appointment>> _stream =
      context.read<AppointmentsRepository>().watchRange(
            from: DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day),
            to: DateTime(DateTime.now().year + 1, DateTime.now().month, DateTime.now().day),
          );

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Appointment>>(
      stream: _stream,
      builder: (context, snapshot) {
        final proximos = (snapshot.data ?? const <Appointment>[])
            .where((a) =>
                a.customerId == widget.customer.id &&
                a.status != AppointmentStatus.cancelado)
            .toList()
          ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));

        if (proximos.isEmpty) return const SizedBox.shrink();
        final a = proximos.first;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              const Icon(Icons.event_available_outlined, color: AppColors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Próximo compromisso',
                      style: TextStyle(fontSize: 11.5, color: AppColors.muted),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${formatDateDdMmYyyy(a.scheduledAt)} às '
                      '${a.scheduledAt.hour.toString().padLeft(2, '0')}:'
                      '${a.scheduledAt.minute.toString().padLeft(2, '0')} — ${a.type.label}',
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Dinheiro e histórico — as duas coisas saem da mesma consulta, então
/// vivem no mesmo widget em vez de repetir a leitura.
class _HistoricoEFinanceiro extends StatefulWidget {
  const _HistoricoEFinanceiro({required this.customer});

  final Customer customer;

  @override
  State<_HistoricoEFinanceiro> createState() => _HistoricoEFinanceiroState();
}

class _HistoricoEFinanceiroState extends State<_HistoricoEFinanceiro> {
  late final Stream<List<Budget>> _orcamentos = context.read<BudgetsRepository>().watchAll();
  late final Stream<List<Job>> _servicos = context.read<JobsRepository>().watchAll();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Budget>>(
      stream: _orcamentos,
      builder: (context, orcamentosSnap) {
        if (orcamentosSnap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final doCliente = (orcamentosSnap.data ?? const <Budget>[])
            .where((b) => b.customerId == widget.customer.id)
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));

        final idsDosOrcamentos = doCliente.map((b) => b.id).toSet();

        return StreamBuilder<List<Job>>(
          stream: _servicos,
          builder: (context, servicosSnap) {
            final servicos = (servicosSnap.data ?? const <Job>[])
                .where((j) => j.budgetId != null && idsDosOrcamentos.contains(j.budgetId))
                .toList();

            final recebido = servicos
                .where((j) => j.paidAt != null)
                .fold<int>(0, (s, j) => s + j.totalCents);
            final aReceber = servicos
                .where((j) => j.status == JobStatus.aguardandoPagamento)
                .fold<int>(0, (s, j) => s + j.totalCents);

            // Serviço indexado pelo orçamento que o gerou, pra cada linha
            // do histórico saber em que pé está a execução.
            final servicoPorOrcamento = <String, Job>{
              for (final j in servicos)
                if (j.budgetId != null) j.budgetId!: j,
            };

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _Tile(
                        rotulo: 'Já pagou',
                        valor: formatCentsBRL(recebido),
                        cor: AppColors.success,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _Tile(
                        rotulo: 'Deve',
                        valor: formatCentsBRL(aReceber),
                        cor: aReceber == 0 ? AppColors.muted : AppColors.warning,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                const Text(
                  'Histórico',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 10),
                if (doCliente.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.muted.withValues(alpha: 0.12)),
                    ),
                    child: const Text(
                      'Nenhum orçamento para este cliente ainda.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: AppColors.muted),
                    ),
                  )
                else
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.muted.withValues(alpha: 0.12)),
                    ),
                    child: Column(
                      children: [
                        for (var i = 0; i < doCliente.length; i++) ...[
                          if (i > 0)
                            Divider(
                              height: 1,
                              color: AppColors.muted.withValues(alpha: 0.12),
                            ),
                          _LinhaDoHistorico(
                            orcamento: doCliente[i],
                            servico: servicoPorOrcamento[doCliente[i].id],
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.rotulo, required this.valor, required this.cor});

  final String rotulo;
  final String valor;
  final Color cor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cor.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(rotulo, style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              valor,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: cor),
            ),
          ),
        ],
      ),
    );
  }
}

class _LinhaDoHistorico extends StatelessWidget {
  const _LinhaDoHistorico({required this.orcamento, this.servico});

  final Budget orcamento;
  final Job? servico;

  /// O que contar de estado. O SERVIÇO manda quando existe: uma vez
  /// aceito, o que importa é a execução ("Concluído", "Em andamento"), não
  /// que o orçamento segue marcado como "Aceito".
  String get _situacao => servico?.status.label ?? (orcamento.status?.label ?? 'Rascunho');

  Color get _cor => servico?.status.color ?? AppColors.muted;

  @override
  Widget build(BuildContext context) {
    final descricao = (orcamento.requestDescription ?? '').trim();
    final titulo = descricao.isNotEmpty
        ? descricao
        : (orcamento.items.isNotEmpty
            ? orcamento.items.first.description
            : 'Orçamento ${formatDateDdMmYyyy(orcamento.date)}');

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13.5, color: AppColors.ink),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      formatDateDdMmYyyy(orcamento.date),
                      style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
                    ),
                    const SizedBox(width: 8),
                    Container(width: 3, height: 3, decoration: const BoxDecoration(
                      color: AppColors.muted, shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        _situacao,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: _cor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                // O valor do SERVIÇO quando existe: ele já inclui
                // aditivos aprovados depois do orçamento original.
                formatCentsBRL(servico?.totalCents ?? orcamento.totalCents),
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              if (servico?.paidAt != null) ...[
                const SizedBox(height: 3),
                const Text(
                  'pago',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: AppColors.success,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
