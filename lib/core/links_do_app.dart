/// Endereços do PrestadorAki na web, num lugar só.
///
/// Existiam três cópias do mesmo domínio espalhadas — no rodapé do PDF de
/// orçamento, no QR Code do card de divulgação e (agora) no manual dentro
/// do app. Três lugares pra trocar quando o endereço mudar é três chances
/// de esquecer um; e ele vai mudar, no dia em que sair do
/// `.web.app` do Firebase pra um domínio próprio.
library;

/// Só o domínio, sem `https://` — é assim que ele aparece IMPRESSO no
/// rodapé dos documentos. Em papel, o `https://` é ruído: ninguém digita.
const String kDominioDoApp = 'prestadoraki.web.app';

/// Endereço completo, pra abrir no navegador ou virar QR Code.
const String kSiteDoApp = 'https://$kDominioDoApp';

/// Manual do prestador (ver `site/manual.html`). Sem `.html` porque o
/// `cleanUrls` do Firebase Hosting está ligado — é o endereço que se cola
/// num WhatsApp sem parecer caminho de arquivo.
const String kManualDoPrestador = '$kSiteDoApp/manual';

/// Como o app se chama nos documentos que ele gera.
const String kNomeDoApp = 'PrestadorAki';
