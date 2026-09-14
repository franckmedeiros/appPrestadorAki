import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import 'appointments_repository.dart';
import 'models/appointment.dart';

/// Tela de agenda — grade semanal com os horários na lateral e os dias nas
/// colunas, navegando semana a semana.
///
/// POR QUE GRADE, E NÃO LISTA: a versão anterior era uma lista dos
/// próximos 30 dias em ordem. Ela responde "o que vem depois", mas não
/// responde a pergunta que o prestador faz o dia inteiro — "quinta de
/// manhã eu tenho buraco?". Numa lista, espaço vazio não ocupa espaço, ou
/// seja, justamente o que ele procura é o que não aparece. Na grade o
/// vazio é visível: é o pedaço de coluna sem bloco nenhum.
///
/// POR QUE HORÁRIO NA LATERAL: o mockup de referência põe TÉCNICO na
/// lateral, porque é um app de equipe. Aqui o prestador é um só — a
/// lateral tem que ser o eixo que de fato varia dentro do dia dele, que é
/// a hora (pedido do Franck).
///
/// A lista continua existindo no modo "Dia", que é o que cabe bem na tela
/// do celular quando ele quer o detalhe de um dia só (endereço, cliente,
/// status) em vez da visão geral.
class AgendaScreen extends StatefulWidget {
  const AgendaScreen({super.key});

  @override
  State<AgendaScreen> createState() => _AgendaScreenState();
}

enum _ModoDaAgenda { semana, dia }

/// Altura de uma hora na grade. 60 dá pra um compromisso de 1h mostrar
/// hora e nome sem apertar.
const double _alturaDaHora = 60;
const double _larguraDaLateral = 52;
const double _larguraMinimaDoDia = 88;

const _diasDaSemana = ['SEG', 'TER', 'QUA', 'QUI', 'SEX', 'SÁB', 'DOM'];
const _meses = [
  'janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho',
  'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro',
];
// Usados só quando a semana cruza o mês: o nome inteiro duas vezes não
// cabe na largura de um celular, e o que importa ali é a data, não a
// grafia completa do mês.
const _mesesCurtos = [
  'jan', 'fev', 'mar', 'abr', 'mai', 'jun',
  'jul', 'ago', 'set', 'out', 'nov', 'dez',
];

DateTime _apenasData(DateTime d) => DateTime(d.year, d.month, d.day);

/// Segunda-feira da semana que contém [d]. `weekday` no Dart vai de 1
/// (segunda) a 7 (domingo), então subtrair `weekday - 1` sempre cai na
/// segunda, inclusive quando [d] já é segunda.
DateTime _inicioDaSemana(DateTime d) =>
    _somarDias(_apenasData(d), -(d.weekday - 1));

/// Soma dias pelo CALENDÁRIO, não por 24h fixas. `add(Duration(days: 1))`
/// soma 86.400 segundos: num dia de mudança de horário isso cai às 23h ou
/// à 1h do dia seguinte, e a agenda passaria a comparar 01/01 00:00 com
/// 01/01 01:00 como se fossem dias diferentes. Construir a data de novo
/// evita esse buraco — o Brasil não usa horário de verão hoje, mas já
/// usou, e a comparação por dia é o alicerce de toda esta tela.
DateTime _somarDias(DateTime d, int dias) => DateTime(d.year, d.month, d.day + dias);

String _doisDigitos(int v) => v.toString().padLeft(2, '0');

String _horaMinuto(DateTime d) => '${_doisDigitos(d.hour)}:${_doisDigitos(d.minute)}';

Color _corDoStatus(AppointmentStatus status) => switch (status) {
      AppointmentStatus.concluido => AppColors.success,
      AppointmentStatus.cancelado => AppColors.danger,
      AppointmentStatus.confirmado => AppColors.primary,
      AppointmentStatus.agendado => AppColors.muted,
    };

