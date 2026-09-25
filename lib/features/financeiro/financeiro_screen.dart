import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_theme.dart';
import '../../core/currency_text_utils.dart';
import '../jobs/jobs_repository.dart';
import '../jobs/models/job.dart';
import '../marketplace/models/service_category.dart';

/// Financeiro — quanto entrou, quanto falta entrar, e como isso se
/// comporta mês a mês.
///
/// NÃO EXISTE LANÇAMENTO MANUAL AQUI, de propósito. Todo número desta tela
/// é calculado dos serviços que o prestador já movimenta no Kanban: o
/// valor sai de `Job.totalCents` e a data de `Job.paidAt`, gravada no
/// momento em que ele confirma o pagamento (ver JobsRepository.updateStatus
/// / JobDetailsSheet). Ou seja, o financeiro se preenche sozinho enquanto
/// ele trabalha.
///
/// Essa foi a decisão de escopo com o Franck (20/09): um caixa completo,
/// com despesas digitadas à mão, só diz a verdade se a pessoa lançar tudo
/// — e prestador em campo não lança. Um relatório que se mantém sozinho
/// vale mais que um livro-caixa vazio. Se um dia as despesas entrarem,
/// entram por cima disto, sem refazer nada.
///
/// O GRÁFICO É O SELETOR DE MÊS. Tocar numa barra troca os números do
/// topo. Evita uma linha de filtros ocupando espaço pra fazer o que o
/// próprio gráfico já sabe fazer.
class FinanceiroScreen extends StatefulWidget {
  const FinanceiroScreen({super.key});

  @override
  State<FinanceiroScreen> createState() => _FinanceiroScreenState();
}

const _mesesCurtos = [
  'jan', 'fev', 'mar', 'abr', 'mai', 'jun',
  'jul', 'ago', 'set', 'out', 'nov', 'dez',
];

const _mesesLongos = [
  'janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho',
  'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro',
];

/// Quantos meses o gráfico mostra. Seis cabem num celular com rótulo
/// legível e já revelam sazonalidade (o mês fraco depois do feriado, a
/// alta do fim de ano) — doze espremeriam as barras a ponto de virar
/// enfeite.
const int _mesesNoGrafico = 6;

/// Um mês fechado do gráfico.
class _MesDeFaturamento {
  _MesDeFaturamento(this.inicio, this.recebidoCents, this.servicos);

  final DateTime inicio;
  final int recebidoCents;
  final int servicos;

  String get rotuloCurto => _mesesCurtos[inicio.month - 1];
  String get rotuloLongo => '${_mesesLongos[inicio.month - 1]} de ${inicio.year}';
}

class _FinanceiroScreenState extends State<FinanceiroScreen> {
  late final Stream<List<Job>> _servicos = context.read<JobsRepository>().watchAll();

  /// Índice do mês selecionado dentro da lista do gráfico. Começa no
  /// último (o mês corrente), que é o que o prestador quer ver ao abrir.
  int _mesSelecionado = _mesesNoGrafico - 1;

  /// Primeiro dia do mês, construído pelo calendário em vez de subtrair
  /// dias: 31 de março menos "um mês" precisa cair em fevereiro, e
  /// aritmética de 30 dias erra isso todo ano.
  DateTime _mesDeReferencia(int quantosMesesAtras) {
    final agora = DateTime.now();
    return DateTime(agora.year, agora.month - quantosMesesAtras, 1);
  }

  List<_MesDeFaturamento> _montarMeses(List<Job> jobs) {
    return List.generate(_mesesNoGrafico, (i) {
      final inicio = _mesDeReferencia(_mesesNoGrafico - 1 - i);
      final fim = DateTime(inicio.year, inicio.month + 1, 1);
      var total = 0;
      var quantidade = 0;
      for (final job in jobs) {
        final pago = job.paidAt;
        if (pago == null) continue;
        if (pago.isBefore(inicio) || !pago.isBefore(fim)) continue;
        total += job.totalCents;
        quantidade++;
      }
      return _MesDeFaturamento(inicio, total, quantidade);
    });
  }

