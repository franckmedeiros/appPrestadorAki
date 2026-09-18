import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'moderation_repository.dart';

/// Estado compartilhado de "quem eu bloqueei".
///
/// Mesmo desenho do FavoritesController, e pelo mesmo motivo: as abas do
/// app ficam vivas num IndexedStack (StatefulShellRoute), então estado
/// carregado uma vez no `initState` de cada tela nunca se atualiza quando
/// outra tela muda alguma coisa. Bloquear alguém no perfil de um prestador
/// precisa esconder essa pessoa TAMBÉM na lista de avaliações que já está
/// montada em outra aba — daí um ChangeNotifier único.
///
/// Guarda uid -> nome. O nome é só pra tela de bloqueados conseguir
/// mostrar de quem se trata sem uma leitura por pessoa; quem filtra
/// conteúdo usa [bloqueou].
class BlockedUsersController extends ChangeNotifier {
  BlockedUsersController(this._repository);

  final ModerationRepository _repository;

  Map<String, String> _bloqueados = const {};
  Map<String, String> get bloqueados => _bloqueados;

  bool _carregando = false;
  String? _carregadoParaUid;

  bool bloqueou(String? uid) => uid != null && _bloqueados.containsKey(uid);

  /// Carrega uma vez por conta logada, e recarrega sozinho se o uid mudou
  /// (logout e login com outra conta) — senão a lista de bloqueados de
  /// quem saiu continuaria escondendo conteúdo pra quem entrou.
  Future<void> ensureLoaded() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (_bloqueados.isNotEmpty || _carregadoParaUid != null) {
        _bloqueados = const {};
        _carregadoParaUid = null;
        notifyListeners();
      }
      return;
    }
    if (_carregadoParaUid == uid || _carregando) return;
    _carregando = true;
    try {
      _bloqueados = await _repository.listarBloqueados();
      _carregadoParaUid = uid;
    } catch (e) {
      // Não bloquear a tela por causa disso: sem a lista, o pior que
      // acontece é o conteúdo de alguém bloqueado aparecer nesta sessão.
      debugPrint('BlockedUsersController.ensureLoaded falhou: $e');
    } finally {
      _carregando = false;
      notifyListeners();
    }
  }

  Future<void> bloquear(String uid, {String? nome}) async {
    await _repository.bloquear(uid, nome: nome);
    _bloqueados = {..._bloqueados, uid: (nome?.trim().isNotEmpty ?? false) ? nome!.trim() : 'Usuário'};
    notifyListeners();
  }

  Future<void> desbloquear(String uid) async {
    await _repository.desbloquear(uid);
    _bloqueados = {..._bloqueados}..remove(uid);
    notifyListeners();
  }
}
