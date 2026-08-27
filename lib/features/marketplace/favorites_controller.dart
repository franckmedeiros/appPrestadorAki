import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'favorites_repository.dart';

/// Estado compartilhado dos favoritos do cliente logado.
///
/// Existe pra resolver um bug relatado pelo Franck: favoritar num card da
/// busca ("Encontre um profissional") não aparecia em "Meus favoritos" (e
/// o contrário também não) sem sair e entrar de novo na aba. Antes, cada
/// tela (ClientHomeScreen, MyFavoritesScreen, ProviderPublicProfileScreen)
/// guardava seu próprio estado local de favoritos, carregado só uma vez no
/// `initState` — como o go_router mantém cada aba viva num `IndexedStack`
/// (StatefulShellRoute), trocar de aba nunca reconstrói esse estado, então
/// uma mudança feita numa tela nunca aparecia nas outras até um
/// pull-to-refresh manual. Centralizar aqui, num `ChangeNotifier` único
/// observado pelas três telas, resolve isso: qualquer
/// favoritar/desfavoritar (de qualquer uma delas) atualiza esse estado uma
/// única vez e notifica todo mundo que está observando, na hora.
class FavoritesController extends ChangeNotifier {
  FavoritesController(this._repository);

  final FavoritesRepository _repository;

  Set<String> _ids = {};
  Set<String> get ids => _ids;

  // Incrementado a cada mudança real (carregar pela primeira vez,
  // favoritar, desfavoritar) — outras telas guardam o valor visto da
  // última vez que recarregaram e comparam com este pra saber que
  // precisam recarregar (ver MyFavoritesScreen), sem precisar comparar
  // Sets inteiros.
  int version = 0;

  bool _loading = false;
  String? _loadedForUid;

  bool isFavorite(String listingId) => _ids.contains(listingId);

  /// Carrega os ids de favoritos uma vez por conta logada — recarrega
  /// sozinho se o uid autenticado mudou desde a última vez (cobre
  /// logout/login com outra conta, que antes deixava favoritos "grudados"
  /// da conta anterior) e limpa tudo se ninguém está logado.
  Future<void> ensureLoaded() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (_ids.isNotEmpty || _loadedForUid != null) {
        _ids = {};
        _loadedForUid = null;
        version++;
        notifyListeners();
      }
      return;
    }
    if (_loadedForUid == uid || _loading) return;
    _loading = true;
    try {
      _ids = await _repository.listFavoriteIds();
      _loadedForUid = uid;
      version++;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Força recarregar do zero — usado quando um convidado escolhe "Já
  /// tenho conta" no meio de um toque de favoritar (a conta pode já ter
  /// favoritos salvos de antes, que `_ids` (vazio até então) ainda não
  /// conhece).
  Future<void> refresh() async {
    _loadedForUid = null;
    await ensureLoaded();
  }

  Future<void> add(String listingId) async {
    await _repository.add(listingId);
    _ids = {..._ids, listingId};
    version++;
    notifyListeners();
  }

  Future<void> remove(String listingId) async {
    await _repository.remove(listingId);
    _ids = {..._ids}..remove(listingId);
    version++;
    notifyListeners();
  }

  Future<void> toggle(String listingId) {
    return isFavorite(listingId) ? remove(listingId) : add(listingId);
  }
}
