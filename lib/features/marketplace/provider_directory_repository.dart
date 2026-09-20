import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/api_exception.dart';
import '../../core/text_normalize.dart';
import 'models/provider_listing.dart';
import 'models/provider_rating.dart';
import 'models/service_category.dart';

/// Diretório público de prestadores (`providerDirectory`, fora de
/// `/providers` — ver firebase/DATA_MODEL.md). Alimenta a busca do lado do
/// cliente. Uma entrada "reivindicada" (`claimed: true`) tem o mesmo id do
/// documento que o `providerUid` do prestador (ver
/// `AuthController.register`); entradas "não reivindicadas" (carga
/// inicial/curadoria manual) têm id gerado e nenhum `providerUid`.
///
/// Notas honestas sobre o que isso NÃO faz ainda: a busca por
/// cidade/categoria usa filtros exatos (equality), não geolocalização de
/// verdade — "prestadores próximos" do documento de produto original
/// precisaria de geohash + Cloud Function ou um serviço de busca externo,
/// isso ainda não existe.
///
/// `visible` (bool, opcional): controlado só pelas Cloud Functions da
/// assinatura (ver functions/src/subscription.ts) — `false` enquanto a
/// assinatura mensal do prestador não estiver ativa. Um documento SEM
/// esse campo é tratado como visível (protege as entradas "não
/// reivindicadas" da curadoria inicial, que nunca têm esse campo, e
/// qualquer entrada reivindicada de antes dessa mudança).
class ProviderDirectoryRepository {
  ProviderDirectoryRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('providerDirectory');

  /// Quantos documentos, no máximo, uma busca traz do Firestore.
  ///
  /// Existe porque o diretório deixou de ser pequeno: passou de algumas
  /// dezenas pra quase 10 mil entradas (carga de curadoria — ver
  /// scripts/README.md). Sem teto, abrir a aba de busca baixava a coleção
  /// INTEIRA no celular do cliente, toda vez. Com filtro de cidade ou
  /// nome, o teto quase nunca é alcançado; sem filtro nenhum, ele é o que
  /// impede a tela de puxar o país inteiro.
  static const _limiteDaBusca = 60;

