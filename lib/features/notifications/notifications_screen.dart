import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import 'models/app_notification.dart';
import 'notifications_repository.dart';

/// Central de notificações — histórico do que já foi avisado por push
/// (novo pedido de orçamento, resposta do prestador), guardado no
/// Firestore pra dar pra ver mesmo depois que a notificação já sumiu da
/// barra do sistema. Tocar marca como lida; arrastar apaga. Mesma ideia
/// do app Resenha (NotificacoesScreen lá).
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repository = context.read<NotificationsRepository>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notificações'),
        actions: [
          // Pedido do Franck: "adicionar a opção marcar todas como
          // lidas" — o botão já existia, mas ficava sempre clicável
          // mesmo sem nada pra marcar (parecia não fazer nada) e não
          // dava nenhuma confirmação depois de tocar. Agora some/
          // desabilita quando já está tudo lido e avisa quando termina.
          StreamBuilder<int>(
            stream: repository.watchUnreadCount(),
            builder: (context, snapshot) {
              final hasUnread = (snapshot.data ?? 0) > 0;
              return TextButton(
                onPressed: hasUnread
                    ? () async {
                        await repository.markAllAsRead();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Todas as notificações foram marcadas como lidas.')),
                          );
                        }
                      }
                    : null,
                child: const Text('Marcar tudo como lida'),
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<List<AppNotification>>(
        stream: repository.watchAll(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final notifications = snapshot.data ?? const [];
          if (notifications.isEmpty) {
            return const _EmptyState();
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            itemCount: notifications.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final n = notifications[index];
              return Dismissible(
                key: ValueKey(n.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.delete_outline, color: AppColors.danger),
                ),
                onDismissed: (_) => repository.delete(n.id),
                child: _NotificationTile(
                  notification: n,
                  onTap: () {
                    if (!n.read) repository.markAsRead(n.id);
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, required this.onTap});

  final AppNotification notification;
  final VoidCallback onTap;

  IconData get _icon => switch (notification.type) {
        AppNotificationType.newBudgetRequest => Icons.request_quote_outlined,
        AppNotificationType.budgetRequestResponded => Icons.reply_outlined,
        AppNotificationType.other => Icons.notifications_outlined,
      };

  @override
  Widget build(BuildContext context) {
    String horario = '';
    if (notification.createdAt != null) {
      try {
        horario = DateFormat("dd/MM 'às' HH:mm", 'pt_BR').format(notification.createdAt!);
      } catch (_) {
        horario = DateFormat('dd/MM HH:mm').format(notification.createdAt!);
      }
    }

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: notification.read ? AppColors.surface : AppColors.primary.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: notification.read
                ? const Color(0xFFDDE4EE)
                : AppColors.primary.withValues(alpha: 0.25),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(_icon, color: AppColors.primary, size: 19),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notification.title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: notification.read ? FontWeight.w600 : FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(notification.body, style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
                  if (horario.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(horario, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                  ],
                ],
              ),
            ),
            if (!notification.read)
              Container(
                margin: const EdgeInsets.only(left: 6, top: 4),
                width: 9,
                height: 9,
                decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

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
              child: const Icon(Icons.notifications_none_outlined, color: AppColors.primary, size: 38),
            ),
            const SizedBox(height: 18),
            const Text(
              'Nenhuma notificação ainda',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              'Novos pedidos de orçamento e respostas vão aparecer aqui.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
