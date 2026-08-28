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