class _AgendaScreenState extends State<AgendaScreen> {
  late DateTime _semana = _inicioDaSemana(DateTime.now());
  late DateTime _diaSelecionado = _apenasData(DateTime.now());
  _ModoDaAgenda _modo = _ModoDaAgenda.semana;

  late Stream<List<Appointment>> _stream = _observarSemana();

  // Duas barras de rolagem horizontal — o cabeçalho dos dias e o corpo da
  // grade — que precisam andar juntas. Um ScrollController não pode ser
  // usado por dois scrolls ao mesmo tempo, então cada um tem o seu e um
  // empurra o outro. `_sincronizando` evita o pingue-pongue infinito de um
  // reagir ao movimento que ele mesmo causou.
  final _rolagemDoCabecalho = ScrollController();
  final _rolagemDoCorpo = ScrollController();
  bool _sincronizando = false;

  @override
  void initState() {
    super.initState();
    _rolagemDoCorpo.addListener(() => _sincronizar(_rolagemDoCorpo, _rolagemDoCabecalho));
    _rolagemDoCabecalho.addListener(() => _sincronizar(_rolagemDoCabecalho, _rolagemDoCorpo));
  }

  @override
  void dispose() {
    _rolagemDoCabecalho.dispose();
    _rolagemDoCorpo.dispose();
    super.dispose();
  }

  void _sincronizar(ScrollController origem, ScrollController destino) {
    if (_sincronizando || !destino.hasClients || !origem.hasClients) return;
    if ((destino.offset - origem.offset).abs() < 0.5) return;
    _sincronizando = true;
    destino.jumpTo(origem.offset);
    _sincronizando = false;
  }

  /// Stream ao vivo (ver AppointmentsRepository.watchRange) — mesma razão
  /// de CustomersRepository.watchAll: resolve "salvei e não apareceu,
  /// precisei sair e entrar de novo".
  ///
  /// Busca só a semana visível, e não mais os 30 dias fixos: navegar pra
  /// trás precisa trazer o passado, que a consulta antiga nunca pedia.
  Stream<List<Appointment>> _observarSemana() {
    return context.read<AppointmentsRepository>().watchRange(
          from: _semana,
          to: _somarDias(_semana, 7),
        );
  }

  void _irParaSemana(DateTime novaSemana) {
    setState(() {
      _semana = novaSemana;
      _stream = _observarSemana();
      // Mantém o dia selecionado dentro da semana visível, senão o modo
      // "Dia" mostraria um dia que não está mais na tela.
      if (_diaSelecionado.isBefore(_semana) ||
          !_diaSelecionado.isBefore(_somarDias(_semana, 7))) {
        _diaSelecionado = _semana;
      }
    });
  }

  void _hoje() {
    final agora = DateTime.now();
    setState(() {
      _semana = _inicioDaSemana(agora);
      _diaSelecionado = _apenasData(agora);
      _stream = _observarSemana();
    });
  }

  Future<void> _recarregar() async {
    setState(() => _stream = _observarSemana());
  }

  Future<void> _abrirCompromisso(Appointment? appointment) async {
    await context.push<bool>('/agenda/editar', extra: appointment);
    // A stream já reflete a escrita sozinha — não precisa recarregar nada
    // manualmente aqui.
  }

  Future<bool> _confirmarExclusao(Appointment appointment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir compromisso?'),
        content: Text(
          'Isso remove ${appointment.customerName ?? appointment.type.label} da agenda. '
          'Use isso quando o cliente desistiu do agendamento.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _excluir(Appointment appointment) async {
    try {
      await context.read<AppointmentsRepository>().delete(appointment.id);
      // A stream já reflete a exclusão sozinha.
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível excluir o compromisso. Tenta de novo.')),
      );
    }
  }

