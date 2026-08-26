import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'biometric_service.dart';
import 'token_storage.dart';

enum AuthStatus { unknown, authenticated, unauthenticated, locked }

/// Os dois lados do marketplace (ver a mudança de escopo combinada com o
/// Franck): `client` procura e contrata prestadores; `provider` é o
/// prestador de serviço (o público original do app, antes do pivot).
/// Guardado só na memória, resolvido a partir de qual documento existe no
/// Firestore pra esse uid (`providers/{uid}` ou `clients/{uid}`) — não é
/// um campo próprio, pra não correr o risco de ficar dessincronizado.
enum AccountRole { client, provider }

/// Estado de autenticação do app, compartilhado via Provider a partir da
/// raiz (main.dart). Depois da migração para Firebase, quem sabe fazer
/// login/cadastro/logout de verdade é o próprio `FirebaseAuth` — esta
/// classe só traduz isso para o `AuthStatus`/`AccountRole` que o resto do
/// app entende, e continua guardando localmente a preferência de
/// biometria (que nunca foi uma credencial de API, sempre foi um cadeado
/// só do app).
///
/// `AuthStatus.locked` é um estado que só existe no app — nunca chega a
/// virar uma chamada ao Firebase. Significa "já existe uma sessão válida
/// do Firebase Auth, mas o usuário ativou o cadeado biométrico, então
/// precisa confirmar a identidade antes de ver qualquer tela".
class AuthController extends ChangeNotifier {
  AuthController({
    required TokenStorage biometricStorage,
    required BiometricService biometricService,
    FirebaseAuth? firebaseAuth,
    FirebaseFirestore? firestore,
  })  : _storage = biometricStorage,
        _biometric = biometricService,
        _auth = firebaseAuth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final TokenStorage _storage;
  final BiometricService _biometric;
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  AuthStatus status = AuthStatus.unknown;
  AccountRole? role;
  String? errorMessage;
  bool isBusy = false;
  bool biometricEnabled = false;

  Future<bool> get biometricAvailable => _biometric.isAvailable;

  /// UID do usuário logado — usado pelos repositórios do Firestore para
  /// montar caminhos como `providers/{uid}/...` ou `clients/{uid}/...`.
  /// Só deve ser lido quando `status == AuthStatus.authenticated`; isso é
  /// garantido pelo redirect do go_router.
  String get providerId => _auth.currentUser!.uid;

  /// Nome de exibição do usuário logado — usado, por exemplo, ao preencher
  /// automaticamente o nome do cliente num pedido de orçamento do
  /// marketplace.
  String get displayName {
    final user = _auth.currentUser;
    if (user?.displayName != null && user!.displayName!.isNotEmpty) return user.displayName!;
    return user?.email ?? 'Usuário';
  }

  /// Chamado uma vez na inicialização do app para restaurar a sessão. O
  /// Firebase Auth já persiste a sessão sozinho no dispositivo — só
  /// checamos se existe um usuário logado e, se existir, qual o papel dele
  /// (cliente ou prestador) e se o cadeado biométrico está ativado.
  Future<void> bootstrap() async {
    // Duração mínima da splash — sem isso, num aparelho rápido (ou contra o
    // emulador local, sem latência de rede nenhuma) o bootstrap pode
    // terminar tão rápido que a splash nem chega a aparecer na tela, e a
    // transição parece um "pulo" direto pra busca/dashboard. `Future.wait`
    // garante que o que for mais lento dos dois manda — o trabalho real ou
    // esse mínimo — sem atrasar quem realmente precisa esperar mais (ex.:
    // resolver o papel da conta pela rede).
    final minDuration = Future.delayed(const Duration(milliseconds: 900));
    try {
      final user = _auth.currentUser;
      // Timeout de segurança: se o canal nativo do secure storage travar
      // (em vez de lançar um erro), isso evita que a splash fique presa
      // para sempre — foi exatamente o sintoma relatado em teste manual.
      biometricEnabled =
          await _storage.readBiometricEnabled().timeout(const Duration(seconds: 5));

      if (user == null) {
        status = AuthStatus.unauthenticated;
      } else {
        role = await _resolveRole(user.uid);
        status = biometricEnabled ? AuthStatus.locked : AuthStatus.authenticated;
      }
    } catch (e) {
      // Se algo falhar (plugin de secure storage não registrado, sem
      // internet pra resolver o papel etc.), não deixe o app preso na
      // splash pra sempre. Se já existe uma sessão do Firebase, entra
      // direto sem cadeado — mais seguro assumir "sem cadeado" do que
      // travar o usuário pra fora da própria conta por um erro local.
      debugPrint('AuthController.bootstrap falhou: $e');
      status = _auth.currentUser == null ? AuthStatus.unauthenticated : AuthStatus.authenticated;
    }
    await minDuration;
    notifyListeners();
  }

  Future<bool> login(String email, String password) => _submit(() async {
        final credential =
            await _auth.signInWithEmailAndPassword(email: email, password: password);
        role = await _resolveRole(credential.user!.uid);
        status = AuthStatus.authenticated;
      });

