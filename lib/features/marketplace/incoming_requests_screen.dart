import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../widgets/app_list_card.dart';
import 'models/service_request.dart';
import 'service_requests_repository.dart';

/// Aba "Pedidos" do lado do prestador — os pedidos de orçamento que
/// chegaram pelo marketplace (diferente da lista de clientes cadastrados
/// manualmente). Responder aqui é deliberadamente simples (um valor total
/// + mensagem); não usa o módulo formal de Orçamentos.
class IncomingRequestsScreen extends StatefulWidget {
  const IncomingRequestsScreen({super.key});

  @override
  State<IncomingRequestsScreen> createState() => _IncomingRequestsScreenState();
}

class _IncomingRequestsScreenState extends State<IncomingRequestsScreen> {
  late Future<List<ServiceRequest>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<ServiceRequestsRepository>().listForProvider();
  }

  Future<void> _reload() async {
    setState(() => _future = context.read<ServiceRequestsRepository>().listForProvider());
    await _future;
  }

  Future<void> _respondWithQuote(ServiceRequest request) async {
    final amountController = TextEditingController();
    final messageController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enviar orçamento'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Valor total (R\$)'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: messageController,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Mensagem (opcional)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Enviar')),
        ],
      ),
    );
    if (result != true) return;
    final amount = double.tryParse(amountController.text.replaceAll(',', '.'));
    if (amount == null) return;
    await context.read<ServiceRequestsRepository>().sendQuote(
          request.id,
          amountCents: (amount * 100).round(),
          message: messageController.text.trim(),
        );
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pedidos recebidos')),
      body: RefreshIndicator(
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
                  Icon(Icons.inbox_outlined, size: 48, color: AppColors.muted),
                  SizedBox(height: 12),
                  Text(
                    'Nenhum pedido do marketplace ainda. Complete seu perfil '
                    'público (categoria e cidade) pra aparecer nas buscas dos '
                    'clientes.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.muted),
                  ),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: requests.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final request = requests[index];
                final canRespond = request.status == ServiceRequestStatus.aguardandoPrestador;
                return AppListCard(
                  leading: AppListCard.iconAvatar(Icons.person_outline),
                  title: request.clientName,
                  subtitle: request.description,
                  trailing: canRespond
                      ? TextButton(
                          onPressed: () => _respondWithQuote(request),
                          child: const Text('Responder'),
                        )
                      : Text(request.status.label, style: const TextStyle(fontSize: 11)),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