  /// "12 a 18 de maio" — e, quando a semana cruza o mês, "28 abr a 4 mai",
  /// que é o único caso em que nomear os dois meses informa alguma coisa.
  String get _rotuloDaSemana {
    final fim = _somarDias(_semana, 6);
    if (_semana.month == fim.month) {
      return '${_semana.day} a ${fim.day} de ${_meses[fim.month - 1]}';
    }
    return '${_semana.day} ${_mesesCurtos[_semana.month - 1]} '
        'a ${fim.day} ${_mesesCurtos[fim.month - 1]}';
  }

  bool get _mostrandoSemanaAtual => _semana == _inicioDaSemana(DateTime.now());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Agenda'),
        actions: [
          if (!_mostrandoSemanaAtual)
            TextButton(
              onPressed: _hoje,
              child: const Text('Hoje'),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _abrirCompromisso(null),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          _BarraDeNavegacao(
            rotulo: _rotuloDaSemana,
            modo: _modo,
            onAnterior: () => _irParaSemana(_somarDias(_semana, -7)),
            onProxima: () => _irParaSemana(_somarDias(_semana, 7)),
            onModo: (m) => setState(() => _modo = m),
          ),
          Expanded(
            child: StreamBuilder<List<Appointment>>(
              stream: _stream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return _EstadoDeErro(
                    message: 'Não foi possível carregar a agenda.',
                    onRetry: _recarregar,
                  );
                }
                final compromissos = snapshot.data ?? const <Appointment>[];
                if (_modo == _ModoDaAgenda.semana) {
                  return _GradeDaSemana(
                    semana: _semana,
                    compromissos: compromissos,
                    rolagemDoCabecalho: _rolagemDoCabecalho,
                    rolagemDoCorpo: _rolagemDoCorpo,
                    onTocarCompromisso: _abrirCompromisso,
                    onTocarDia: (dia) => setState(() {
                      _diaSelecionado = dia;
                      _modo = _ModoDaAgenda.dia;
                    }),
                  );
                }
                return _VisaoDoDia(
                  semana: _semana,
                  diaSelecionado: _diaSelecionado,
                  compromissos: compromissos,
                  onTrocarDia: (dia) => setState(() => _diaSelecionado = dia),
                  onTocarCompromisso: _abrirCompromisso,
                  onConfirmarExclusao: _confirmarExclusao,
                  onExcluir: _excluir,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Cabeçalho com as setas de semana e o alternador Semana/Dia.
class _BarraDeNavegacao extends StatelessWidget {
  const _BarraDeNavegacao({
    required this.rotulo,
    required this.modo,
    required this.onAnterior,
    required this.onProxima,
    required this.onModo,
  });

  final String rotulo;
  final _ModoDaAgenda modo;
  final VoidCallback onAnterior;
  final VoidCallback onProxima;
  final ValueChanged<_ModoDaAgenda> onModo;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: onAnterior,
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Semana anterior',
          ),
          Expanded(
            child: Text(
              rotulo,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
            ),
          ),
          IconButton(
            onPressed: onProxima,
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Próxima semana',
          ),
          const SizedBox(width: 4),
          _Alternador(modo: modo, onModo: onModo),
        ],
      ),
    );
  }
}

class _Alternador extends StatelessWidget {
  const _Alternador({required this.modo, required this.onModo});

  final _ModoDaAgenda modo;
  final ValueChanged<_ModoDaAgenda> onModo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _botao('Semana', _ModoDaAgenda.semana),
          _botao('Dia', _ModoDaAgenda.dia),
        ],
      ),
    );
  }

  Widget _botao(String texto, _ModoDaAgenda valor) {
    final ativo = modo == valor;
    return GestureDetector(
      onTap: () => onModo(valor),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: ativo ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          texto,
          style: TextStyle(
            color: ativo ? Colors.white : AppColors.muted,
            fontWeight: FontWeight.w600,
            fontSize: 12.5,
          ),
        ),
      ),
    );
  }
}