  Future<bool> register(
    String name,
    String email,
    String password, {
    required AccountRole role,
    String? category,
    String? city,
    String? state,
  }) =>
      _submit(() async {
        final credential = await _auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
        final uid = credential.user!.uid;
        await credential.user?.updateDisplayName(name);
        final now = FieldValue.serverTimestamp();

        if (role == AccountRole.provider) {
          // Documento raiz do prestador (providers/{uid}) — ver
          // firebase/DATA_MODEL.md. A própria regra `isOwner` do
          // firestore.rules permite que o usuário recém-criado grave este
          // documento.
          await _firestore.collection('providers').doc(uid).set({
            'name': name,
            'email': email,
            'nextBudgetNumber': 1,
            'createdAt': now,
            'updatedAt': now,
          });
          // Também cria a entrada pública no diretório do marketplace
          // (mesmo id do uid — ver ProviderDirectoryRepository), pra
          // aparecer na busca do cliente desde já. Só cria se categoria e
          // cidade foram informadas (RegisterScreen exige isso pra quem
          // escolhe "Sou prestador").
          if (category != null && city != null && city.isNotEmpty) {
            await _firestore.collection('providerDirectory').doc(uid).set({
              'name': name,
              'category': category,
              'city': city,
              if (state != null && state.isNotEmpty) 'state': state,
              'claimed': true,
              'providerUid': uid,
              'createdAt': now,
              'updatedAt': now,
            });
          }
        } else {
          // Documento raiz do cliente (clients/{uid}) — o lado novo do
          // marketplace.
          await _firestore.collection('clients').doc(uid).set({
            'name': name,
            'email': email,
            'createdAt': now,
            'updatedAt': now,
          });
        }

        this.role = role;
        status = AuthStatus.authenticated;
      });

  /// Chamado a partir da tela de bloqueio biométrico. Só existe quando
  /// `status == AuthStatus.locked` (ou seja, já há uma sessão do Firebase
  /// Auth válida — isso apenas confirma a identidade local, sem falar com
  /// o Firebase). Retorna o resultado detalhado (não só bool) para a tela
  /// poder explicar o motivo quando não der certo.
  Future<BiometricResult> unlockWithBiometrics() async {
    final result = await _biometric.authenticate(
      reason: 'Confirme sua identidade para entrar no PrestadorAki',
    );
    if (result == BiometricResult.success) {
      status = AuthStatus.authenticated;
      notifyListeners();
    }
    return result;
  }

  /// Usado quando o usuário prefere digitar a senha em vez de usar a
  /// biometria na tela de bloqueio — encerra a sessão local e volta para o
  /// fluxo normal de login.
  Future<void> useLoginInstead() => logout();

  Future<void> setBiometricEnabled(bool enabled) async {
    biometricEnabled = enabled;
    await _storage.setBiometricEnabled(enabled);
    notifyListeners();
  }

  Future<void> logout() async {
    await _auth.signOut();
    await _storage.clear();
    biometricEnabled = false;
    role = null;
    status = AuthStatus.unauthenticated;
    notifyListeners();
  }

  /// Descobre se o uid é de um prestador ou de um cliente, olhando qual
  /// dos dois documentos raiz existe no Firestore. Contas criadas pelo
  /// próprio app sempre têm um dos dois (ver `register` acima); se nenhum
  /// existir (não deveria acontecer), assume prestador como padrão seguro
  /// — era o único tipo de conta antes desse pivot.
  Future<AccountRole> _resolveRole(String uid) async {
    final providerDoc = await _firestore.collection('providers').doc(uid).get();
    if (providerDoc.exists) return AccountRole.provider;
    final clientDoc = await _firestore.collection('clients').doc(uid).get();
    if (clientDoc.exists) return AccountRole.client;
    return AccountRole.provider;
  }

  Future<bool> _submit(Future<void> Function() action) async {
    isBusy = true;
    errorMessage = null;
    notifyListeners();
    try {
      await action();
      return true;
    } on FirebaseAuthException catch (e) {
      errorMessage = _messageFor(e.code);
      return false;
    } catch (e) {
      debugPrint('AuthController: erro inesperado: $e');
      errorMessage = 'Não foi possível conectar ao servidor.';
      return false;
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  /// Traduz os códigos de erro do Firebase Auth (documentados na API do
  /// SDK) para mensagens em português que fazem sentido pro usuário — sem
  /// vazar detalhes técnicos como "FirebaseAuthException".
  String _messageFor(String code) {
    switch (code) {
      case 'invalid-email':
        return 'E-mail inválido.';
      case 'user-disabled':
        return 'Esta conta foi desativada.';
      case 'user-not-found':
        return 'Não existe conta com esse e-mail.';
      case 'wrong-password':
        return 'Senha incorreta.';
      case 'invalid-credential':
        // SDKs recentes do Firebase Auth unificam "usuário não encontrado"
        // e "senha errada" nesse único código, por segurança — evita
        // indicar a quem tenta adivinhar se o e-mail existe ou não.
        return 'E-mail ou senha incorretos.';
      case 'email-already-in-use':
        return 'Já existe uma conta com esse e-mail.';
      case 'weak-password':
        return 'Senha muito fraca — use pelo menos 8 caracteres.';
      case 'too-many-requests':
        return 'Muitas tentativas. Aguarde um pouco e tente de novo.';
      case 'network-request-failed':
        return 'Sem conexão com a internet.';
      default:
        return 'Não foi possível completar a operação ($code).';
    }
  }
}
