import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../core/auth_controller.dart';
import '../../widgets/app_list_card.dart';
import 'client_auth_gate.dart';
import 'models/service_category.dart';
import 'models/service_request.dart';
import 'service_requests_repository.dart';

class MyRequestsScreen extends StatefulWidget {
  const MyRequestsScreen({super.key});

  @override
  State<MyRequestsScreen> createState() => _MyRequestsScreenState();
}

class _MyRequestsScreenState extends State<MyRequestsScreen> {
  // Stream em vez de Future recarregado manualmente: esta tela é uma aba
  // do shell único do app (StatefulShellRoute.indexedStack — ver
  // UnifiedShell), que fica viva o tempo todo, e o envio de uma nova
  // solicitação acontece em OUTRA tela empilhada por cima
  // (RequestQuoteFormScreen) — não existia nenhum jeito natural de avisar
  // esta aqui pra recarregar, daí a lista "não vinha" sem sair e entrar
  // de novo. Ver ServiceRequestsRepository.watchForClient.
  Stream<List<ServiceRequest>>? _stream;
  String? _streamForUid;

  void _ensureStream(String uid) {
    if (_streamForUid == uid) return;
    _streamForUid = uid;
    _stream = context.read<ServiceRequestsRepository>().watchForClient();
  }

  Future<void> _signIn() async {
    if (await ensureClientAccount(context) && mounted) setState(() {});
  }

  Future<void> _respond(ServiceRequest request, bool accepted) async {
    try {
      await context.read<ServiceRequestsRepository>().respond(request.id, accepted: accepted);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível responder agora. Tenta de novo.')),
      );
    }
    // Não precisa recarregar manualmente: a tela usa watchForClient()
    // (Stream), então a lista já atualiza sozinha quando o status muda.
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final isClient = auth.status == AuthStatus.authenticated;
    if (isClient) {
      _ensureStream(auth.providerId);
    } else {
      _stream = null;
      _streamForUid = null;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Minhas solicitações')),
      body: !isClient
          ? ClientSignInPrompt(
              icon: Icons.list_alt_outlined,
              message: 'Crie uma conta grátis para acompanhar suas solicitações de orçamento.',
              onPressed: _signIn,
            )
          : StreamBuilder<List<ServiceRequest>>(
              stream: _stream,
              builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final requests = snapshot.data ?? [];
                  if (requests.isEmpty) {
                    return ListView(
                      children: const [
                        SizedBox(height: 80),
                        Icon(Icons.list_alt_outlined, size: 48, color: AppColors.muted),
                        SizedBox(height: 12),
                        Text('Nenhuma solicitação enviada ainda.',
                            textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
                      ],
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: requests.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final request = requests[index];
                      final accepted = request.status == ServiceRequestStatus.aceito;
                      final awaitingDecision = request.status == ServiceRequestStatus.orcamentoEnviado;
                      return AppListCard(
                        leading: AppListCard.iconAvatar(request.category.icon),
                        title: request.providerName,
                        subtitle: request.description,
                        trailing: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(request.status.label,
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                            if (request.quoteAmountCents != null)
                              Text(
                                'R\$ ${(request.quoteAmountCents! / 100).toStringAsFixed(2)}',
                                style: const TextStyle(fontSize: 12, color: AppColors.muted),
                              ),
                          ],
                        ),
                        // Só pedidos aceitos liberam avaliação (ver
                        // ServiceRequestsRepository.hasAcceptedRequestWith)
                        // — leva pro perfil público, onde a seção de
                        // avaliação de verdade mora (evita duplicar o
                        // formulário de estrelas em duas telas).
                        footer: awaitingDecision
                            ? Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton(
                                    onPressed: () => _respond(request, false),
                                    style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                                    child: const Text('Recusar'),
                                  ),
                                  const SizedBox(width: 8),
                                  FilledButton(
                                    onPressed: () => _respond(request, true),
                                    child: const Text('Aceitar'),
                                  ),
                                ],
                              )
                            : accepted
                                ? Align(
                                    alignment: Alignment.centerLeft,
                                    child: TextButton.icon(
                                      onPressed: () =>
                                          context.push('/prestador/${request.providerDirectoryId}'),
                                      icon: const Icon(Icons.star_outline, size: 16),
                                      label: const Text('Avaliar este prestador'),
                                      style: TextButton.styleFrom(
                                        padding: EdgeInsets.zero,
                                        minimumSize: const Size(0, 32),
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      ),
                                    ),
                                  )
                                : null,
                      );
                    },
                  );
                },
            ),
    );
  }
}