  /// Serviços pagos dentro do mês selecionado — base das linhas por
  /// categoria.
  List<Job> _doMesSelecionado(List<Job> jobs, _MesDeFaturamento mes) {
    final fim = DateTime(mes.inicio.year, mes.inicio.month + 1, 1);
    return jobs.where((j) {
      final pago = j.paidAt;
      return pago != null && !pago.isBefore(mes.inicio) && pago.isBefore(fim);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Financeiro')),
      body: StreamBuilder<List<Job>>(
        stream: _servicos,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const _Aviso(
              icone: Icons.error_outline,
              titulo: 'Não foi possível carregar o financeiro',
              texto: 'Verifique sua conexão e tente de novo.',
            );
          }

          // Arquivado sai da conta: se saiu da lista de trabalho, não
          // deveria continuar mexendo no faturamento.
          final jobs = (snapshot.data ?? const <Job>[]).where((j) => !j.archived).toList();

          if (jobs.isEmpty) {
            return const _Aviso(
              icone: Icons.insights_outlined,
              titulo: 'Ainda não há o que mostrar',
              texto: 'Os números aparecem sozinhos conforme você conclui '
                  'serviços e confirma o pagamento na tela de Serviços.',
            );
          }

          final meses = _montarMeses(jobs);
          final indice = _mesSelecionado.clamp(0, meses.length - 1);
          final mes = meses[indice];

          // "A receber" é um número de AGORA, não do mês escolhido: é
          // dinheiro que ainda não entrou, então não pertence a nenhum mês
          // do passado. Fica separado dos outros dois de propósito.
          final aReceber =
              jobs.where((j) => j.status == JobStatus.aguardandoPagamento).toList();

          final ticketCents = mes.servicos == 0 ? 0 : (mes.recebidoCents / mes.servicos).round();
          final doMes = _doMesSelecionado(jobs, mes);

          // "Por categoria" só faz sentido pra quem atua em mais de uma: um
          // eletricista tem uma categoria só, e o bloco virava uma linha
          // única repetindo o total do mês — ocupando espaço sem responder
          // nada. Pedido do Franck (25/09): o que ele precisa ver ali é
          // QUEM pagou, pra conferir ("ver se a Marina pagou"). Essa
          // resposta agora é a lista abaixo; a categoria virou o detalhe
          // secundário que só aparece quando de fato há o que comparar.
          final categorias = doMes.map((j) => (j.category ?? '').trim()).toSet();

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              _CartaoDoMes(mes: mes, ticketCents: ticketCents),
              const SizedBox(height: 12),
              _CartaoAReceber(servicos: aReceber),
              const SizedBox(height: 20),
              _GraficoDeFaturamento(
                meses: meses,
                selecionado: indice,
                onSelecionar: (i) => setState(() => _mesSelecionado = i),
              ),
              const SizedBox(height: 24),
              _RecebidosNoMes(servicos: doMes, mes: mes),
              if (categorias.length > 1) ...[
                const SizedBox(height: 24),
                _PorCategoria(servicos: doMes, mes: mes),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Número principal: o que entrou no mês escolhido.
class _CartaoDoMes extends StatelessWidget {
  const _CartaoDoMes({required this.mes, required this.ticketCents});

  final _MesDeFaturamento mes;
  final int ticketCents;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.primaryDark],
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Recebido em ${mes.rotuloLongo}',
            style: const TextStyle(color: Colors.white70, fontSize: 12.5),
          ),
          const SizedBox(height: 6),
          Text(
            formatCentsBRL(mes.recebidoCents),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _MiniDado(
                  rotulo: 'Serviços pagos',
                  valor: '${mes.servicos}',
                ),
              ),
              Container(width: 1, height: 30, color: Colors.white24),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 14),
                  child: _MiniDado(
                    rotulo: 'Ticket médio',
                    valor: mes.servicos == 0 ? '—' : formatCentsBRL(ticketCents),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniDado extends StatelessWidget {
  const _MiniDado({required this.rotulo, required this.valor});

  final String rotulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(rotulo, style: const TextStyle(color: Colors.white70, fontSize: 11)),
        const SizedBox(height: 2),
        Text(
          valor,
          style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

/// "A receber hoje" — e, ao tocar, DE QUEM.
///
/// O valor sozinho respondia "quanto falta entrar" mas não "quem ainda não
/// me pagou", que é a pergunta que o prestador realmente faz. Como a lista
/// costuma ser curta (é o que está parado agora, não o histórico), ela cabe
/// aqui dentro em vez de virar outra tela.
class _CartaoAReceber extends StatefulWidget {
  const _CartaoAReceber({required this.servicos});

  final List<Job> servicos;

  @override
  State<_CartaoAReceber> createState() => _CartaoAReceberState();
}

class _CartaoAReceberState extends State<_CartaoAReceber> {
  bool _aberto = false;

  @override
  Widget build(BuildContext context) {
    final cents = widget.servicos.fold<int>(0, (s, j) => s + j.totalCents);
    final quantidade = widget.servicos.length;
    // Zero aqui é notícia boa — não vale acender um alerta laranja.
    final cor = cents == 0 ? AppColors.muted : AppColors.warning;
    // Sem nada parado não há o que abrir: o cartão continua sendo só o
    // número, sem uma seta que não leva a lugar nenhum.
    final podeAbrir = quantidade > 0;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cor.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: podeAbrir ? () => setState(() => _aberto = !_aberto) : null,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: cor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.schedule, color: cor, size: 20),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'A receber hoje',
                          style: TextStyle(fontSize: 12.5, color: AppColors.muted),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          formatCentsBRL(cents),
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    quantidade == 0
                        ? 'nada parado'
                        : '$quantidade serviço${quantidade == 1 ? '' : 's'}',
                    style: TextStyle(fontSize: 12, color: cor, fontWeight: FontWeight.w600),
                  ),
                  if (podeAbrir)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Icon(
                        _aberto ? Icons.expand_less : Icons.expand_more,
                        size: 20,
                        color: cor,
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (_aberto)
            for (final job in widget.servicos) ...[
              Divider(height: 1, color: AppColors.muted.withValues(alpha: 0.12)),
              _LinhaDeServico(
                nome: job.customerName,
                detalhe: job.addressText,
                cents: job.totalCents,
                cor: cor,
              ),
            ],
        ],
      ),
    );
  }
}

/// Barras de faturamento dos últimos meses.
///
/// Uma série só, então não leva legenda — o título já diz o que é. Só a
/// barra selecionada e a maior recebem rótulo de valor: número em cima de
/// toda barra vira ruído e some com a própria comparação que o gráfico
/// existe pra permitir.
class _GraficoDeFaturamento extends StatelessWidget {
  const _GraficoDeFaturamento({
    required this.meses,
    required this.selecionado,
    required this.onSelecionar,
  });

  final List<_MesDeFaturamento> meses;
  final int selecionado;
  final ValueChanged<int> onSelecionar;

  @override
  Widget build(BuildContext context) {
    final maior = meses.fold<int>(0, (m, e) => e.recebidoCents > m ? e.recebidoCents : m);
    final indiceDoMaior = meses.indexWhere((e) => e.recebidoCents == maior && maior > 0);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.muted.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Faturamento por mês',
            style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.ink),
          ),
          const SizedBox(height: 2),
          const Text(
            'Toque num mês para ver os detalhes dele',
            style: TextStyle(fontSize: 11.5, color: AppColors.muted),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 150,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < meses.length; i++)
                  Expanded(
                    child: _Barra(
                      mes: meses[i],
                      // Proporção sobre o maior mês. Quando TUDO é zero,
                      // `maior` é zero e a divisão estouraria — daí o
                      // fallback: todas as barras ficam no mínimo.
                      proporcao: maior == 0 ? 0 : meses[i].recebidoCents / maior,
                      selecionada: i == selecionado,
                      mostrarValor: i == selecionado || i == indiceDoMaior,
                      onTap: () => onSelecionar(i),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Barra extends StatelessWidget {
  const _Barra({
    required this.mes,
    required this.proporcao,
    required this.selecionada,
    required this.mostrarValor,
    required this.onTap,
  });

  final _MesDeFaturamento mes;
  final double proporcao;
  final bool selecionada;
  final bool mostrarValor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Altura útil da área de barras, descontando o rótulo do valor em cima
    // e o nome do mês embaixo.
    const alturaMaxima = 96.0;
    // Um mês sem faturamento precisa continuar clicável e visível como
    // "zero", e não desaparecer: o vazio é informação.
    final altura = proporcao <= 0 ? 3.0 : (proporcao * alturaMaxima).clamp(6.0, alturaMaxima);

    return GestureDetector(
      onTap: onTap,
      // Opaco pra o toque valer na coluna inteira, não só em cima da
      // barra — mês zerado tem 3px de altura e seria impossível acertar.
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          SizedBox(
            height: 26,
            child: mostrarValor
                ? FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      formatCentsBRL(mes.recebidoCents).replaceAll('R\$ ', ''),
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: selecionada ? AppColors.primary : AppColors.muted,
                      ),
                    ),
                  )
                : null,
          ),
          Padding(
            // 2px de respiro de cada lado: barras encostadas viram um
            // bloco só e o olho perde onde uma termina.
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              height: altura,
              decoration: BoxDecoration(
                color: selecionada
                    ? AppColors.primary
                    : AppColors.primary.withValues(alpha: 0.28),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            mes.rotuloCurto,
            style: TextStyle(
              fontSize: 11,
              fontWeight: selecionada ? FontWeight.w700 : FontWeight.w400,
              color: selecionada ? AppColors.ink : AppColors.muted,
            ),
          ),
        ],
      ),
    );
  }
}

