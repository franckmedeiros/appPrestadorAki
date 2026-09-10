import Flutter
import UIKit

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
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Canal só de leitura: o Dart pergunta "o que aconteceu com o registro
    // na APNs?" e recebe o que os callabcks abaixo gravaram.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ApnsDiagnostico") {
      let canal = FlutterMethodChannel(
        name: "prestadoraki/apns",
        binaryMessenger: registrar.messenger()
      )
      canal.setMethodCallHandler { call, result in
        guard call.method == "lerDiagnostico" else {
          result(FlutterMethodNotImplemented)
          return
        }
        var resposta = UserDefaults.standard.dictionary(forKey: AppDelegate.diagnosticoKey) ?? [:]
        // Complementa com o que só dá pra saber na hora da pergunta.
        resposta["registradoAgora"] = UIApplication.shared.isRegisteredForRemoteNotifications
        result(resposta)
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
  /// Se este for o callback que aparece no `pushDebug` e ainda assim o
  /// token do FCM não sair, o problema está na ponte APNs → Firebase
  /// Messaging (registro do app no Firebase, chave .p8, bundle id), não
  /// na configuração nativa da Apple.
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

  /// A Apple RECUSOU o registro. É o cenário mais informativo dos três: o
  /// `erro`/`dominio`/`codigo` gravados aqui dizem exatamente o que está
  /// errado (entitlement `aps-environment` ausente na assinatura, App ID
  /// sem a capacidade Push, aparelho sem rede na hora, etc.).
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
