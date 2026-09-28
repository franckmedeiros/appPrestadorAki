import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_theme.dart';
import '../../core/auth_controller.dart';
import '../marketplace/budget_requests_repository.dart';
import 'budget_chat_screen.dart';
import 'budgets_repository.dart';
import 'models/budget.dart';

/// Caixa de entrada das conversas — a aba "Conversas".
///
/// POR QUE ELA EXISTE (pedido do Franck, 28/09): o chat sempre morou
/// DENTRO de um orçamento (`providers/{uid}/budgets/{id}/mensagens`, ver
/// BudgetChatScreen). Funcionava pra continuar uma conversa já aberta,
/// mas não pra começar a responder: chegava a notificação de mensagem
/// nova e não existia lugar nenhum no app onde o prestador visse "quem
/// falou comigo". Ele tinha que lembrar de qual orçamento era e navegar
/// até ele. Esta tela é esse lugar.
///
/// NÃO É UMA ESTRUTURA NOVA. A conversa continua sendo do orçamento; isto
/// aqui é só uma leitura transversal dos orçamentos que já têm mensagem.
/// Os três campos que fazem isso funcionar (`ultimaMensagemEm`,
/// `naoLidasPrestador`, `naoLidasCliente`) já eram mantidos pela Cloud
/// Function `onMensagemDoOrcamentoCriada` desde que o chat nasceu — eram
/// usados só pra bolinha no card. Aqui eles finalmente pagam o que
/// custam.
///
/// OS DOIS LADOS NA MESMA LISTA. A conta é unificada (ver AuthController),
/// então a mesma pessoa pode ter conversa como prestador (alguém pediu
/// orçamento pra ela) e como cliente (ela pediu pra outro). As duas
/// aparecem juntas, ordenadas por quem falou por último — separar em duas
/// abas obrigaria a pessoa a adivinhar em qual delas está a mensagem que
/// ela acabou de receber.
///
/// SEM ÍNDICE NOVO, de propósito: reaproveita `BudgetsRepository.watchAll`
/// e `BudgetRequestsRepository.watchMine`, que já existem e já têm índice,
/// e filtra/ordena aqui no app. Uma consulta dedicada (ordenar por
/// `ultimaMensagemEm` no servidor) pediria índice composto novo e uma
/// espera de "Ativado" no console antes de funcionar — por um ganho que
/// ninguém sente, já que uma pessoa tem dezenas de orçamentos, não
/// milhares.
class ConversasScreen extends StatefulWidget {
  const ConversasScreen({super.key});

  @override
  State<ConversasScreen> createState() => _ConversasScreenState();
}

class _ConversasScreenState extends State<ConversasScreen> {
  Stream<List<Budget>>? _comoPrestador;
  Stream<List<Budget>>? _comoCliente;

  /// Identifica a combinação de sessão que gerou os streams atuais. Sem
  /// isso, cada rebuild criaria assinaturas novas no Firestore e a lista
  /// piscaria — mesmo cuidado já tomado em BudgetChatScreen.
  String? _chaveDaSessao;

  void _garantirStreams(AuthController auth) {
    final chave = '${auth.status}-${auth.isProvider}';
    if (chave == _chaveDaSessao) return;
    _chaveDaSessao = chave;

    if (auth.status != AuthStatus.authenticated) {
      _comoPrestador = null;
      _comoCliente = null;
      return;
    }
    // `watchAll` usa `currentUser!` lá dentro — só pode ser chamado com
    // sessão de verdade, daí o corte acima antes de qualquer consulta.
    _comoPrestador = auth.isProvider ? context.read<BudgetsRepository>().watchAll() : null;
    _comoCliente = context.read<BudgetRequestsRepository>().watchMine();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    _garantirStreams(auth);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Conversas')),
      body: auth.status != AuthStatus.authenticated
          ? const _Aviso(
              icone: Icons.chat_bubble_outline,
              titulo: 'Entre para ver suas conversas',
              texto: 'As mensagens ficam ligadas à sua conta — é assim que '
                  'elas chegam até você mesmo se o telefone estiver errado.',
            )
          : _lista(),
    );
  }

  Widget _lista() {
    return StreamBuilder<List<Budget>>(
      stream: _comoCliente,
      builder: (context, comoCliente) {
        return StreamBuilder<List<Budget>>(
          stream: _comoPrestador,
          builder: (context, comoPrestador) {
            final esperando = (_comoCliente != null && comoCliente.connectionState == ConnectionState.waiting) ||
                (_comoPrestador != null && comoPrestador.connectionState == ConnectionState.waiting);
            if (esperando) {
              return const Center(child: CircularProgressIndicator());
            }
            if (comoCliente.hasError || comoPrestador.hasError) {
              return const _Aviso(
                icone: Icons.error_outline,
                titulo: 'Não foi possível carregar as conversas',
                texto: 'Verifique sua conexão e tente de novo.',
              );
            }

            final conversas = <_Conversa>[
              for (final b in comoPrestador.data ?? const <Budget>[])
                if (_temConversa(b)) _Conversa(b, souPrestador: true),
              for (final b in comoCliente.data ?? const <Budget>[])
                if (_temConversa(b)) _Conversa(b, souPrestador: false),
            ]..sort((a, z) => z.quando.compareTo(a.quando));

            if (conversas.isEmpty) {
              return const _Aviso(
                icone: Icons.chat_bubble_outline,
                titulo: 'Nenhuma conversa ainda',
                texto: 'Toda conversa começa a partir de um pedido de '
                    'orçamento. Quando alguém escrever, a mensagem aparece aqui.',
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: conversas.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, indent: 72, color: AppColors.muted.withValues(alpha: 0.12)),
              itemBuilder: (context, i) => _LinhaDeConversa(
                conversa: conversas[i],
                onTap: () => _abrir(conversas[i]),
              ),
            );
          },
        );
      },
    );
  }

  /// Um orçamento só vira conversa quando alguém escreveu nele. Sem essa
  /// condição a lista mostraria todo orçamento já criado, e a tela perderia
  /// justamente o sentido de ser uma caixa de entrada.
  static bool _temConversa(Budget b) => b.ultimaMensagemEm != null && b.providerUid != null;

  void _abrir(_Conversa conversa) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BudgetChatScreen(
          providerId: conversa.budget.providerUid!,
          budgetId: conversa.budget.id,
          souPrestador: conversa.souPrestador,
          tituloOutroLado: conversa.outroLado,
        ),
      ),
    );
  }
}

