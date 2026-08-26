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

  // Resultado "pré-aquecido" — disparado assim que o app confirma a
  // identidade do cliente (desbloqueio biométrico, ver
  // BiometricUnlockScreen), pra a aba Favoritos abrir com os dados já
  // prontos em vez de mostrar um spinner. Consumido uma única vez: depois
  // que a tela lê esse valor, a próxima chamada de listResolved() busca
  // de novo do Firestore normalmente (puxar pra baixo, reabrir a aba etc.
  // continuam sempre atualizados).
  Future<List<ProviderListing>>? _warmCache;

  CollectionReference<Map<String, dynamic>> get _favorites =>
      _firestore.collection('clients').doc(_auth.currentUser!.uid).collection('favorites');

  /// Dispara a leitura dos favoritos em segundo plano — chamado assim que
  /// o app sabe que o usuário logado é um cliente com sessão confirmada
  /// (login normal ou desbloqueio biométrico), sem bloquear a navegação
  /// esperando o resultado.
  void warmUp() {
    _warmCache ??= listResolved();
  }

  Future<bool> isFavorite(String listingId) async {
    final doc = await _favorites.doc(listingId).get();
    return doc.exists;
  }

  Future<void> add(String listingId) async {
    try {
      await _favorites.doc(listingId).set({'addedAt': FieldValue.serverTimestamp()});
    } on FirebaseException catch (e) {
      throw ApiException(0, e.message ?? 'Não foi possível favoritar.');
    } finally {
      _warmCache = null;
    }
  }

  Future<void> remove(String listingId) async {
    try {
      await _favorites.doc(listingId).delete();
    } on FirebaseException catch (e) {
      throw ApiException(0, e.message ?? 'Não foi possível remover dos favoritos.');
    } finally {
      _warmCache = null;
    }
  }

  /// Retorna os perfis favoritados já resolvidos (não só os ids) — faz uma
  /// leitura extra por favorito; para a quantidade esperada (favoritos de
  /// uma pessoa) isso é barato o bastante pra não precisar de nenhuma
  /// otimização especial agora. Se `warmUp()` já tiver disparado uma
  /// leitura recente, reaproveita o resultado em vez de buscar de novo.
  Future<List<ProviderListing>> listResolved() {
    final warm = _warmCache;
    if (warm != null) {
      _warmCache = null;
      return warm;
    }
    return _fetch();
  }

  Future<List<ProviderListing>> _fetch() async {
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
