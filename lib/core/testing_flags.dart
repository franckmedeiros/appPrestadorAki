/// Flags temporárias só pra testar mais rápido, sem esperar o Play
/// Billing/Play Console estarem prontos de verdade — NUNCA devem ir pra
/// produção ligadas assim.
///
/// Combinado com o Franck (27/08): enquanto o produto de assinatura não
/// está cadastrado no Play Console (ver README.md, "Assinatura mensal do
/// prestador"), "virar prestador" volta a ser de graça — sem paywall,
/// `listingStatus` já nasce/vira `'active'` — só pra dar pra testar a
/// busca/listagem do lado do cliente sem depender da configuração externa.
///
/// **Antes de publicar de verdade**: mude isto pra `false`. Os dois
/// lugares que usam essa flag (`AuthController._createProviderDocument`/
/// `updateProviderBusinessInfo` e
/// `UserProfileScreen._BecomeProviderSheet._submit`) voltam sozinhos a
/// exigir a assinatura de verdade — não precisa reverter mais nada além
/// de trocar esse valor aqui.
const bool kBypassProviderSubscriptionGate = true;
