import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/auth_controller.dart';
import '../budgets/budget_chat_screen.dart';
import 'budget_requests_repository.dart';
import 'client_auth_gate.dart';
import 'models/provider_listing.dart';

/// Abre o chat com um prestador a partir do card da busca ou dos
/// favoritos.
///
/// Função solta, e não método de uma tela, porque o card aparece em duas
/// (ClientHomeScreen e MyFavoritesScreen) e o comportamento precisa ser o
/// mesmo nas duas. Duas cópias divergiriam no primeiro ajuste.
///
/// O que acontece, na ordem:
/// 1. Pede login se a pessoa estiver navegando como convidada — mensagem
///    precisa de remetente.
/// 2. Acha a conversa que já existe com esse prestador, ou abre uma
///    (ver BudgetRequestsRepository.conversaCom).
/// 3. Abre o MESMO chat do orçamento (BudgetChatScreen) — pedido do Franck:
///    "a funcionalidade de chat que já tem lá no orçamento, mas ali no card".
Future<void> abrirConversaComPrestador(BuildContext context, ProviderListing listing) async {
  if (!await ensureClientAccount(context)) return;
  if (!context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);

  try {
    final conversa = await context.read<BudgetRequestsRepository>().conversaCom(
          listing,
          clientName: context.read<AuthController>().displayName,
        );
    if (conversa == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Este profissional ainda não recebe mensagens pelo app.')),
      );
      return;
    }
    await navigator.push(
      MaterialPageRoute(
        builder: (_) => BudgetChatScreen(
          providerId: conversa.providerUid,
          budgetId: conversa.budgetId,
          souPrestador: false,
          tituloOutroLado: listing.name,
        ),
      ),
    );
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text('Não foi possível abrir a conversa. $e')),
    );
  }
}
