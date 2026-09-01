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

  /// Nota honesta: a ordenação é feita aqui no app, não no Firestore. Um
  /// `orderBy` combinado com qualquer um dos filtros de igualdade abaixo
  /// (categoria e/ou cidade) exigiria um índice composto diferente pra
  /// cada combinação possível — pra uma lista do tamanho esperado aqui
  /// (prestadores de uma região), ordenar no app depois de buscar é mais
  /// simples e não depende de deploy de índice nenhum.
  ///
  /// Ordem: por nome. A classificação por estrelas (ratingAverage) é
  /// mostrada em cada card, mas não decide a ordem da lista — só o nome
  /// (ver ProviderListingCard/StarRatingBar).
  Future<List<ProviderListing>> search({ServiceCategory? category, String? city}) async {
    try {
      Query<Map<String, dynamic>> query = _collection;
      if (category != null) {
        query = query.where('category', isEqualTo: category.wireValue);
      }
      // Nota honesta: o filtro de cidade NÃO usa mais `where('city',
      // isEqualTo: ...)` do Firestore — isso é comparação exata de
      // string, sensível a acento/maiúscula, e cadastros antigos (feitos
      // antes do seletor fechado de Estado/Cidade existir — ver
      // BrazilLocations) podem ter gravado a mesma cidade com grafias
      // diferentes (ex.: "Criciuma" sem acento). Filtrar aqui no Dart com
      // `normalizeForSearch` casa essas variações; o preço é baixar todos
      // os prestadores da categoria (ou todos, sem categoria) em vez de só
      // os da cidade — aceitável pro tamanho de diretório esperado aqui,
      // mesma filosofia já usada na ordenação/filtro de `visible` abaixo.
      final normalizedCity = (city != null && city.isNotEmpty) ? normalizeForSearch(city) : null;
      final snapshot = await query.get();
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
          .where((doc) => doc.data()['visible'] != false)
          .where((doc) => doc.id != ownUid)
          .map(ProviderListing.fromFirestore)
          .where((listing) =>
              normalizedCity == null || normalizeForSearch(listing.city) == normalizedCity)
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
  /// Nota honesta: isso lê TODOS os documentos de providerDirectory pra
  /// tirar os valores únicos de `city`, porque o Firestore não tem uma
  /// consulta nativa de "valores distintos". Pro tamanho de diretório
  /// esperado aqui (prestadores de algumas regiões) isso é barato; se um
  /// dia isso crescer muito, vira uma coleção separada (`cities`) mantida
  /// por Cloud Function a cada escrita em providerDirectory.
  Future<List<String>> listCities() async {
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
    required ServiceCategory category,
    required String city,
    String? state,
    String? bio,
    String? whatsapp,
  }) async {
    try {
      final uid = _auth.currentUser!.uid;
      final ref = _collection.doc(uid);
      final existing = await ref.get();
      final now = FieldValue.serverTimestamp();
      await ref.set({
        'name': name,
        'category': category.wireValue,
        'city': city,
        if (state != null && state.isNotEmpty) 'state': state,
        'bio': (bio != null && bio.trim().isNotEmpty) ? bio.trim() : FieldValue.delete(),
        'whatsapp':
            (whatsapp != null && whatsapp.trim().isNotEmpty) ? whatsapp.trim() : FieldValue.delete(),
        'claimed': true,
        'providerUid': uid,
        'updatedAt': now,
        if (!existing.exists) 'createdAt': now,
      }, SetOptions(merge: true));
    } on FirebaseException catch (e) {
      throw ApiException(0, e.message ?? 'Não foi possível salvar o perfil público.');
    }
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
  Future<void> rate(String listingId, {required int stars, String? comment}) async {
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
