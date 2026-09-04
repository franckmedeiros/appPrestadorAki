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

    try {
      // Isolado num try/catch PRÓPRIO, separado do pedido de permissão/
      // token abaixo — bug real visto em produção (relatado pelo Franck:
      // "quando eu abro o app ele não pergunta se permite as
      // notificações"): antes, isso e o `_messaging.requestPermission`
      // estavam no MESMO try, então se a inicialização do plugin de
      // notificação local desse qualquer problema (ex.: plugin/versão
      // nativa desalinhada num aparelho específico), a exceção pulava
      // direto pro catch de fora e `requestPermission` NUNCA rodava — daí
      // o app nunca pedir permissão nenhuma (nem Android 13+, nem iOS) e
      // nunca salvar token, sem log nenhum visível pra quem está usando o
      // app. Notificação manual em primeiro plano (`_showLocalNotification`
      // abaixo) é um extra; não pode derrubar o que faz o push funcionar
      // de verdade.
      try {
        await _localNotifications
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(_channel);

        await _localNotifications.initialize(
          const InitializationSettings(
            android: AndroidInitializationSettings('@mipmap/ic_launcher'),
            // Sem isso, o lado Darwin do plugin nunca é inicializado — a
            // notificação manual que a gente mostra com o app aberto (ver
            // `_showLocalNotification` logo abaixo) simplesmente não
            // aparecia no iPhone, silenciosamente (nenhum erro, nenhum
            // log — só não tinha efeito nenhum). Não pede permissão de
            // novo aqui (`request...Permission: false`) porque isso já é
            // feito explicitamente logo abaixo, via
            // `_messaging.requestPermission`.
            iOS: DarwinInitializationSettings(
              requestAlertPermission: false,
              requestBadgePermission: false,
              requestSoundPermission: false,
            ),
          ),
        );
      } catch (e) {
        debugPrint('Não foi possível inicializar flutter_local_notifications: $e');
      }

      await _messaging.requestPermission(alert: true, badge: true, sound: true);

      await _saveCurrentToken();
      _messaging.onTokenRefresh.listen(
        (_) => _saveCurrentToken()
            .catchError((e) => debugPrint('Não foi possível salvar o token renovado: $e')),
      );

      // Com o app ABERTO, o Android não mostra a notificação sozinho —
      // aqui a gente escuta e exibe manualmente com o mesmo visual de uma
      // notificação normal.
      FirebaseMessaging.onMessage.listen(_showLocalNotification);

      // Só marca como "pronto" DEPOIS de tudo ter funcionado de verdade —
      // antes `_started = true` era setado logo no início, então se
      // `getToken()`/o salvamento no Firestore falhasse uma vez (ex: sem
      // internet ainda bem no instante em que o app acabou de abrir, ou o
      // Google Play Services ainda inicializando logo depois de uma
      // instalação nova), o app nunca mais tentava de novo dentro do
      // mesmo processo — só resolvia matando o app de verdade (não
      // bastava fechar pelos recentes e reabrir, o processo continua
      // vivo). Agora, como `init()` já é chamado de novo a cada rebuild
      // do UnifiedShell (troca de aba, por exemplo — ver ali), uma falha
      // aqui simplesmente tenta de novo na próxima vez sozinha.
      _started = true;
    } catch (e) {
      // Notificação é um "extra" — se der qualquer problema (permissão
      // negada, aparelho sem Google Play Services etc.), o app continua
      // funcionando normal, só sem push. `_started` continua false de
      // propósito (ver comentário acima) pra tentar de novo depois.
      debugPrint('Não foi possível configurar notificações: $e');
    }
  }

  /// Deixa qualquer erro subir pra quem chamou (`init()`, que decide se
  /// tenta de novo depois — ver comentário lá) em vez de engolir com
  /// try/catch só um debugPrint: antes, se o `.set()` no Firestore
  /// falhasse (regra de segurança, sem rede etc.), `init()` já tinha
  /// marcado `_started = true` e nunca mais tentava de novo, mesmo com o
  /// token do aparelho nunca tendo sido salvo — o cenário mais provável
  /// por trás de "desinstalei e instalei de novo e não gerou token".
  Future<void> _saveCurrentToken() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final token = await _messaging.getToken();
    if (token == null) return;

    final firestore = FirebaseFirestore.instance;
    final now = FieldValue.serverTimestamp();

    await firestore
        .collection('clients')
        .doc(uid)
        .set({'fcmToken': token, 'fcmTokenUpdatedAt': now}, SetOptions(merge: true));

    // Só atualiza providers/{uid} se ele já existir — nunca cria essa
    // coleção sozinho a partir daqui (quem cria é a Cloud Function de
    // assinatura, ver DATA_MODEL.md).
    final providerRef = firestore.collection('providers').doc(uid);
    final snapshot = await providerRef.get();
    if (snapshot.exists) {
      await providerRef.set({'fcmToken': token, 'fcmTokenUpdatedAt': now}, SetOptions(merge: true));
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
        // Mesmo motivo do `iOS:` em `init()` acima — sem isso a
        // notificação manual nunca aparecia com o app aberto no iPhone.
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );
  }
}
