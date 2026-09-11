import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Chave no UserDefaults onde fica guardado o resultado do registro na
  /// APNs (ver os dois callbacks lá embaixo).
  ///
  /// Por que passar por UserDefaults em vez de simplesmente logar: esses
  /// callbacks são do iOS e podem acontecer ANTES de o Flutter estar de
  /// pé, então não dá pra empurrar direto pro Dart na hora. E um `print`
  /// aqui não serviria de nada no caso do Franck — ele testa por
  /// TestFlight, sem cabo, sem Console.app. Gravando aqui, o Dart lê
  /// quando quiser (ver NotificationService._lerDiagnosticoApnsNativo) e
  /// manda pro `pushDebug` no Firestore, que é o que ele consegue abrir.
  private static let diagnosticoKey = "apnsDiagnostico"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let resultado = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    // ESTA LINHA É A CORREÇÃO DO PUSH NO iOS.
    //
    // Sem ela, ninguém no app pedia o registro do aparelho na APNs — e o
    // diagnóstico provou isso: nenhum dos dois callbacks abaixo era
    // chamado, e `isRegisteredForRemoteNotifications` era `false`. Sem
    // registro não existe token da APNs, e sem token da APNs o
    // `getToken()` do Firebase Messaging falha pra sempre com
    // "[firebase_messaging/apns-token-not-set]".
    //
    // O app dependia de o plugin firebase_messaging fazer esse registro
    // sozinho, o que ele normalmente faz a partir deste mesmo
    // `didFinishLaunchingWithOptions`. Só que este projeto usa o template
    // novo do Flutter, com ciclo de vida baseado em UIScene: os plugins
    // só são registrados depois, no `didInitializeImplicitFlutterEngine`
    // logo abaixo — ou seja, quando o plugin entra em cena, este momento
    // do lançamento JÁ PASSOU, e o registro que ele faria nunca acontece.
    //
    // Pedir o registro aqui, explicitamente, não depende de plugin nenhum.
    // É seguro chamar mesmo antes de o usuário decidir sobre a permissão:
    // o token do aparelho não exige permissão de alerta (ela controla o
    // que aparece na tela, não o registro), e chamar mais de uma vez é
    // inofensivo — o iOS devolve o mesmo token.
    application.registerForRemoteNotifications()

    return resultado
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Canal de apoio ao push: o Dart lê o diagnóstico gravado pelos
    // callbacks abaixo e pode pedir um novo registro na APNs.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ApnsDiagnostico") {
      let canal = FlutterMethodChannel(
        name: "prestadoraki/apns",
        binaryMessenger: registrar.messenger()
      )
      canal.setMethodCallHandler { call, result in
        switch call.method {
        case "lerDiagnostico":
          var resposta = UserDefaults.standard.dictionary(forKey: AppDelegate.diagnosticoKey) ?? [:]
          if resposta["resultado"] == nil {
            // Deixa explícito no Firestore que nenhum callback rodou, em
            // vez de o mapa chegar lá só com `registradoAgora` e a
            // ausência ter que ser deduzida.
            resposta["resultado"] = "NENHUM_CALLBACK_AINDA"
          }
          resposta["registradoAgora"] = UIApplication.shared.isRegisteredForRemoteNotifications
          result(resposta)

        case "registrarNaApns":
          // Segunda garantia, chamada pelo Dart DEPOIS de o Firebase estar
          // inicializado e a permissão resolvida. O registro no
          // `didFinishLaunchingWithOptions` acima acontece cedo demais
          // para o Firebase Messaging ter sido configurado (isso só
          // ocorre quando o Dart roda `Firebase.initializeApp`), então
          // um token que chegasse naquele instante poderia não ser
          // aproveitado. Pedindo de novo aqui, com tudo de pé, o token
          // chega no momento certo.
          DispatchQueue.main.async {
            UIApplication.shared.registerForRemoteNotifications()
          }
          result(true)

        case "definirBadge":
          // Contador do ícone do app. Quem DEFINE o número quando a
          // notificação chega é o próprio push (campo `badge`, ver
          // functions/src/notifications.ts) — este canal existe pro
          // outro lado da história: zerar/ajustar o contador quando a
          // pessoa LÊ as notificações dentro do app, algo que nenhum
          // push consegue fazer (o servidor não sabe que ela leu).
          let quantidade = (call.arguments as? [String: Any])?["quantidade"] as? Int ?? 0
          DispatchQueue.main.async {
            if #available(iOS 16.0, *) {
              UNUserNotificationCenter.current().setBadgeCount(max(0, quantidade))
            } else {
              UIApplication.shared.applicationIconBadgeNumber = max(0, quantidade)
            }
          }
          result(true)

        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
  }

  private func salvarDiagnostico(_ dados: [String: Any]) {
    var comData = dados
    comData["quando"] = ISO8601DateFormatter().string(from: Date())
    UserDefaults.standard.set(comData, forKey: AppDelegate.diagnosticoKey)
  }

  /// A Apple ACEITOU o registro e entregou o token do aparelho.
  ///
  /// Guarda só o começo do token, não ele inteiro: o que interessa é
  /// saber que chegou e que tem o tamanho esperado; o valor completo é um
  /// identificador do aparelho e não precisa parar no Firestore.
  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
    salvarDiagnostico([
      "resultado": "APNS_TOKEN_RECEBIDO",
      "tokenPrefixo": String(hex.prefix(12)),
      "tokenTamanho": hex.count,
    ])
    // OBRIGATÓRIO chamar o super: é por aqui que o Firebase Messaging
    // recebe o token (ele intercepta este mesmo callback). Sem isso, a
    // instrumentação quebraria justamente o que ela veio medir.
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  /// A Apple RECUSOU o registro. O `erro`/`dominio`/`codigo` gravados aqui
  /// dizem exatamente o que está errado (entitlement `aps-environment`
  /// ausente na assinatura, App ID sem a capacidade Push, aparelho sem
  /// rede na hora, etc.).
  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    let erro = error as NSError
    salvarDiagnostico([
      "resultado": "ERRO_AO_REGISTRAR",
      "erro": erro.localizedDescription,
      "dominio": erro.domain,
      "codigo": erro.code,
    ])
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }
}
