import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../core/app_theme.dart';
import '../core/auth_controller.dart';
import '../features/marketplace/client_auth_gate.dart';
import '../features/notifications/notifications_repository.dart';

/// Ícone de sino com badge de não lidas, pra colocar no AppBar de uma
/// tela — abre a central de notificações ao tocar (ver
/// NotificationsScreen). Mesma ideia do app Resenha (NotificationBell
/// lá), adaptado pro DI via `provider`/rotas via `go_router` que o
/// PrestadorAki já usa.
///
/// Fica sempre visível (mesmo pra um convidado não-logado, já que
/// `ClientHomeScreen` é aberta livre — ver app_router.dart), mas sem
/// contagem nem stream do Firestore até existir sessão: `clients/{uid}`
/// exige um uid de verdade, e tocar antes de logar mostra o mesmo convite
/// de login/cadastro já usado pra favoritar (`ensureClientAccount`), em
/// vez de travar tentando ler notificações de ninguém.
///
/// Só é colocado nas telas "principais" de cada lado da conta (Buscar,
/// pro cliente; Dashboard, pro prestador) — igual ao Resenha, que só tem
/// o sino na lista principal, não repetido em toda tela.
class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key});

  Future<void> _open(BuildContext context) async {
    if (!await ensureClientAccount(context)) return;
    if (!context.mounted) return;
    context.push('/notificacoes');
  }

  @override
  Widget build(BuildContext context) {
    final isAuthenticated = context.watch<AuthController>().status == AuthStatus.authenticated;

    if (!isAuthenticated) {
      return IconButton(
        tooltip: 'Notificações',
        onPressed: () => _open(context),
        icon: const Icon(Icons.notifications_outlined),
      );
    }

    return StreamBuilder<int>(
      stream: context.read<NotificationsRepository>().watchUnreadCount(),
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        return IconButton(
          tooltip: 'Notificações',
          onPressed: () => _open(context),
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(Icons.notifications_outlined),
              if (count > 0)
                Positioned(
                  right: -3,
                  top: -3,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    decoration: const BoxDecoration(color: AppColors.danger, shape: BoxShape.circle),
                    child: Text(
                      count > 9 ? '9+' : '$count',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
