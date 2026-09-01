import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Handler de mensagens recebidas com o app em segundo plano ou fechado.
/// PRECISA ser uma função de nível top-level (fora de qualquer classe) e
/// anotada com `@pragma('vm:entry-point')` — é assim que o FCM exige,
/// porque esse código roda num isolate separado, sem acesso ao estado do
/// app. Não precisa fazer nada aqui: o próprio sistema operacional já
/// mostra a notificação sozinho nesse caso (usamos mensagens do tipo
/// "notification", não só "data"), isso só existe pra registrar o
/// handler exigido pelo plugin. Registrado em main.dart.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

/// Cuida de tudo relacionado a notificações push: pedir permissão, guardar
/// o token do aparelho (pro backend saber pra quem mandar — ver
/// functions/src/notifications.ts), e mostrar a notificação na hora
/// quando o app está aberto (o FCM não faz isso sozinho em primeiro plano
/// no Android). Mesmo desenho já usado no app Resenha.
///
/// O token é salvo em `clients/{uid}` (conta unificada — TODA conta
/// autenticada tem esse documento, ver DATA_MODEL.md) e, quando a mesma
/// conta também é prestador, também em `providers/{uid}` — porque as
/// Cloud Functions escolhem de qual dessas coleções ler o token conforme
/// quem está sendo avisado (o prestador que recebeu um pedido novo, ou o
/// cliente que recebeu uma resposta).
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  static const _channel = AndroidNotificationChannel(
    'prestadoraki_avisos',
    'Avisos do PrestadorAki',
    description: 'Novos pedidos de orçamento e respostas a pedidos',
    importance: Importance.high,
  );

  bool _started = false;

  /// Chamado toda vez que o UnifiedShell (a casca única do app,
  /// alcançada por qualquer conta logada, prestador ou não) reconstrói —
  /// antes só rodava dentro de ClientHomeScreen (aba "Buscar"), e um
  /// prestador que nunca abrisse essa aba nunca tinha o token FCM salvo,
  /// então nunca recebia o push (com som) de "novo pedido de orçamento",
  /// só a entrada na central de notificações. Seguro de chamar mais de
  /// uma vez — só faz efeito na primeira.
  Future<void> init() async {
    if (_started) return;
    _started = true;

    try {
      await _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_channel);

      await _localNotifications.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );

      await _messaging.requestPermission(alert: true, badge: true, sound: true);

      await _saveCurrentToken();
      _messaging.onTokenRefresh.listen((_) => _saveCurrentToken());

      // Com o app ABERTO, o Android não mostra a notificação sozinho —
      // aqui a gente escuta e exibe manualmente com o mesmo visual de uma
      // notificação normal.
      FirebaseMessaging.onMessage.listen(_showLocalNotification);
    } catch (e) {
      // Notificação é um "extra" — se der qualquer problema (permissão
      // negada, aparelho sem Google Play Services etc.), o app continua
      // funcionando normal, só sem push.
      debugPrint('Não foi possível configurar notificações: $e');
    }
  }

  Future<void> _saveCurrentToken() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final token = await _messaging.getToken();
    if (token == null) return;

    final firestore = FirebaseFirestore.instance;
    final now = FieldValue.serverTimestamp();

    try {
      await firestore
          .collection('clients')
          .doc(uid)
          .set({'fcmToken': token, 'fcmTokenUpdatedAt': now}, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Não foi possível salvar o token de notificação (clients): $e');
    }

    // Só atualiza providers/{uid} se ele já existir — nunca cria essa
    // coleção sozinho a partir daqui (quem cria é a Cloud Function de
    // assinatura, ver DATA_MODEL.md).
    try {
      final providerRef = firestore.collection('providers').doc(uid);
      final snapshot = await providerRef.get();
      if (snapshot.exists) {
        await providerRef.set({'fcmToken': token, 'fcmTokenUpdatedAt': now}, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('Não foi possível salvar o token de notificação (providers): $e');
    }
  }

  void _showLocalNotification(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;
    _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
    );
  }
}