  /// Busca prestadores. Tudo que dá pra filtrar no SERVIDOR é filtrado lá
  /// — só `visible` e a ordenação ficam no app.
  ///
  /// Isto já foi o contrário: cidade e nome eram filtrados no Dart, sobre
  /// a coleção inteira baixada, porque era mais simples e o diretório era
  /// pequeno. Com ~9.700 entradas isso virou ~10 mil leituras por busca,
  /// megabytes no 4G do cliente e uma conta de Firestore que cresce
  /// sozinha. Os campos `cityNormalized` e `nameNormalized` (gravados sem
  /// acento e em minúsculas — ver `upsertOwnListing` e a função
  /// `onListagemEscrita`) são o que permite comparar no servidor sem
  /// exigir digitação idêntica.
  ///
  /// Cada ramo abaixo usa UM filtro de servidor por vez, de propósito:
  /// combinar dois exigiria um índice composto diferente pra cada
  /// combinação. O filtro que sobra é aplicado no app, sobre um conjunto
  /// já pequeno.
  ///
  /// Ordem: por nome, feita no app. A nota (ratingAverage) aparece em
  /// cada card mas não decide a ordem (ver ProviderListingCard).
  Future<List<ProviderListing>> search({
    ServiceCategory? category,
    String? city,
    String? nome,
  }) async {
    try {
      final termoNome = (nome ?? '').trim();
      final normalizedCity = (city != null && city.isNotEmpty) ? normalizeForSearch(city) : null;

      // `visible` filtrado no SERVIDOR, e não mais no app.
      //
      // Antes ficava no app com a justificativa de que "documento sem o
      // campo não casa com `== true` de qualquer jeito". Isso era verdade
      // e deixou de bastar no dia em que a busca ganhou teto de 60
      // documentos: filtrar depois do limite significa pedir 60 e
      // descartar os escondidos, podendo sobrar zero. Com ~9.700 entradas
      // de curadoria ocultadas, TODA busca sem filtro voltaria vazia.
      //
      // Para isso funcionar, todo documento precisa ter o campo. Quem
      // garante são a função `onListagemEscrita` (preenche `true` quando
      // falta, sem nunca sobrescrever um `false` deliberado) e o
      // backfill_diretorio.js, pro acervo que já existe.
      Query<Map<String, dynamic>> query = _collection.where('visible', isEqualTo: true);
      var filtrarCategoriaNoApp = false;
      var filtrarCidadeNoApp = false;

      if (termoNome.isNotEmpty) {
        // Busca por nome: prefixo no servidor. O truque do `` (o
        // último caractere utilizável do plano básico do Unicode) fecha o
        // intervalo "tudo que começa com o termo".
        //
        // MUDANÇA DE COMPORTAMENTO, assumida: antes o nome era comparado
        // com `contains` sobre a coleção inteira, então "sourcing" achava
        // "OPOutsourcingBr". Agora é começa-com, então é preciso digitar
        // do início. É o preço de não baixar 9.700 documentos a cada
        // letra; um `contains` de verdade no servidor exigiria um índice
        // invertido, que o Firestore não tem.
        final termo = normalizeForSearch(termoNome);
        query = query
            .where('nameNormalized', isGreaterThanOrEqualTo: termo)
            .where('nameNormalized', isLessThanOrEqualTo: '$termo');
        filtrarCategoriaNoApp = category != null;
        filtrarCidadeNoApp = normalizedCity != null;
      } else if (normalizedCity != null) {
        // Casa quem tem a cidade como PRINCIPAL e quem a tem na área de
        // atendimento (pedido do Franck: atender Criciúma e Florianópolis
        // sem precisar de duas contas).
        //
        // Mesmo `Filter.or` usado nas categorias, e pelo mesmo motivo:
        // `cidadesNormalizadas` só existe em quem salvou o perfil depois
        // desta mudança. As ~9.700 entradas de curadoria e os cadastros
        // antigos continuam sendo achados pelo `cityNormalized` de sempre,
        // sem migração nenhuma.
        query = query.where(
          Filter.or(
            Filter('cidadesNormalizadas', arrayContains: normalizedCity),
            Filter('cityNormalized', isEqualTo: normalizedCity),
          ),
        );
        filtrarCategoriaNoApp = category != null;
      } else if (category != null) {
        // `Filter.or` casa tanto quem já tem o campo novo `categories`
        // (lista, ver ProviderListing/upsertOwnListing — pedido do
        // Franck: prestador em 2+ categorias precisa aparecer na busca
        // de QUALQUER uma delas) quanto quem ainda só tem o `category`
        // singular antigo (documento de antes dessa mudança, que só
        // recebe `categories` no próximo salvamento do perfil).
        query = query.where(
          Filter.or(
            Filter('categories', arrayContains: category.wireValue),
            Filter('category', isEqualTo: category.wireValue),
          ),
        );
      }

      // Sem filtro nenhum, o teto de 60 precisa de uma ORDEM — senão o
      // Firestore devolve os 60 primeiros por id do documento, que na
      // prática são sempre os mesmos (os ids da carga de curadoria
      // começam com número: `048-...`, `2-irmaos-...`). Foi assim que um
      // prestador de verdade sumiu da lista e só aparecia quando o Franck
      // digitava o nome dele.
      if (termoNome.isEmpty && normalizedCity == null && category == null) {
        query = query.orderBy('nameNormalized');
      }

      final snapshot = await query.limit(_limiteDaBusca).get();
      // Um prestador logado também pode abrir "Encontre um profissional"
      // pelo lado cliente (a mesma conta pode ter as duas capacidades) —
      // nesse caso ele nunca deve aparecer na própria busca. `ownUid` vem
      // null pra visitante sem sessão, então não filtra nada nesse caso.
      final ownUid = _auth.currentUser?.uid;
      // Filtro de `visible` feito aqui no app, não no Firestore, pela
      // mesma razão da ordenação abaixo: um `where('visible', ...)`
      // combinado com os filtros de igualdade acima pediria mais um
      // índice composto, e documentos sem o campo (a maioria, hoje) não
      // combinam com `isEqualTo: true` de qualquer jeito.
      final listings = snapshot.docs
          // `visible` saiu daqui — agora é filtro de servidor (ver acima).
          .where((doc) => doc.id != ownUid)
          .map(ProviderListing.fromFirestore)
          // Os dois filtros abaixo só entram em ação quando o ramo lá em
          // cima já gastou o filtro de servidor com outra coisa (ver
          // `filtrarCidadeNoApp`/`filtrarCategoriaNoApp`) — aí eles agem
          // sobre no máximo `_limiteDaBusca` documentos, não sobre a
          // coleção inteira como antes.
          .where((listing) =>
              !filtrarCidadeNoApp || normalizeForSearch(listing.city) == normalizedCity)
          // Olha a LISTA de categorias, não só a singular: quem atua em
          // mais de uma precisa aparecer na busca de qualquer uma delas
          // (pedido do Franck). `categories` já cai na singular quando a
          // entrada é antiga e não tem a lista — ver
          // ProviderListing.fromFirestore.
          .where((listing) =>
              !filtrarCategoriaNoApp ||
              listing.categories.contains(category) ||
              listing.category == category)
          .toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return listings;
    } on FirebaseException catch (e) {
      throw ApiException(0, e.message ?? 'Não foi possível buscar prestadores.');
    }
  }

