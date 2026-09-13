/// Flags temporárias só pra testar mais rápido, sem esperar o Play
/// Billing/Play Console (ou o StoreKit/App Store Connect) estarem prontos
/// de verdade — NUNCA devem ir pra produção ligadas assim.
///
/// Combinado com o Franck (27/08): enquanto o produto de assinatura não
/// está cadastrado no Play Console (ver README.md, "Assinatura mensal do
/// prestador"), "virar prestador" volta a ser de graça — sem paywall,
/// `listingStatus` já nasce/vira `'active'` — só pra dar pra testar a
/// busca/listagem do lado do cliente sem depender da configuração externa.
///
/// Religada em 10/09: o lado Apple (App Store Connect) ainda está preso
/// num travamento no envio pra revisão da assinatura ("Novos grupos de
/// assinatura devem ser enviados com uma assinatura com renovação
/// automática desse grupo" — parece bug conhecido do App Store Connect,
/// não erro de configuração nossa). Enquanto isso não resolve, volta a
/// bypassar pra não travar o resto do teste no iPhone.
///
/// **Antes de publicar de verdade**: mude isto pra `false`. Os dois
/// lugares que usam essa flag (`AuthController._createProviderDocument`/
/// `updateProviderBusinessInfo` e
/// `UserProfileScreen._BecomeProviderSheet._submit`) voltam sozinhos a
/// exigir a assinatura de verdade — não precisa reverter mais nada além
/// de trocar esse valor aqui.
const bool kBypassProviderSubscriptionGate = true;

/// Liga o rastro de diagnóstico do push em `clients/{uid}.pushDebug`
/// (ver `NotificationService._debugLog`).
///
/// Nasceu porque o Franck testa por TestFlight, sem cabo e sem
/// Console.app: `debugPrint` não servia de nada, e o Firebase Console era
/// a única janela que ele conseguia abrir pra ver o que o app estava
/// fazendo por dentro. Foi essa instrumentação que provou que NENHUM dos
/// dois callbacks da APNs era chamado — e daí saiu a causa real do bug (o
/// template novo do Flutter registra os plugins só depois do
/// `didFinishLaunchingWithOptions`, então o registro na APNs que o
/// firebase_messaging faria nunca acontecia; ver
/// ios/Runner/AppDelegate.swift).
///
/// **Desligada agora que o push funciona.** Ligada, são ~8 a 10 escritas
/// no Firestore a cada primeira abertura do app por conta, pra produzir
/// um dado que ninguém lê mais.
///
/// O código do diagnóstico continua todo lá, de propósito: se o push
/// voltar a falhar num aparelho específico, é só mudar isto pra `true`,
/// gerar uma build e o rastro volta inteiro — bem melhor que remontar do
/// zero, que da última vez levou várias rodadas de tentativa e erro (e
/// três hipóteses erradas) até chegar na causa.
const bool kGravarDiagnosticoDePush = false;
