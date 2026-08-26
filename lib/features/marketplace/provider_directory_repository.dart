import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/api_exception.dart';
import 'models/provider_listing.dart';
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
/// isso ainda não existe. Também não há cálculo de nota média
/// (`ratingAverage` fica de fora por enquanto).
class ProviderDirectoryRepository {
  ProviderDirectoryRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('providerDirectory');

  /// Nota honesta: a ordenação por nome é feita aqui no app, não no
  /// Firestore. Um `orderBy('name')` combinado com qualquer um dos
  /// filtros de igualdade abaixo (categoria e/ou cidade) exigiria um
  /// índice composto diferente pra cada combinação possível (só
  /// categoria, só cidade, os dois juntos) — pra uma lista do tamanho
  /// esperado aqui (prestadores de uma região), ordenar no app depois de
  /// buscar é mais simples e não depende de deploy de índice nenhum.
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
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return listings;
    } on FirebaseException catch (e) {
      throw ApiException(0, e.message ?? 'Não foi possível buscar prestadores.');
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
  /// vez.
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
}
