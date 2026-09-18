import 'dart:io' show Platform;

/// Flags temporárias só pra testar mais rápido, sem esperar o Play
/// Billing/Play Console (ou o StoreKit/App Store Connect) estarem prontos
/// de verdade — NUNCA devem ir pra produção ligadas assim.
///
/// HISTÓRICO: ficou ligada desde 27/08, quando o produto de assinatura
/// ainda não existia no Play Console e "virar prestador" precisava ser de
/// graça só pra dar pra testar a busca do lado do cliente. Foi religada em
/// 10/09 por causa de um travamento no App Store Connect no envio do grupo
/// de assinatura pra revisão ("Novos grupos de assinatura devem ser
/// enviados com uma assinatura com renovação automática desse grupo").
///
/// AGORA É POR PLATAFORMA (18/09). O Android já tem a assinatura pronta no
/// Play, o iOS ainda não — e uma flag só, valendo pros dois, obrigava a
/// escolher entre deixar o Android sem paywall ou pôr o iPhone numa tela
/// de compra que não consegue concluir. Nenhuma das duas serve.
///
/// Ligar o paywall onde ele funciona é o que permite testar a compra de
/// verdade sem quebrar o teste na outra loja.
const bool _bypassNoAndroid = false; // Play Billing pronto: paywall VALENDO
const bool _bypassNoIOS = true; //     App Store Connect travado: ainda bypassa

/// **Quando a Apple destravar**: mude `_bypassNoIOS` pra `false`. Os três
/// lugares que usam esta flag (`AuthController._createProviderDocument` e
/// `updateProviderBusinessInfo`, e
/// `UserProfileScreen._BecomeProviderSheet._submit`) voltam sozinhos a
/// exigir a assinatura — não precisa mexer em mais nada.
///
/// Fora de Android e iOS (desktop, usado só em desenvolvimento) não existe
/// loja pra cobrar, então bypassa: senão não dá nem pra abrir a tela de
/// prestador numa máquina de desenvolvimento.
bool get kBypassProviderSubscriptionGate {
  if (Platform.isAndroid) return _bypassNoAndroid;
  if (Platform.isIOS) return _bypassNoIOS;
  return true;
}

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