/// Um compromisso já posicionado: em que coluna do "empilhamento" ele
/// entra quando dois ocupam o mesmo horário, e de quantas colunas é a
/// divisão daquele grupo.
class _Posicionado {
  _Posicionado(this.compromisso, this.coluna, this.totalDeColunas);

  final Appointment compromisso;
  final int coluna;
  final int totalDeColunas;
}

/// Divide os compromissos de um dia em grupos que se sobrepõem no tempo e,
/// dentro de cada grupo, dá uma coluna a cada um — é o que impede dois
/// compromissos das 9h ficarem um em cima do outro, escondendo um deles.
///
/// Compromisso cancelado continua entrando: ele ainda ocupa espaço visual
/// porque o prestador precisa ver que aquele horário FOI marcado; quem
/// decide se o horário está livre é ele, não a tela.
List<_Posicionado> _posicionarDoDia(List<Appointment> doDia) {
  if (doDia.isEmpty) return const [];
  final ordenados = [...doDia]..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));

  final resultado = <_Posicionado>[];
  var grupo = <Appointment>[];
  DateTime? fimDoGrupo;

  void fecharGrupo() {
    if (grupo.isEmpty) return;
    // Aloca cada compromisso na primeira coluna que já esteja livre
    // naquele instante.
    final fimPorColuna = <DateTime>[];
    final colunaDe = <int>[];
    for (final a in grupo) {
      final fim = a.scheduledAt.add(Duration(minutes: a.durationMinutes));
      var coluna = fimPorColuna.indexWhere((f) => !f.isAfter(a.scheduledAt));
      if (coluna == -1) {
        fimPorColuna.add(fim);
        coluna = fimPorColuna.length - 1;
      } else {
        fimPorColuna[coluna] = fim;
      }
      colunaDe.add(coluna);
    }
    for (var i = 0; i < grupo.length; i++) {
      resultado.add(_Posicionado(grupo[i], colunaDe[i], fimPorColuna.length));
    }
    grupo = [];
    fimDoGrupo = null;
  }

  for (final a in ordenados) {
    final fim = a.scheduledAt.add(Duration(minutes: a.durationMinutes));
    if (fimDoGrupo != null && !a.scheduledAt.isBefore(fimDoGrupo!)) {
      fecharGrupo();
    }
    grupo.add(a);
    fimDoGrupo = (fimDoGrupo == null || fim.isAfter(fimDoGrupo!)) ? fim : fimDoGrupo;
  }
  fecharGrupo();

  return resultado;
}

class _GradeDaSemana extends StatelessWidget {
  const _GradeDaSemana({
    required this.semana,
    required this.compromissos,
    required this.rolagemDoCabecalho,
    required this.rolagemDoCorpo,
    required this.onTocarCompromisso,
    required this.onTocarDia,
  });

  final DateTime semana;
  final List<Appointment> compromissos;
  final ScrollController rolagemDoCabecalho;
  final ScrollController rolagemDoCorpo;
  final ValueChanged<Appointment> onTocarCompromisso;
  final ValueChanged<DateTime> onTocarDia;