/// Uma linha da caixa de entrada: o orçamento, mais de que lado dele a
/// pessoa logada está. É esse `souPrestador` que decide qual contador de
/// não lidas vale e qual nome mostrar — o mesmo orçamento visto pelo outro
/// lado seria uma conversa com outra pessoa.
class _Conversa {
  _Conversa(this.budget, {required this.souPrestador});

  final Budget budget;
  final bool souPrestador;

  /// `ultimaMensagemEm` nunca é nulo aqui (ver `_temConversa`), mas o
  /// fallback evita depender disso à distância.
  DateTime get quando => budget.ultimaMensagemEm ?? budget.date;

  int get naoLidas => souPrestador ? budget.naoLidasPrestador : budget.naoLidasCliente;

  String get outroLado {
    if (souPrestador) {
      return budget.customerName.isEmpty ? 'Cliente' : budget.customerName;
    }
    final nome = budget.providerName;
    return (nome == null || nome.isEmpty) ? 'Prestador' : nome;
  }

  /// Uma linha de contexto pra pessoa saber de qual serviço é a conversa
  /// antes de abrir. O pedido do cliente é o que melhor descreve isso; sem
  /// ele, o rótulo do status já diz mais que nada.
  String get assunto {
    final descricao = budget.requestDescription?.trim();
    if (descricao != null && descricao.isNotEmpty) return descricao;
    return budget.status?.label ?? 'Orçamento';
  }
}

class _LinhaDeConversa extends StatelessWidget {
  const _LinhaDeConversa({required this.conversa, required this.onTap});

  final _Conversa conversa;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final naoLidas = conversa.naoLidas;
    final temNaoLidas = naoLidas > 0;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withValues(alpha: 0.10),
              ),
              child: Icon(
                // O ícone diz de que lado a pessoa está nesta conversa —
                // numa conta que é cliente E prestador, duas linhas podem
                // ter nomes parecidos e origens completamente diferentes.
                conversa.souPrestador ? Icons.person_outline : Icons.handyman_outlined,
                color: AppColors.primary,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          conversa.outroLado,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: temNaoLidas ? FontWeight.w800 : FontWeight.w600,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _quando(conversa.quando),
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: temNaoLidas ? FontWeight.w700 : FontWeight.w400,
                          color: temNaoLidas ? AppColors.primary : AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          conversa.assunto,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12.5, color: AppColors.muted, height: 1.3),
                        ),
                      ),
                      if (temNaoLidas) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            naoLidas > 99 ? '99+' : '$naoLidas',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "agora", "há 8 min", "ontem", "12/09" — quanto mais recente, mais
/// preciso. Uma data completa numa mensagem de cinco minutos atrás obriga
/// a pessoa a fazer a conta de cabeça.
String _quando(DateTime data) {
  final agora = DateTime.now();
  final diferenca = agora.difference(data);
  if (diferenca.isNegative || diferenca.inMinutes < 1) return 'agora';
  if (diferenca.inMinutes < 60) return 'há ${diferenca.inMinutes} min';

  final hoje = DateTime(agora.year, agora.month, agora.day);
  final dia = DateTime(data.year, data.month, data.day);
  if (dia == hoje) return 'há ${diferenca.inHours} h';
  if (dia == hoje.subtract(const Duration(days: 1))) return 'ontem';

  final d = data.day.toString().padLeft(2, '0');
  final m = data.month.toString().padLeft(2, '0');
  return data.year == agora.year ? '$d/$m' : '$d/$m/${data.year}';
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
