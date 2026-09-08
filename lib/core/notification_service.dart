import 'dart:io' show Platform;

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
/// Erro "esperado" de tentar de novo depois (FCM devolveu null
/// momentaneamente, comum logo após instalar) — nunca é um bug de
/// verdade, só existe pra fazer `_saveCurrentToken()` terminar com uma
/// EXCEÇÃO (não um `return` normal). Ver o comentário grande em `init()`
/// sobre `_started`: se `_saveCurrentToken()` retornasse normalmente
/// aqui, `init()` marcaria `_started = true` mesmo sem o token ter sido
/// salvo — e como essa flag nunca mais volta a `false` sozinha, o app
/// pararia de tentar de novo PRA SEMPRE (até matar o processo de
/// verdade), mesmo trocando de aba centenas de vezes depois. Esse era um
/// bug real e silencioso. Distinta de `_debugLog(..., 'step')` — que já
/// registra a etapa específica — pra não deixar o catch genérico de
/// baixo sobrescrever esse registro com uma mensagem menos útil.
class _PushRetryLater implements Exception {
  const _PushRetryLater(this.message);
  final String message;
  @override
  String toString() => message;
}

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

  /// Grava um rastro do que está acontecendo em `clients/{uid}.pushDebug`
  /// — criado pra debugar o push no iPhone do Franck sem precisar de
  /// cabo/Console.app (ele não tem acesso a USB nesse computador): o
  /// Firebase Console → Firestore já é a ferramenta que ele consegue
  /// abrir, então em vez de só `debugPrint` (que ele não tem como ver
  /// numa build de TestFlight sem USB), cada etapa importante do processo
  /// de pedir permissão/pegar token também fica registrada aqui, um campo
  /// só que vai sendo sobrescrito a cada passo (não uma lista — não
  /// precisamos de histórico, só do ÚLTIMO estado conhecido). Nunca deixa
  /// uma falha AQUI derrubar o fluxo de verdade — por isso o try/catch
  /// próprio, silencioso.
  Future<void> _debugLog(String? uid, String step, [Map<String, dynamic>? extra]) async {
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance.collection('clients').doc(uid).set({
        'pushDebug': {
          'step': step,
          'platform': kIsWeb ? 'web' : (Platform.isIOS ? 'ios' : 'android'),
          'at': FieldValue.serverTimestamp(),
          ...?extra,
        },
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[NotificationService] Não foi possível gravar pushDebug ($step): $e');
    }
  }

  /// Chamado toda vez que o UnifiedShell (a casca única do app,
  /// alcançada por qualquer conta logada, prestador ou não) reconstrói —
  /// antes só rodava dentro de ClientHomeScreen (aba "Buscar"), e um
  /// prestador que nunca abrisse essa aba nunca tinha o token FCM salvo,
  /// então nunca recebia o push (com som) de "novo pedido de orçamento",
  /// só a entrada na central de notificações. Seguro de chamar mais de
  /// uma vez — só faz efeito na primeira.
  Future<void> init() async {
    if (_started) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    await _debugLog(uid, 'init_start');

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

      // Só pede a permissão quando ainda não há NENHUMA decisão registrada
      // no sistema (`notDetermined`) — tanto no Android 13+ (runtime
      // permission POST_NOTIFICATIONS) quanto no iOS, o próprio SO só
      // mostra o diálogo de verdade nesse caso; chamando `requestPermission`
      // de novo depois de já decidido (autorizado OU negado) ele NUNCA
      // reabre o pop-up, só devolve a decisão antiga silenciosamente — daí
      // o relato mais comum de "o app não pergunta mais": não é bug, é o
      // comportamento normal do Android/iOS quando essa MESMA instalação
      // já passou por essa pergunta uma vez (mesmo numa versão antiga,
      // antes de qualquer correção aqui). Atualizar o app por cima (sem
      // desinstalar) NUNCA reabre essa pergunta. Checar aqui, em vez de só
      // chamar `requestPermission` direto, deixa isso explícito e — mais
      // importante — deixa um rastro no log (`adb logcat` / `flutter logs`,
      // filtrando por "NotificationService") pra confirmar com certeza qual
      // dos três estados o aparelho já está: nunca perguntado, autorizado,
      // ou negado.
      final statusAntes = await _messaging.getNotificationSettings();
      debugPrint(
          '[NotificationService] Status de permissão antes: ${statusAntes.authorizationStatus}');
      await _debugLog(uid, 'permission_status_before',
          {'status': statusAntes.authorizationStatus.toString()});

      switch (statusAntes.authorizationStatus) {
        case AuthorizationStatus.notDetermined:
          try {
            final statusDepois = await _messaging.requestPermission(
              alert: true,
              badge: true,
              sound: true,
            );
            debugPrint(
                '[NotificationService] Usuário respondeu ao pedido de permissão: ${statusDepois.authorizationStatus}');
            await _debugLog(uid, 'permission_result',
                {'status': statusDepois.authorizationStatus.toString()});
          } catch (e) {
            // Isolado num try/catch próprio (mesma lógica do plugin de
            // notificação local acima) pra distinguir no log "o SO nem
            // deixou perguntar" de "algo quebrou ao perguntar" — sem isso,
            // os dois caiam no mesmo catch genérico lá embaixo, com a
            // mesma mensagem, impossível de diferenciar sem debugar ao
            // vivo.
            debugPrint('[NotificationService] requestPermission() lançou uma exceção: $e');
            await _debugLog(uid, 'permission_exception', {'error': e.toString()});
          }
          break;
        case AuthorizationStatus.denied:
          debugPrint(
              '[NotificationService] Usuário já negou a permissão antes nesta instalação — '
              'não peço de novo (o Android/iOS não reabririam o diálogo mesmo se eu pedisse). '
              'Pra testar o pedido de novo, desinstale o app por completo (não só atualize por '
              'cima) e instale de novo.');
          await _debugLog(uid, 'permission_denied_before');
          break;
        case AuthorizationStatus.authorized:
        case AuthorizationStatus.provisional:
          debugPrint(
              '[NotificationService] Permissão já concedida anteriormente — nada a pedir.');
          await _debugLog(uid, 'permission_already_granted',
              {'status': statusAntes.authorizationStatus.toString()});
          break;
      }

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
      // Mesma lógica do catch de `_saveCurrentToken()` acima: pra
      // `_PushRetryLater` a etapa específica já foi registrada, não
      // sobrescreve com "init_exception" genérico.
      if (e is! _PushRetryLater) {
        await _debugLog(uid, 'init_exception', {'error': e.toString()});
      }
    }
  }

  /// Deixa qualquer erro subir pra quem chamou (`init()`, que decide se
  /// tenta de novo depois — ver comentário lá) em vez de engolir com
  /// try/catch só um debugPrint: antes, se o `.set()` no Firestore
  /// falhasse (regra de segurança, sem rede etc.), `init()` já tinha
  /// marcado `_started = true` e nunca mais tentava de novo, mesmo com o
  /// token do aparelho nunca tendo sido salvo — o cenário mais provável
  /// por trás de "desinstalei e instalei de novo e não gerou token".
  ///
  /// IMPORTANTE (correção depois de comparar com o app Resenha, que
  /// funciona no mesmo iPhone): esta versão TINHA um laço aqui esperando
  /// `_messaging.getAPNSToken()` responder antes de chamar `getToken()`,
  /// com até 5 tentativas de 1s. Essa espera não existe no Resenha — lá
  /// o código chama `getToken()` direto, sem nunca checar
  /// `getAPNSToken()` antes — e mesmo assim funciona nesse aparelho.
  /// Removido porque é a causa mais provável do `apns_timeout` que
  /// travava aqui pra sempre: `getAPNSToken()` só LÊ um valor já
  /// registrado nativamente (não força nada a acontecer), enquanto
  /// `getToken()` é o método que de fato aciona
  /// `registerForRemoteNotifications()` no iOS e espera a resposta da
  /// Apple internamente antes de devolver o token FCM. Ou seja: ficar
  /// checando `getAPNSToken()` ANTES de nunca ter chamado `getToken()`
  /// podia ficar esperando um registro que o próprio código nunca tinha
  /// disparado — daí nunca chegar, em NENHUMA tentativa, mesmo com
  /// permissão concedida, entitlement e provisioning corretos (tudo isso
  /// já verificado e descartado como causa). Chamar `getToken()` direto,
  /// como o Resenha faz, deixa o próprio plugin cuidar dessa espera.
  Future<void> _saveCurrentToken() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    await _debugLog(uid, 'save_token_start');

    try {
      final token = await _messaging.getToken();
      if (token == null) {
        debugPrint('[NotificationService] getToken() (FCM) devolveu null.');
        await _debugLog(uid, 'fcm_token_null');
        // `throw`, não `return` — ver doc de `_PushRetryLater` acima.
        throw const _PushRetryLater('getToken() (FCM) devolveu null.');
      }
      debugPrint('[NotificationService] FCM Token: $token');
      await _debugLog(uid, 'fcm_token_ok');

      final firestore = FirebaseFirestore.instance;
      final now = FieldValue.serverTimestamp();

      await firestore
          .collection('clients')
          .doc(uid)
          .set({'fcmToken': token, 'fcmTokenUpdatedAt': now}, SetOptions(merge: true));
      await _debugLog(uid, 'saved_ok');

      // Só atualiza providers/{uid} se ele já existir — nunca cria essa
      // coleção sozinho a partir daqui (quem cria é a Cloud Function de
      // assinatura, ver DATA_MODEL.md).
      final providerRef = firestore.collection('providers').doc(uid);
      final snapshot = await providerRef.get();
      if (snapshot.exists) {
        await providerRef.set({'fcmToken': token, 'fcmTokenUpdatedAt': now}, SetOptions(merge: true));
      }
    } catch (e) {
      // Registrado aqui ANTES de deixar subir (ver doc do método) — sem
      // isso, um erro nessa etapa (ex.: PERMISSION_DENIED da regra do
      // Firestore) só aparecia no `debugPrint` genérico do catch de
      // `init()`, invisível pra quem não tem como olhar o console/log do
      // aparelho. `_PushRetryLater` já registrou a etapa específica
      // (`fcm_token_null`) alguns milissegundos atrás — não sobrescreve
      // com essa mensagem genérica nesse caso.
      if (e is! _PushRetryLater) {
        await _debugLog(uid, 'save_token_exception', {'error': e.toString()});
      }
      rethrow;
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