/// Quem pagou o quê no mês selecionado.
///
/// É a resposta à pergunta que o prestador faz de verdade ao abrir o
/// Financeiro — "a Marina já me pagou?" — e que o total do mês, sozinho,
/// nunca respondeu. Vem do MESMO `Job.paidAt` que soma a barra do gráfico,
/// então a lista sempre fecha com o número de cima: se somar as linhas e
/// der outra coisa, é bug, não arredondamento.
///
/// Ordenada do pagamento mais recente pro mais antigo: conferindo, a
/// pessoa procura o que acabou de entrar, não o começo do mês.
class _RecebidosNoMes extends StatelessWidget {
  const _RecebidosNoMes({required this.servicos, required this.mes});

  final List<Job> servicos;
  final _MesDeFaturamento mes;

  @override
  Widget build(BuildContext context) {
    if (servicos.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.muted.withValues(alpha: 0.12)),
        ),
        child: Text(
          'Nenhum serviço pago em ${mes.rotuloLongo}.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: AppColors.muted),
        ),
      );
    }

    final ordenados = [...servicos]
      ..sort((a, b) => (b.paidAt ?? DateTime(0)).compareTo(a.paidAt ?? DateTime(0)));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Recebidos em ${mes.rotuloLongo}',
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
            ),
            Text(
              '${ordenados.length} pagamento${ordenados.length == 1 ? '' : 's'}',
              style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.muted.withValues(alpha: 0.12)),
          ),
          child: Column(
            children: [
              for (var i = 0; i < ordenados.length; i++) ...[
                if (i > 0)
                  Divider(height: 1, color: AppColors.muted.withValues(alpha: 0.12)),
                _LinhaDeServico(
                  nome: ordenados[i].customerName.isEmpty
                      ? 'Sem cliente'
                      : ordenados[i].customerName,
                  detalhe: _dataCurta(ordenados[i].paidAt),
                  cents: ordenados[i].totalCents,
                  cor: AppColors.success,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  static String? _dataCurta(DateTime? data) {
    if (data == null) return null;
    return '${data.day} de ${_mesesCurtos[data.month - 1]}';
  }
}

/// Uma linha de "fulano — R$ tanto", usada tanto pelo que já entrou quanto
/// pelo que está pendente. A cor do valor é o que separa os dois (verde pro
/// recebido, laranja pro parado), em vez de dois widgets quase idênticos.
class _LinhaDeServico extends StatelessWidget {
  const _LinhaDeServico({
    required this.nome,
    required this.cents,
    required this.cor,
    this.detalhe,
  });

  final String nome;
  final String? detalhe;
  final int cents;
  final Color cor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nome,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13.5, color: AppColors.ink),
                ),
                if (detalhe != null && detalhe!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    detalhe!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            formatCentsBRL(cents),
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: cor),
          ),
        ],
      ),
    );
  }
}

