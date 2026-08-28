import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// Um estado brasileiro (UF + nome por extenso) — ver
/// assets/data/br_locations.json.
class BrazilState {
  const BrazilState({required this.uf, required this.name});

  final String uf;
  final String name;
}

/// Carrega e expõe a lista fechada de estados e cidades do Brasil (nomes
/// oficiais, com acentuação correta — gerados a partir da mesma base do
/// IBGE) pros seletores de Estado/Cidade em "Editar perfil"/"Virar
/// prestador" (ver `widgets/state_city_fields.dart`).
///
/// Por que isso existe (decisão combinada com o Franck): antes, cidade e
/// UF eram campos de texto livre — dava pra digitar "Criciuma" sem
/// acento, e o cliente buscando "Criciúma" (com acento, como aparece pra
/// quem digitou certo) nunca encontrava esse prestador, porque a busca no
/// Firestore é por igualdade exata de string. Forçar a escolha nessas
/// duas listas fechadas elimina o problema na raiz pra cadastros novos ou
/// editados a partir de agora — cadastros antigos com grafia errada
/// continuam existindo até o próprio prestador reabrir "Editar perfil" e
/// escolher a cidade certa uma vez (ver também o filtro tolerante a
/// acento em `ProviderDirectoryRepository.search`, que cobre esses casos
/// antigos na busca sem exigir essa correção manual).
///
/// Carregado uma única vez (cache em memória, estático) — o arquivo tem
/// ~85KB, não compensa reler do asset toda vez que uma tela abre.
class BrazilLocations {
  BrazilLocations._();

  static List<BrazilState>? _states;
  static Map<String, List<String>>? _citiesByState;
  static Future<void>? _loading;

  static Future<void> _ensureLoaded() {
    if (_states != null && _citiesByState != null) return Future.value();
    return _loading ??= () async {
      final raw = await rootBundle.loadString('assets/data/br_locations.json');
      final data = jsonDecode(raw) as Map<String, dynamic>;
      _states = (data['states'] as List)
          .map((e) => BrazilState(
                uf: (e as Map<String, dynamic>)['uf'] as String,
                name: e['name'] as String,
              ))
          .toList();
      _citiesByState = (data['citiesByState'] as Map<String, dynamic>).map(
        (uf, cities) => MapEntry(uf, (cities as List).cast<String>()),
      );
    }();
  }

  /// Os 27 estados, já ordenados por nome (ver geração do asset).
  static Future<List<BrazilState>> states() async {
    await _ensureLoaded();
    return _states!;
  }

  /// Cidades do estado (sigla, ex.: 'SC') — lista vazia se o UF não
  /// existir na base (não deveria acontecer, vindo do próprio seletor de
  /// estado).
  static Future<List<String>> citiesOf(String uf) async {
    await _ensureLoaded();
    return _citiesByState![uf] ?? const [];
  }
}