  /// Lista as cidades que já têm pelo menos um prestador cadastrado, pra
  /// preencher o campo de busca (ver ClientHomeScreen — autocomplete
  /// estilo iFood, filtra conforme digita).
  ///
  /// Lê de `meta/cidades`, UM documento com a lista pronta — mantido pela
  /// Cloud Function `onListagemEscrita` a cada escrita no diretório.
  ///
  /// Antes isto varria a coleção inteira pra extrair os valores únicos de
  /// `city` (o Firestore não tem "distinct"), com a justificativa de que
  /// o diretório era pequeno. Aquele "se um dia isso crescer muito"
  /// chegou: com ~9.700 entradas, abrir a tela de busca custava ~9.700
  /// leituras só pra montar o autocomplete de cidades — mais que a busca
  /// em si. Agora custa UMA.
  ///
  /// Se o documento não existir (ainda não foi gerado — ver
  /// scripts/backfill_diretorio.js), cai no método antigo em vez de
  /// deixar a tela sem cidade nenhuma.
  Future<List<String>> listCities() async {
    // try/catch PRÓPRIO, e não um `try` só em volta dos dois caminhos: a
    // primeira versão disto tratava apenas o documento AUSENTE como
    // motivo pra cair no método antigo, e deixava qualquer erro de
    // leitura subir. Deu no que tinha que dar — as regras do `meta/`
    // ainda não estavam publicadas, a leitura foi NEGADA, a exceção subiu
    // e o campo de cidade virou um botão morto: tocava e não acontecia
    // nada, porque quem chama faz `await` dessa Future antes de abrir o
    // seletor (ver ClientHomeScreen._openCityPicker).
    //
    // Agora qualquer falha aqui — negada, offline, documento ausente —
    // cai no caminho antigo, que é lento mas sempre funciona.
    try {
      final resumo = await _firestore.collection('meta').doc('cidades').get();
      final lista = (resumo.data()?['cidades'] as List<dynamic>?)?.cast<String>();
      if (lista != null && lista.isNotEmpty) {
        return lista.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      }
    } catch (_) {
      // Silencioso de propósito: não é erro do usuário, é um atalho de
      // desempenho que não estava disponível.
    }
    return _listCitiesVarrendoTudo();
  }

