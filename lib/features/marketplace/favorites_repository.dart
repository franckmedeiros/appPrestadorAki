import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/api_exception.dart';
import 'models/provider_listing.dart';

/// Favoritos do cliente (`clients/{uid}/favorites/{listingId}`) — só um
/// ponteiro pro id do `providerDirectory`, sem duplicar os dados do
/// prestador (evita ficar desatualizado se ele mudar nome/cidade).
class FavoritesRepository {
  FavoritesRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> get _favorites =>
      _firestore.collection('clients').doc(_auth.currentUser!.uid).collection('favorites');

  Future<bool> isFavorite(String listingId) async {
    final doc = await _favorites.doc(listingId).get();
    return doc.exists;
  }

  Future<void> add(String listingId) async {
    try {
      await _favorites.doc(listingId).set({'addedAt': FieldValue.serverTimestamp()});
    } on FirebaseException catch (e) {
      throw ApiException(0, e.message ?? 'Não foi possível favoritar.');
    }
  }

  Future<void> remove(String listingId) async {
    try {
      await _favorites.doc(listingId).delete();
    } on FirebaseException catch (e) {
      throw ApiException(0, e.message ?? 'Não foi possível remover dos favoritos.');
    }
  }

  /// Retorna os perfis favoritados já resolvidos (não só os ids) — faz uma
  /// leitura extra por favorito; para a quantidade esperada (favoritos de
  /// uma pessoa) isso é barato o bastante pra não precisar de nenhuma
  /// otimização especial agora.
  Future<List<ProviderListing>> listResolved() async {
    try {
      final favSnapshot = await _favorites.orderBy('addedAt', descending: true).get();
      final listings = <ProviderListing>[];
      for (final favDoc in favSnapshot.docs) {
        final listingDoc = await _firestore.collection('providerDirectory').doc(favDoc.id).get();
        if (listingDoc.exists) {
          listings.add(ProviderListing.fromFirestore(listingDoc));
        }
      }
      return listings;
    } on FirebaseException catch (e) {
      throw ApiException(0, e.message ?? 'Não foi possível carregar seus favoritos.');
    }
  }
}
