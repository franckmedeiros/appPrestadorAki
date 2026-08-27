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
  Future<List<ServiceRequest>>? _future;

  void _load() {
    final auth = context.read<AuthController>();
    if (auth.status == AuthStatus.authenticated) {
      _future = context.read<ServiceRequestsRepository>().listForClient();
    }
  }

  Future<void> _reload() async {
    setState(_load);
    await _future;
  }

  Future<void> _signIn() async {
    if (await ensureClientAccount(context) && mounted) setState(_load);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final isClient = auth.status == AuthStatus.authenticated;
    if (isClient && _future == null) _load();
    if (!isClient) _future = null;

    return Scaffold(
      appBar: AppBar(title: const Text('Minhas solicitações')),
      body: !isClient
          ? ClientSignInPrompt(
              icon: Icons.list_alt_outlined,
              message: 'Crie uma conta grátis para acompanhar suas solicitações de orçamento.',
              onPressed: _signIn,
            )
          : RefreshIndicator(
              onRefresh: _reload,
              child: FutureBuilder<List<ServiceRequest>>(
                future: _future,
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
                        footer: accepted
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
            ),
    );
  }
}