  @override
  Widget build(BuildContext context) {
    // Janela de horas mostrada. Começa no horário comercial pra não abrir
    // a tela em 24 linhas quase todas vazias, mas se abre o quanto
    // precisar pra caber um compromisso às 6h ou às 22h — esconder um
    // compromisso seria pior do que rolar um pouco mais.
    var primeiraHora = 7;
    var ultimaHora = 19;
    for (final a in compromissos) {
      final fim = a.scheduledAt.add(Duration(minutes: a.durationMinutes));
      if (a.scheduledAt.hour < primeiraHora) primeiraHora = a.scheduledAt.hour;
      final horaDoFim = fim.minute > 0 ? fim.hour + 1 : fim.hour;
      if (horaDoFim > ultimaHora) ultimaHora = horaDoFim;
    }
    primeiraHora = primeiraHora.clamp(0, 23);
    ultimaHora = ultimaHora.clamp(primeiraHora + 1, 24);

    final totalDeHoras = ultimaHora - primeiraHora;
    final alturaTotal = totalDeHoras * _alturaDaHora;
    final hoje = _apenasData(DateTime.now());

    // Por dia da semana, já posicionados.
    final porDia = List.generate(7, (i) {
      final dia = _somarDias(semana, i);
      return _posicionarDoDia(
        compromissos.where((a) => _apenasData(a.scheduledAt) == dia).toList(),
      );
    });

    return LayoutBuilder(
      builder: (context, constraints) {
        // Em tela larga (tablet) os sete dias cabem e a grade preenche;
        // no celular cada dia fica com uma largura legível e a semana
        // rola na horizontal, em vez de espremer texto até sumir.
        final larguraDisponivel = constraints.maxWidth - _larguraDaLateral;
        final larguraDoDia =
            (larguraDisponivel / 7).clamp(_larguraMinimaDoDia, double.infinity).toDouble();
        final larguraDaGrade = larguraDoDia * 7;

        return Column(
          children: [
            // Cabeçalho dos dias — fica fixo enquanto a grade rola na
            // vertical, e acompanha a rolagem horizontal.
            Container(
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(bottom: BorderSide(color: Color(0x14000000))),
              ),
              child: Row(
                children: [
                  const SizedBox(width: _larguraDaLateral),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      controller: rolagemDoCabecalho,
                      child: SizedBox(
                        width: larguraDaGrade,
                        child: Row(
                          children: List.generate(7, (i) {
                            final dia = _somarDias(semana, i);
                            return SizedBox(
                              width: larguraDoDia,
                              child: _CabecalhoDoDia(
                                dia: dia,
                                indice: i,
                                ehHoje: dia == hoje,
                                quantidade: porDia[i].length,
                                onTap: () => onTocarDia(dia),
                              ),
                            );
                          }),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                child: SizedBox(
                  height: alturaTotal,
                  child: Row(
                    children: [
                      _ColunaDeHorarios(primeiraHora: primeiraHora, totalDeHoras: totalDeHoras),
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          controller: rolagemDoCorpo,
                          child: SizedBox(
                            width: larguraDaGrade,
                            height: alturaTotal,
                            child: Stack(
                              children: [
                                _LinhasDaGrade(
                                  totalDeHoras: totalDeHoras,
                                  larguraDoDia: larguraDoDia,
                                ),
                                for (var i = 0; i < 7; i++)
                                  for (final p in porDia[i])
                                    _BlocoDoCompromisso(
                                      posicionado: p,
                                      esquerdaDoDia: i * larguraDoDia,
                                      larguraDoDia: larguraDoDia,
                                      primeiraHora: primeiraHora,
                                      onTap: () => onTocarCompromisso(p.compromisso),
                                    ),
                              ],
                            ),
                          ),
                        ),
                      ),
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

class _CabecalhoDoDia extends StatelessWidget {
  const _CabecalhoDoDia({
    required this.dia,
    required this.indice,
    required this.ehHoje,
    required this.quantidade,
    required this.onTap,
  });

  final DateTime dia;
  final int indice;
  final bool ehHoje;
  final int quantidade;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _diasDaSemana[indice],
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: ehHoje ? AppColors.primary : AppColors.muted,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 3),
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: ehHoje ? AppColors.primary : Colors.transparent,
                shape: BoxShape.circle,
              ),
              child: Text(
                '${dia.day}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: ehHoje ? Colors.white : AppColors.ink,
                ),
              ),
            ),
            const SizedBox(height: 3),
            // Um ponto só, quando há algo marcado: confirma o dia cheio
            // mesmo quando a rolagem vertical está longe dos blocos.
            SizedBox(
              height: 5,
              child: quantidade == 0
                  ? null
                  : Container(
                      width: 5,
                      height: 5,
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ColunaDeHorarios extends StatelessWidget {
  const _ColunaDeHorarios({required this.primeiraHora, required this.totalDeHoras});

  final int primeiraHora;
  final int totalDeHoras;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _larguraDaLateral,
      child: Column(
        children: List.generate(totalDeHoras, (i) {
          return SizedBox(
            height: _alturaDaHora,
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                // Sobe meio texto pra o número ficar alinhado COM a linha
                // da hora, e não pendurado abaixo dela.
                child: Transform.translate(
                  offset: const Offset(0, -6),
                  child: Text(
                    '${_doisDigitos(primeiraHora + i)}:00',
                    style: const TextStyle(fontSize: 11, color: AppColors.muted),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _LinhasDaGrade extends StatelessWidget {
  const _LinhasDaGrade({required this.totalDeHoras, required this.larguraDoDia});

  final int totalDeHoras;
  final double larguraDoDia;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(totalDeHoras, (i) {
        return Container(
          height: _alturaDaHora,
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Color(0x11000000))),
          ),
          // `stretch` é o que faz o traço vertical existir: sem ele os
          // separadores de dia teriam altura zero (um Container só com
          // largura e borda não tem altura própria) e a grade sairia sem
          // as divisórias entre as colunas.
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: List.generate(7, (d) {
              return Container(
                width: larguraDoDia,
                decoration: const BoxDecoration(
                  border: Border(left: BorderSide(color: Color(0x0D000000))),
                ),
              );
            }),
          ),
        );
      }),
    );
  }
}

class _BlocoDoCompromisso extends StatelessWidget {
  const _BlocoDoCompromisso({
    required this.posicionado,
    required this.esquerdaDoDia,
    required this.larguraDoDia,
    required this.primeiraHora,
    required this.onTap,
  });

  final _Posicionado posicionado;
  final double esquerdaDoDia;
  final double larguraDoDia;
  final int primeiraHora;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final a = posicionado.compromisso;
    final minutosDoTopo =
        (a.scheduledAt.hour - primeiraHora) * 60 + a.scheduledAt.minute;
    final topo = minutosDoTopo / 60 * _alturaDaHora;
    // Altura mínima pra um compromisso de 15 ou 30 min continuar clicável
    // e com o horário legível.
    final altura = (a.durationMinutes / 60 * _alturaDaHora).clamp(26.0, double.infinity);

    final larguraUtil = (larguraDoDia - 4) / posicionado.totalDeColunas;
    final esquerda = esquerdaDoDia + 2 + posicionado.coluna * larguraUtil;

    final cor = _corDoStatus(a.status);
    final cancelado = a.status == AppointmentStatus.cancelado;

    return Positioned(
      top: topo,
      left: esquerda,
      width: larguraUtil - 2,
      height: altura,
      child: GestureDetector(
        onTap: onTap,
        // ClipRRect + barra colorida como filho, em vez de
        // `Border(left: ...)` com `borderRadius`: o Flutter não aceita
        // borda de um lado só junto com canto arredondado ("a borderRadius
        // can only be given for a uniform Border") e quebraria em tempo de
        // execução.
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Container(
            color: cor.withValues(alpha: cancelado ? 0.06 : 0.13),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 3, color: cor),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _horaMinuto(a.scheduledAt),
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: cor,
                            decoration: cancelado ? TextDecoration.lineThrough : null,
                          ),
                        ),
                        if (altura > 34)
                          Expanded(
                            child: Text(
                              a.customerName ?? a.type.label,
                              maxLines: altura > 58 ? 3 : 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10.5,
                                height: 1.15,
                                color: AppColors.ink,
                                decoration: cancelado ? TextDecoration.lineThrough : null,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Modo "Dia": os sete dias em pílulas no topo e a lista do dia escolhido
/// embaixo. É a visão de detalhe — mostra endereço, tipo e status, que não
/// cabem num bloco de grade.
class _VisaoDoDia extends StatelessWidget {
  const _VisaoDoDia({
    required this.semana,
    required this.diaSelecionado,
    required this.compromissos,
    required this.onTrocarDia,
    required this.onTocarCompromisso,
    required this.onConfirmarExclusao,
    required this.onExcluir,
  });

  final DateTime semana;
  final DateTime diaSelecionado;
  final List<Appointment> compromissos;
  final ValueChanged<DateTime> onTrocarDia;
  final ValueChanged<Appointment> onTocarCompromisso;
  final Future<bool> Function(Appointment) onConfirmarExclusao;
  final Future<void> Function(Appointment) onExcluir;

  @override
  Widget build(BuildContext context) {
    final hoje = _apenasData(DateTime.now());
    final doDia = compromissos
        .where((a) => _apenasData(a.scheduledAt) == diaSelecionado)
        .toList()
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));

    return Column(
      children: [
        Container(
          color: AppColors.surface,
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: List.generate(7, (i) {
              final dia = _somarDias(semana, i);
              final selecionado = dia == diaSelecionado;
              final tem = compromissos.any((a) => _apenasData(a.scheduledAt) == dia);
              return Expanded(
                child: InkWell(
                  onTap: () => onTrocarDia(dia),
                  child: Column(
                    children: [
                      Text(
                        _diasDaSemana[i],
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: dia == hoje ? AppColors.primary : AppColors.muted,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        width: 30,
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: selecionado ? AppColors.primary : Colors.transparent,
                          shape: BoxShape.circle,
                          border: dia == hoje && !selecionado
                              ? Border.all(color: AppColors.primary)
                              : null,
                        ),
                        child: Text(
                          '${dia.day}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: selecionado ? Colors.white : AppColors.ink,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        height: 5,
                        child: tem
                            ? Container(
                                width: 5,
                                height: 5,
                                decoration: BoxDecoration(
                                  color: selecionado ? AppColors.primary : AppColors.muted,
                                  shape: BoxShape.circle,
                                ),
                              )
                            : null,
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
        Expanded(
          child: doDia.isEmpty
              ? ListView(
                  children: const [
                    SizedBox(height: 60),
                    Icon(Icons.event_available_outlined, size: 44, color: AppColors.muted),
                    SizedBox(height: 12),
                    Text(
                      'Nenhum compromisso neste dia.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.muted),
                    ),
                  ],
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: doDia.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final appointment = doDia[index];
                    return Dismissible(
                      key: ValueKey(appointment.id),
                      direction: DismissDirection.endToStart,
                      confirmDismiss: (_) => onConfirmarExclusao(appointment),
                      onDismissed: (_) => onExcluir(appointment),
                      background: Container(
                        decoration: BoxDecoration(
                          color: AppColors.danger,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: const Icon(Icons.delete_outline, color: Colors.white),
                      ),
                      child: _CartaoDoCompromisso(
                        appointment: appointment,
                        onTap: () => onTocarCompromisso(appointment),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _CartaoDoCompromisso extends StatelessWidget {
  const _CartaoDoCompromisso({required this.appointment, required this.onTap});

  final Appointment appointment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final inicio = appointment.scheduledAt;
    final fim = inicio.add(Duration(minutes: appointment.durationMinutes));

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  Text(_horaMinuto(inicio), style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(_horaMinuto(fim),
                      style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      appointment.customerName ?? appointment.type.label,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(appointment.type.label,
                        style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                    if (appointment.addressText != null && appointment.addressText!.isNotEmpty)
                      Text(appointment.addressText!, style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              _StatusChip(status: appointment.status),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final AppointmentStatus status;

  @override
  Widget build(BuildContext context) {
    final color = _corDoStatus(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(status.label,
          style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}

class _EstadoDeErro extends StatelessWidget {
  const _EstadoDeErro({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 80),
        const Icon(Icons.error_outline, size: 48, color: AppColors.danger),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        Center(
          child: OutlinedButton(onPressed: onRetry, child: const Text('Tentar de novo')),
        ),
      ],
    );
  }
}