  /// O jeito antigo, caro — só como rede de segurança enquanto
  /// `meta/cidades` não existir.
  Future<List<String>> _listCitiesVarrendoTudo() async {
    try {
      final snapshot = await _collection.get();
      // Dedupe por grafia NORMALIZADA (sem acento/maiúscula), não pela
      // string crua — sem isso, "Criciuma" e "Criciúma" apareceriam como
      // duas cidades diferentes nessa lista (mesmo bug de fundo do
      // `search` acima). Guarda a primeira grafia vista de cada cidade
      // como rótulo de exibição — não tenta adivinhar qual delas está
      // "certa".
      final seen = <String, String>{};
      for (final doc in snapshot.docs) {
        if (doc.data()['visible'] == false) continue;
        final city = doc.data()['city'] as String?;
        if (city == null || city.isEmpty) continue;
        seen.putIfAbsent(normalizeForSearch(city), () => city);
      }
      final cities = seen.values.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      return cities;
    } on FirebaseException catch (e) {
      throw ApiException(0, e.message ?? 'Não foi possível carregar as cidades.');
    }
  }

  Future<ProviderListing?> get(String id) async {
    final doc = await _collection.doc(id).get();
    if (!doc.exists) return null;
    return ProviderListing.fromFirestore(doc);
  }

  /// Cria ou atualiza o próprio perfil público do prestador logado — o id
  /// do documento é sempre o próprio uid (ver classe acima), então isso
  /// nunca cria uma segunda entrada por engano, mesmo chamado mais de uma
  /// vez. Usado no cadastro e na tela "Editar perfil" (EditProfileScreen).
  Future<void> upsertOwnListing({
    required String name,
    required List<ServiceCategory> categories,
    required String city,
    String? state,
    String? bio,
    String? whatsapp,
    List<String> cidadesAtendidas = const [],
    String? logoUrl,
    List<String> fotos = const [],
  }) async {
    assert(categories.isNotEmpty, 'upsertOwnListing precisa de ao menos uma categoria');
    try {
      final uid = _auth.currentUser!.uid;
      final ref = _collection.doc(uid);
      final existing = await ref.get();
      final now = FieldValue.serverTimestamp();
      await ref.set({
        'name': name,
        'categories': categories.map((c) => c.wireValue).toList(),
        // `category` (singular) continua gravado com a primeira escolhida
        // — mantém compatibilidade com qualquer leitura antiga que ainda
        // espere só esse campo (ex.: uma versão anterior do app instalada
        // em algum aparelho que ainda não atualizou).
        'category': categories.first.wireValue,
        'city': city,
        if (state != null && state.isNotEmpty) 'state': state,
        'bio': (bio != null && bio.trim().isNotEmpty) ? bio.trim() : FieldValue.delete(),
        'whatsapp':
            (whatsapp != null && whatsapp.trim().isNotEmpty) ? whatsapp.trim() : FieldValue.delete(),
        // Dígitos só do telefone — pedido do Franck: quando o prestador se
        // cadastra de verdade (ou edita o WhatsApp depois), o sistema
        // precisa achar/"reivindicar" pelo TELEFONE uma entrada "não
        // reivindicada" da carga inicial (ver
        // functions/src/subscription.ts, reivindicarListagemPorTelefone).
        // Gravado aqui também (não só na criação via assinatura) pra nunca
        // ficar desatualizado se a pessoa trocar de WhatsApp depois.
        'phoneNormalized': (whatsapp != null && whatsapp.trim().isNotEmpty)
            ? normalizePhoneDigits(whatsapp.trim())
            : FieldValue.delete(),
        // Cópias sem acento e em minúsculas de `name` e `city`, pra busca
        // poder comparar no SERVIDOR (ver `search` acima). Sem elas, o
        // Firestore só faria comparação exata, sensível a acento — e foi
        // justamente pra fugir disso que a busca filtrava tudo no app,
        // baixando a coleção inteira. A Cloud Function `onListagemEscrita`
        // também preenche esses campos, pra pegar entradas que não passam
        // por aqui (carga de curadoria, edição pelo Console).
        'nameNormalized': normalizeForSearch(name),
        'cityNormalized': normalizeForSearch(city),
        // Área de atendimento (pedido do Franck: "hoje ele pode atender
        // Criciúma e Florianópolis"). Duas listas com papéis diferentes:
        // `cidadesAtendidas` guarda "Cidade/UF" pra mostrar na tela, e
        // `cidadesNormalizadas` guarda só o nome sem acento, que é o que a
        // busca compara no servidor (ver `search`).
        //
        // A cidade principal entra nas DUAS. Sem isso, um prestador que
        // preenchesse a área de atendimento deixaria de ser achado na
        // própria cidade, porque a busca passaria a casar pela lista.
        'cidadesAtendidas': _comCidadePrincipal(cidadesAtendidas, city, state),
        'cidadesNormalizadas': _comCidadePrincipal(cidadesAtendidas, city, state)
            .map((c) => normalizeForSearch(c.split('/').first.trim()))
            .toSet()
            .toList(),
        // Foto do prestador e fotos de trabalhos feitos. A logo já existia
        // em `providers/{uid}.logoUrl`, mas nunca era copiada pra cá — o
        // prestador subia a foto e o cliente continuava vendo um ícone
        // genérico. `FieldValue.delete()` quando vazio pra uma foto
        // removida sumir de fato, em vez de virar string vazia.
        'logoUrl': (logoUrl != null && logoUrl.trim().isNotEmpty)
            ? logoUrl.trim()
            : FieldValue.delete(),
        'fotos': fotos.where((f) => f.trim().isNotEmpty).toList(),
        'claimed': true,
        'providerUid': uid,
        'updatedAt': now,
        if (!existing.exists) 'createdAt': now,
      }, SetOptions(merge: true));
    } on FirebaseException catch (e) {
      throw ApiException(0, e.message ?? 'Não foi possível salvar o perfil público.');
    }
  }

