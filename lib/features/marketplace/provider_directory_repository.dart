import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/api_exception.dart';
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
  /// Ordem: primeiro os "Destaque" com assinatura em dia (`isFeatured`),
  /// depois todo mundo por nome — dentro de cada grupo. Isso é o único
  /// efeito que o plano pago tem na busca por enquanto (ver
  /// ProviderListing.isFeatured e scripts/set_provider_plan.js).
  Future<List<ProviderListing>> search({ServiceCategory? category, String? city}) async {
    try {
      Query<Map<String, dynamic>> query = _collection;
      if (category != null) {
        query = query.where('category', isEqualTo: category.wireValue);
      }
      if (city != null && city.isNotEmpty) {
        query = query.where('city', isEqualTo: city);
      }
      final snapshot = await query.get();
      final listings = snapshot.docs.map(ProviderListing.fromFirestore).toList()
        ..sort((a, b) {
          if (a.isFeatured != b.isFeatured) return a.isFeatured ? -1 : 1;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
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
      final cities = snapshot.docs
          .map((doc) => doc.data()['city'] as String?)
          .whereType<String>()
          .where((city) => city.isNotEmpty)
          .toSet()
          .toList()
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
  /// vez. Deliberadamente nunca escreve `featured`/`featuredUntil` — quem
  /// controla o selo de Destaque é só o script administrativo (ver
  /// firestore.rules, que bloqueia o próprio prestador de mudar esses dois
  /// campos no seu perfil).
  Future<void> upsertOwnListing({
    required String name,
    required ServiceCategory category,
    required String city,
    String? state,
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
  /// Nota honesta: a checagem de "só quem teve um pedido aceito com esse
  /// prestador pode avaliar" é feita na tela (ver
  /// ServiceRequestsRepository.hasAcceptedRequestWith), não aqui nem no
  /// firestore.rules — um cliente que forçar a chamada direto ainda
  /// conseguiria avaliar sem nunca ter contratado. Fechar essa brecha de
  /// verdade exigiria uma Cloud Function (o projeto já teve percalço pra
  /// manter as Functions publicadas — ver README) ou uma regra bem mais
  /// elaborada lendo `serviceRequests` a partir do firestore.rules; fica
  /// como próximo passo se abuso aparecer na prática.
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
