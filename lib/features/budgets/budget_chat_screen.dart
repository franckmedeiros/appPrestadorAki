import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_theme.dart';
import '../../core/auth_controller.dart';
import 'budget_messages_repository.dart';
import 'models/budget_message.dart';

/// Conversa de um orçamento, usada pelos DOIS lados — o prestador abre
/// pelo pedido/orçamento (BudgetFormScreen) e o cliente pelo card em
/// "Meus orçamentos" (MyRequestsScreen). A única diferença entre os dois
/// é [souPrestador], que decide de que lado da tela cada balão aparece e
/// qual contador de não lidas é zerado.
///
/// Pedido do Franck: "ter um lugar no app pra ele perguntar pro cliente,
/// tipo um responder dentro do card. Porque o cliente pode não ter
/// informado o whatsapp corretamente". É a rede de segurança do atalho
/// de WhatsApp: aqui a mensagem chega na CONTA, não num número que
/// ninguém verificou.
class BudgetChatScreen extends StatefulWidget {
  const BudgetChatScreen({
    super.key,
    required this.providerId,
    required this.budgetId,
    required this.souPrestador,
    required this.tituloOutroLado,
  });

  /// Dono do orçamento. Pro prestador é o próprio uid; pro cliente vem do
  /// `Budget.providerUid` do orçamento que ele está olhando.
  final String providerId;
  final String budgetId;
  final bool souPrestador;

  /// Nome de quem está do outro lado, só pro cabeçalho.
  final String tituloOutroLado;

  @override
  State<BudgetChatScreen> createState() => _BudgetChatScreenState();
}

class _BudgetChatScreenState extends State<BudgetChatScreen> {
  // `late final` com `context.read`: o Provider permite ler (sem escutar)
  // já no initState, e assim o repositório segue vindo da árvore como
  // todos os outros do app (ver main.dart) em vez de ser instanciado à
  // mão aqui.
  late final BudgetMessagesRepository _repo = context.read<BudgetMessagesRepository>();

  /// O stream é criado UMA vez e guardado. Chamar `_repo.watch(...)`
  /// direto no `StreamBuilder` criaria uma assinatura nova a cada
  /// rebuild — a lista piscaria e o Firestore reabriria o listener sem
  /// necessidade.
  late final Stream<List<BudgetMessage>> _mensagens =
      _repo.watch(providerId: widget.providerId, budgetId: widget.budgetId);

  final _controller = TextEditingController();
  final _scroll = ScrollController();
  bool _enviando = false;

  /// Quantas mensagens a tela já viu. Existe pra distinguir "chegou
  /// mensagem nova" de "o widget se redesenhou" — sem isso, rolar a
  /// lista ou abrir o teclado dispararia de novo a gravação de "marcar
  /// como lida" no Firestore, uma escrita por rebuild.
  int _totalJaVisto = -1;

  @override
  void initState() {
    super.initState();
    _marcarLidas();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _marcarLidas() {
    _repo.marcarComoLidas(
      providerId: widget.providerId,
      budgetId: widget.budgetId,
      souPrestador: widget.souPrestador,
    );
  }

  /// Rola pro fim depois que a lista se redesenha. O `postFrameCallback` é
  /// necessário: no frame em que a mensagem nova chega, o ListView ainda
  /// não recalculou a altura, e rolar agora pararia antes do fim.
  void _rolarProFim() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _enviar() async {
    final texto = _controller.text.trim();
    if (texto.isEmpty || _enviando) return;
    setState(() => _enviando = true);
    // Limpa o campo ANTES de esperar a rede: o Firestore mostra a
    // mensagem na hora pelo cache local, então deixar o texto no campo
    // até o servidor responder faria parecer que não enviou.
    _controller.clear();
    try {
      await _repo.enviar(
        providerId: widget.providerId,
        budgetId: widget.budgetId,
        texto: texto,
        souPrestador: widget.souPrestador,
        meuNome: context.read<AuthController>().displayName,
      );
    } catch (e) {
      if (!mounted) return;
      // Devolve o texto pro campo — perder o que a pessoa escreveu por
      // causa de uma falha de rede é inaceitável.
      _controller.text = texto;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível enviar: $e')),
      );
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.tituloOutroLado),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<BudgetMessage>>(
              stream: _mensagens,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _Aviso(
                    icone: Icons.error_outline,
                    texto: 'Não foi possível carregar a conversa.\n${snapshot.error}',
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final mensagens = snapshot.data!;
                if (mensagens.isEmpty) {
                  return const _Aviso(
                    icone: Icons.forum_outlined,
                    texto: 'Nenhuma mensagem ainda.\nEscreva abaixo pra tirar uma dúvida.',
                  );
                }
                // SÓ quando o número de mensagens muda (ver
                // `_totalJaVisto`): chegou coisa nova enquanto a tela está
                // aberta, então rola pro fim e marca como lida — senão a
                // bolinha ficaria acesa com a conversa aberta na frente da
                // pessoa.
                if (mensagens.length != _totalJaVisto) {
                  _totalJaVisto = mensagens.length;
                  _rolarProFim();
                  _marcarLidas();
                }
                return ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  itemCount: mensagens.length,
                  itemBuilder: (context, i) {
                    final m = mensagens[i];
                    final minha = widget.souPrestador
                        ? m.autorTipo == AutorMensagem.prestador
                        : m.autorTipo == AutorMensagem.cliente;
                    return _Balao(mensagem: m, minha: minha);
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(top: BorderSide(color: Color(0x14000000))),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'Escreva sua mensagem',
                        border: InputBorder.none,
                      ),
                      onSubmitted: (_) => _enviar(),
                    ),
                  ),
                  IconButton(
                    onPressed: _enviando ? null : _enviar,
                    icon: _enviando
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.2),
                          )
                        : const Icon(Icons.send_rounded, color: AppColors.primary),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Balao extends StatelessWidget {
  const _Balao({required this.mensagem, required this.minha});

  final BudgetMessage mensagem;
  final bool minha;

  @override
  Widget build(BuildContext context) {
    final hora = mensagem.createdAt;
    return Align(
      alignment: minha ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: minha ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(minha ? 14 : 4),
            bottomRight: Radius.circular(minha ? 4 : 14),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              mensagem.texto,
              style: TextStyle(
                fontSize: 14,
                height: 1.35,
                color: minha ? Colors.white : AppColors.ink,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              // Sem data ainda = o serverTimestamp não voltou. "Enviando…"
              // é mais honesto que um horário inventado no relógio local.
              hora == null ? 'Enviando…' : TimeOfDay.fromDateTime(hora).format(context),
              style: TextStyle(
                fontSize: 10.5,
                color: minha ? Colors.white70 : AppColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({required this.icone, required this.texto});

  final IconData icone;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icone, size: 40, color: AppColors.muted),
            const SizedBox(height: 10),
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