  /// Junta a cidade principal com as adicionais, sem repetir e sem
  /// vazios. Separado num helper porque o valor é usado duas vezes (lista
  /// de exibição e lista normalizada) e as duas PRECISAM conter os mesmos
  /// municípios — se divergirem, o prestador aparece escrito numa cidade
  /// e é encontrado em outra.
  static List<String> _comCidadePrincipal(
    List<String> adicionais,
    String city,
    String? state,
  ) {
    final uf = (state ?? '').trim().toUpperCase();
    final principal = city.trim().isEmpty
        ? null
        : (uf.isEmpty ? city.trim() : '${city.trim()}/$uf');
    return <String>{
      if (principal != null) principal,
      ...adicionais.where((c) => c.trim().isNotEmpty),
    }.toList();
  }

  /// A avaliação que o cliente logado já deu pra esse prestador, se
  /// houver — usada pra pré-preencher o formulário como edição em vez de
  /// deixar a pessoa achar que está criando uma segunda avaliação.
  Future<ProviderRating?> getMyRating(String listingId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return null;
    final doc = await _collection.doc(listingId).collection('ratings').doc(uid).get();
    if (!doc.exists) return null;
    return ProviderRating.fromFirestore(doc);
  }

  /// Ao vivo, mais recente primeiro — TODAS as avaliações (com
  /// comentário ou não) de um prestador, pra mostrar de verdade no perfil
  /// público (pedido do Franck: hoje o cliente escreve um comentário e
  /// ele nunca aparece pra ninguém, nem pro próprio prestador). Leitura
  /// pública, mesma regra de `allow read: if true` já usada por
  /// `getMyRating` — ver firestore.rules, bloco `ratings`.
  Stream<List<ProviderRating>> watchRatings(String listingId, {int limit = 30}) {
    return _collection
        .doc(listingId)
        .collection('ratings')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(ProviderRating.fromFirestore).toList());
  }

  /// Avalia (ou edita a própria avaliação de) um prestador — 1 a 5
  /// estrelas, comentário opcional. Recalcula `ratingAverage`/
  /// `ratingCount` no próprio documento do diretório dentro de uma
  /// transação, pra nunca ficar com a média fora de sincronia mesmo se
  /// dois clientes avaliarem ao mesmo tempo.
  ///
  /// Nota honesta: a checagem de "só quem teve um orçamento aceito com
  /// esse prestador pode avaliar" é feita na tela (ver
  /// BudgetRequestsRepository.hasAcceptedBudgetWith), não aqui nem no
  /// firestore.rules — um cliente que forçar a chamada direto ainda
  /// conseguiria avaliar sem nunca ter contratado. Fechar essa brecha de
  /// verdade exigiria uma Cloud Function (o projeto já teve percalço pra
  /// manter as Functions publicadas — ver README) ou uma regra bem mais
  /// elaborada lendo os orçamentos via `collectionGroup` a partir do
  /// firestore.rules; fica como próximo passo se abuso aparecer na
  /// prática.
  Future<void> rate(
    String listingId, {
    required int stars,
    String? comment,
    String? clientName,
  }) async {
    if (stars < 1 || stars > 5) {
      throw ApiException(0, 'A nota precisa ser de 1 a 5 estrelas.');
    }
    final uid = _auth.currentUser!.uid;
    final listingRef = _collection.doc(listingId);
    final ratingRef = listingRef.collection('ratings').doc(uid);
    try {
      await _firestore.runTransaction((tx) async {
        final listingSnap = await tx.get(listingRef);
        final existingRatingSnap = await tx.get(ratingRef);

        final oldAverage = (listingSnap.data()?['ratingAverage'] as num?)?.toDouble() ?? 0;
        final oldCount = (listingSnap.data()?['ratingCount'] as num?)?.toInt() ?? 0;
        final hadRatingBefore = existingRatingSnap.exists;
        final oldStarsForThisClient =
            (existingRatingSnap.data()?['stars'] as num?)?.toInt() ?? 0;

        final newCount = hadRatingBefore ? oldCount : oldCount + 1;
        final oldSum = oldAverage * oldCount;
        final newSum = hadRatingBefore ? (oldSum - oldStarsForThisClient + stars) : (oldSum + stars);
        final newAverage = newCount == 0 ? 0.0 : newSum / newCount;

        // Extraído numa variável à parte (em vez de embutido direto no
        // valor do map literal abaixo) por causa de um caso real de
        // ambiguidade de parsing do Dart: um `?:` cujo ramo "then" é uma
        // expressão `??` terminando em chamada de função, seguido do `:`
        // numa linha nova, confundiu o compilador (erro "Expected ':'
        // before this" que só apareceu na build do Codemagic — não tinha
        // como pegar isso sem rodar `flutter build` de verdade).
        final Object createdAt = hadRatingBefore
            ? (existingRatingSnap.data()?['createdAt'] ?? FieldValue.serverTimestamp())
            : FieldValue.serverTimestamp();

        tx.set(ratingRef, {
          'stars': stars,
          if (comment != null && comment.trim().isNotEmpty) 'comment': comment.trim(),
          if (clientName != null && clientName.trim().isNotEmpty) 'clientName': clientName.trim(),
          'createdAt': createdAt,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        tx.update(listingRef, {
          'ratingAverage': double.parse(newAverage.toStringAsFixed(2)),
          'ratingCount': newCount,
        });
      });
    } on FirebaseException catch (e) {
      throw ApiException(0, e.message ?? 'Não foi possível registrar sua avaliação.');
    }
  }
}
