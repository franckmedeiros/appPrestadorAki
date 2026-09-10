import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MethodChannel;
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

  /// Trava de reentrada: `init()` é chamado a CADA rebuild do UnifiedShell
  /// (troca de aba, notifyListeners do AuthController...) e só marca
  /// `_started = true` no fim, quando tudo deu certo. Como agora a espera
  /// pelo token APNs no iOS pode levar alguns segundos (ver
  /// `_obterTokenFcm`), sem essa trava dois ou três `init()` rodariam ao
  /// mesmo tempo, cada um pedindo permissão/token em paralelo e
  /// atropelando o `pushDebug` um do outro.
  bool _rodando = false;

  /// `onTokenRefresh` é registrado UMA vez só, mesmo que `init()` seja
  /// repetido depois de uma falha.
  bool _ouvindoRefresh = false;

  /// Grava um rastro do que está acontecendo em `clients/{uid}.pushDebug`
  /// — criado pra debugar o push no iPhone do Franck sem precisar de
  /// cabo/Console.app (ele não tem acesso a USB nesse computador): o
  /// Firebase Console → Firestore já é a ferramenta que ele consegue
  /// abrir, então em vez de só `debugPrint` (que ele não tem como ver
  /// numa build de TestFlight sem USB), cada etapa importante do processo
  /// de pedir permissão/pegar token também fica registrada aqui.
  ///
  /// Cada etapa agora vira uma CHAVE PRÓPRIA dentro de `pushDebug`, em vez
  /// de sobrescrever um campo `step` único como era antes. Motivo prático:
  /// sobrescrevendo, só dava pra ver a última etapa, e justamente a
  /// informação que mais faltava (qual era o estado da permissão antes de
  /// tudo) já tinha sido apagada por etapas posteriores quando o Franck ia
  /// olhar. Como `set(..., merge: true)` faz merge PROFUNDO de mapa, cada
  /// chave se acumula sozinha e um print só do campo conta a história
  /// inteira. `ultimoPasso` continua dizendo onde parou.
  ///
  /// Nunca deixa uma falha AQUI derrubar o fluxo de verdade — por isso o
  /// try/catch próprio, silencioso.
  Future<void> _debugLog(String? uid, String step, [Map<String, dynamic>? extra]) async {
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance.collection('clients').doc(uid).set({
        'pushDebug': {
          'ultimoPasso': step,
          'platform': kIsWeb ? 'web' : (Platform.isIOS ? 'ios' : 'android'),
          'at': FieldValue.serverTimestamp(),
          step: {
            'at': FieldValue.serverTimestamp(),
            ...?extra,
          },
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
    if (_started || _rodando) return;
    _rodando = true;

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

      // CHAMADO SEMPRE, qualquer que seja o status anterior — mudança
      // importante depois de caçar o "APNS token has not been received on
      // the device yet" no iPhone do Franck.
      //
      // A versão anterior só chamava `requestPermission` quando o status
      // era `notDetermined`, com um raciocínio que está CERTO do ponto de
      // vista da PERGUNTA (o iOS/Android realmente nunca reabrem o pop-up
      // depois de uma decisão tomada, então pedir de novo não mostra nada)
      // mas que ignorava um efeito colateral essencial no iOS: é dentro
      // do `requestPermission` que o plugin chama o
      // `registerForRemoteNotifications` do iOS — o passo que de fato
      // manda o aparelho se registrar na Apple e receber o token APNs.
      // Pulando essa chamada, o registro nunca era disparado, o token
      // APNs nunca chegava, e o `getToken()` do FCM falhava pra sempre com
      // aquele erro — mesmo com a permissão JÁ concedida, entitlement
      // certo e chave .p8 no lugar.
      //
      // Chamar sempre é seguro: com a decisão já tomada, o SO devolve a
      // resposta antiga em silêncio (nenhum pop-up a mais pro usuário),
      // e o registro na APNs acontece do mesmo jeito.
      try {
        final statusDepois = await _messaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
        debugPrint(
            '[NotificationService] Permissão após requestPermission: ${statusDepois.authorizationStatus}');
        await _debugLog(uid, 'permission_result', {
          'status': statusDepois.authorizationStatus.toString(),
          'statusAntes': statusAntes.authorizationStatus.toString(),
        });
      } catch (e) {
        // Try/catch próprio pra distinguir no rastro "o SO nem deixou
        // perguntar" de "algo quebrou ao perguntar" — sem isso, os dois
        // cairiam no mesmo catch genérico lá embaixo, com a mesma
        // mensagem, impossível de diferenciar sem debugar ao vivo.
        debugPrint('[NotificationService] requestPermission() lançou uma exceção: $e');
        await _debugLog(uid, 'permission_exception', {'error': e.toString()});
      }

      switch (statusAntes.authorizationStatus) {
        case AuthorizationStatus.notDetermined:
          break;
        case AuthorizationStatus.denied:
          debugPrint(
              '[NotificationService] Usuário já negou a permissão antes nesta instalação — '
              'o pop-up não reabre (nem no Android nem no iOS). Pra testar a pergunta de novo, '
              'desinstale o app por completo (não só atualize por cima) e instale de novo, ou '
              'ligue na mão em Ajustes > Notificações.');
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

      // Registrado ANTES da primeira tentativa de salvar (antes era
      // depois) — essa ordem é a rede de segurança do caso do iPhone: no
      // iOS o token FCM só passa a existir depois que a Apple devolve o
      // token APNs pro aparelho, o que pode acontecer DEPOIS da nossa
      // primeira tentativa (justamente no cadastro, que é quando o
      // usuário acabou de aceitar a permissão). Quando isso acontece, o
      // próprio FCM dispara `onTokenRefresh` assim que consegue gerar o
      // token — com o listener já ligado, ele é salvo sozinho, sem
      // depender de o app tentar de novo. Na ordem antiga, se
      // `_saveCurrentToken()` lançasse (é o que faz quando o token vem
      // null), o listener NUNCA chegava a ser registrado.
      if (!_ouvindoRefresh) {
        _ouvindoRefresh = true;
        _messaging.onTokenRefresh.listen((_) async {
          await _debugLog(FirebaseAuth.instance.currentUser?.uid, 'token_refresh_recebido');
          await _saveCurrentToken()
              .catchError((e) => debugPrint('Não foi possível salvar o token renovado: $e'));
        });
      }

      await _saveCurrentToken();

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
    } finally {
      // Sempre libera a trava — com `_started` ainda false quando deu
      // errado, a próxima reconstrução do shell tenta tudo de novo.
      _rodando = false;
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
      final token = await _obterTokenFcm(uid);
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

  /// Pega o token FCM, tratando o caso do iOS (o motivo de "cadastrei pelo
  /// iPhone e o fcmToken não foi gravado").
  ///
  /// No Android o token existe assim que o Google Play Services responde,
  /// e `getToken()` resolve na primeira. No iOS existe um passo a mais no
  /// meio: o token FCM só pode ser gerado DEPOIS que a Apple devolveu o
  /// token APNs pro aparelho, e esse registro é assíncrono — começa quando
  /// o usuário aceita a permissão e pode levar de milissegundos a vários
  /// segundos (rede ruim, primeira instalação, aparelho acabando de sair
  /// do avião...). Como a permissão é pedida no MESMO instante do cadastro,
  /// a primeira tentativa cai justamente nessa janela: `getToken()` ou
  /// devolve null, ou lança `[firebase_messaging/apns-token-not-set]`.
  ///
  /// Uma versão antiga daqui esperava o APNs com no máximo 5 tentativas de
  /// 1s e DESISTIA de vez (`apns_timeout`) se não viesse — e foi removida
  /// por isso. Esta volta a esperar, mas com duas diferenças que resolvem
  /// o problema de antes: espera bem mais (até ~20s) e, principalmente,
  /// NUNCA desiste por causa disso — se o APNs não chegar, ainda assim
  /// tenta o `getToken()`, e o resultado (inclusive a mensagem de erro
  /// exata) fica registrado no `pushDebug` pra diferenciar as duas causas
  /// possíveis:
  ///   • `apns_token_ausente` → o aparelho nem chegou a se registrar na
  ///     Apple: problema de entitlement/provisioning/capability do app
  ///     (nada que o Firebase resolva).
  ///   • `apns_token_ok` + `fcm_token_erro` → o registro na Apple foi bem,
  ///     mas o Firebase não conseguiu emitir o token: quase sempre é a
  ///     chave de autenticação APNs (.p8) que falta no Firebase Console
  ///     (Configurações do projeto → Cloud Messaging → app da Apple).
  Future<String?> _obterTokenFcm(String uid) async {
    if (!kIsWeb && Platform.isIOS) {
      var tentativas = 0;
      var apns = await _lerApnsToken();
      while (apns == null && tentativas < 20) {
        await Future.delayed(const Duration(seconds: 1));
        apns = await _lerApnsToken();
        tentativas++;
      }
      await _debugLog(
        uid,
        apns == null ? 'apns_token_ausente' : 'apns_token_ok',
        {'segundosEsperando': tentativas},
      );

      // O que o iOS respondeu ao pedido de registro, direto do
      // AppDelegate (ver ios/Runner/AppDelegate.swift). É este registro
      // que separa os três cenários possíveis quando o token não vem:
      //
      //   APNS_TOKEN_RECEBIDO → a Apple aceitou e entregou o token; se
      //     mesmo assim o FCM falha, o problema está na ponte APNs →
      //     Firebase (registro do app no Firebase, chave .p8, bundle id).
      //   ERRO_AO_REGISTRAR   → a Apple recusou; o `erro`/`dominio`/
      //     `codigo` dizem exatamente o quê (entitlement, App ID, rede).
      //   NENHUM_CALLBACK     → o app nunca chegou a pedir o registro; o
      //     problema está na inicialização/ciclo de vida nativo.
      final diagnostico = await _lerDiagnosticoApnsNativo();
      await _debugLog(
        uid,
        'apns_callback_nativo',
        diagnostico.isEmpty ? {'resultado': 'NENHUM_CALLBACK'} : diagnostico,
      );
    }

    // Até 3 tentativas espaçadas: mesmo com o APNs no lugar, a primeira
    // chamada logo depois de instalar às vezes falha por rede. No iOS sem
    // token APNs isso vai falhar 3 vezes seguidas de propósito — o
    // objetivo aí não é conseguir o token (não tem como), é deixar a
    // mensagem de erro exata gravada no pushDebug.
    for (var tentativa = 1; tentativa <= 3; tentativa++) {
      try {
        final token = await _messaging.getToken();
        if (token != null) return token;
        await _debugLog(uid, 'fcm_token_null_tentativa', {'tentativa': tentativa});
      } catch (e) {
        // A mensagem já vem com o código do plugin no começo (ex.:
        // "[firebase_messaging/apns-token-not-set] ..."), que é
        // exatamente o que precisamos ver pra saber o que está faltando.
        debugPrint('[NotificationService] getToken() falhou (tentativa $tentativa): $e');
        await _debugLog(uid, 'fcm_token_erro', {
          'tentativa': tentativa,
          'error': e.toString(),
        });
      }
      if (tentativa < 3) {
        await Future.delayed(Duration(seconds: 3 * tentativa));
      }
    }
    return null;
  }

  /// Canal só de leitura pro diagnóstico gravado pelo AppDelegate — ver
  /// `prestadoraki/apns` em ios/Runner/AppDelegate.swift.
  static const _canalApns = MethodChannel('prestadoraki/apns');

  /// Pergunta ao lado nativo o que aconteceu com o registro na APNs.
  ///
  /// Devolve um mapa vazio quando não há nada gravado — o que já é uma
  /// resposta: significa que NENHUM dos dois callbacks do iOS foi
  /// chamado, ou seja, o app nunca chegou a pedir o registro. Nunca
  /// lança: no Android (ou se o canal não estiver registrado) só devolve
  /// vazio, porque isso aqui é diagnóstico, não pode derrubar o push.
  Future<Map<String, dynamic>> _lerDiagnosticoApnsNativo() async {
    if (kIsWeb || !Platform.isIOS) return const {};
    try {
      final resposta = await _canalApns.invokeMapMethod<String, dynamic>('lerDiagnostico');
      return resposta ?? const {};
    } catch (e) {
      debugPrint('[NotificationService] Não foi possível ler o diagnóstico da APNs: $e');
      return {'erroAoLerDiagnostico': e.toString()};
    }
  }

  /// Lê o token APNs devolvendo `null` quando ele ainda não chegou.
  ///
  /// Existe por um motivo bem concreto: `getAPNSToken()` do
  /// firebase_messaging NÃO devolve null nesse caso — ele LANÇA
  /// `[firebase_messaging/apns-token-not-set] APNS token has not been
  /// received on the device yet`. A primeira versão do laço de espera aqui
  /// assumia null e chamava `getAPNSToken()` direto, então estourava já na
  /// primeira tentativa e a espera de 20 segundos nunca acontecia de
  /// verdade — ela ia embora pelo `catch` de cima antes do primeiro
  /// `Future.delayed`. Traduzir a exceção em "ainda não" é o que faz o
  /// laço realmente esperar.
  Future<String?> _lerApnsToken() async {
    try {
      return await _messaging.getAPNSToken();
    } catch (e) {
      debugPrint('[NotificationService] APNs ainda não disponível: $e');
      return null;
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
