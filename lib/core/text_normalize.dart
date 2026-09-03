/// Remove acentos e ignora maiúsculas/minúsculas pra comparar texto sem
/// exigir digitação exata.
///
/// Extraído de `ClientHomeScreen` (era um método privado só dela) porque
/// agora tem mais de um lugar que precisa da mesma comparação: os
/// seletores de Estado/Cidade (`widgets/state_city_fields.dart`) e o
/// `ProviderDirectoryRepository`, que passou a comparar cidade de forma
/// tolerante a acento pra casar cadastros antigos gravados com grafias
/// diferentes da mesma cidade (ex.: "Criciuma" sem acento x "Criciúma"
/// com acento — ver a nota em `ProviderDirectoryRepository.search`).
const _accented = 'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ';
const _plain = 'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC';

String normalizeForSearch(String value) {
  var result = value.toLowerCase();
  for (var i = 0; i < _accented.length; i++) {
    result = result.replaceAll(_accented[i].toLowerCase(), _plain[i].toLowerCase());
  }
  return result;
}

/// Só os dígitos de um telefone (ex.: "(48) 99999-0000" -> "48999990000")
/// — mesma normalização de `AuthController._normalizePhone` (usada em
/// `phoneIndex` pra achar cliente já cadastrado pelo telefone), extraída
/// aqui pra reaproveitar também em `ProviderDirectoryRepository`/
/// `functions/src/subscription.ts` (ver `phoneNormalized` em
/// providerDirectory) sem duplicar a regex em três lugares nem arriscar
/// os dois lados divergirem.
String normalizePhoneDigits(String phone) => phone.replaceAll(RegExp(r'[^0-9]'), '');
