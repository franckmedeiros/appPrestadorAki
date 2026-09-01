import 'package:cloud_firestore/cloud_firestore.dart';

/// Tipos de notificação gravados pelas Cloud Functions (ver
/// functions/src/notifications.ts) — só decide o ícone certo na lista, o
/// texto (title/body) já vem pronto do backend. Os valores de fio
/// ('novo_pedido'/'resposta_pedido') continuam os mesmos de antes — só a
/// origem mudou, de gatilhos em `serviceRequests` para gatilhos em
/// `providers/{uid}/budgets` (ver `Budget`/`BudgetStatus`).
enum AppNotificationType { newBudgetRequest, budgetRequestResponded, other }

AppNotificationType appNotificationTypeFromWire(String? value) => switch (value) {
      'novo_pedido' => AppNotificationType.newBudgetRequest,
      'resposta_pedido' => AppNotificationType.budgetRequestResponded,
      _ => AppNotificationType.other,
    };

/// Um item da central de notificações (sininho — ver NotificationBell),
/// salvo em `clients/{uid}/notifications/{id}` (ver DATA_MODEL.md e
/// firestore.rules) — é o registro "permanente" do mesmo aviso que também
/// chega como push: a notificação do sistema some depois de vista, esta
/// fica guardada até o usuário marcar como lida ou apagar, pra sempre dar
/// pra ver "o que eu perdi" dentro do app.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    this.budgetId,
    required this.read,
    this.createdAt,
  });

  factory AppNotification.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return AppNotification(
      id: doc.id,
      type: appNotificationTypeFromWire(data['type'] as String?),
      title: data['title'] as String? ?? '',
      body: data['body'] as String? ?? '',
      budgetId: data['budgetId'] as String?,
      read: data['read'] as bool? ?? false,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  final String id;
  final AppNotificationType type;
  final String title;
  final String body;
  final String? budgetId;
  final bool read;
  final DateTime? createdAt;
}
