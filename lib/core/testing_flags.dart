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