/// Quanto cada categoria rendeu no mês selecionado.
///
/// Só é montado por quem atua em mais de uma categoria (ver a decisão em
/// `FinanceiroScreen.build`) — daí não haver estado vazio aqui: a tela não
/// chega a construir este bloco quando não há o que comparar.
class _PorCategoria extends StatelessWidget {
  const _PorCategoria({required this.servicos, required this.mes});

  final List<Job> servicos;
  final _MesDeFaturamento mes;

  @override
  Widget build(BuildContext context) {
    final porCategoria = <String, int>{};
    for (final job in servicos) {
      final chave = (job.category ?? '').trim();
      porCategoria[chave] = (porCategoria[chave] ?? 0) + job.totalCents;
    }
    final linhas = porCategoria.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = linhas.fold<int>(0, (s, e) => s + e.value);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Por categoria em ${mes.rotuloLongo}',
          style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.ink),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.muted.withValues(alpha: 0.12)),
          ),
          child: Column(
            children: [
              for (var i = 0; i < linhas.length; i++) ...[
                if (i > 0)
                  Divider(height: 1, color: AppColors.muted.withValues(alpha: 0.12)),
                _LinhaDeCategoria(
                  rotulo: linhas[i].key.isEmpty
                      ? 'Sem categoria'
                      : serviceCategoryFromWire(linhas[i].key).label,
                  cents: linhas[i].value,
                  fatia: total == 0 ? 0 : linhas[i].value / total,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _LinhaDeCategoria extends StatelessWidget {
  const _LinhaDeCategoria({
    required this.rotulo,
    required this.cents,
    required this.fatia,
  });

  final String rotulo;
  final int cents;
  final double fatia;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  rotulo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13.5, color: AppColors.ink),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                formatCentsBRL(cents),
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          // A barrinha repete o número ao lado de propósito: proporção é
          // muito mais rápida de comparar de relance do que dois valores
          // em reais.
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: fatia,
              minHeight: 5,
              backgroundColor: AppColors.muted.withValues(alpha: 0.12),
              valueColor: const AlwaysStoppedAnimation(AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({required this.icone, required this.titulo, required this.texto});

  final IconData icone;
  final String titulo;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withValues(alpha: 0.08),
              ),
              child: Icon(icone, color: AppColors.primary, size: 38),
            ),
            const SizedBox(height: 18),
            Text(titulo, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              texto,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppColors.muted, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
