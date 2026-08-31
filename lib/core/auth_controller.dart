import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'biometric_service.dart';
import 'testing_flags.dart';
import 'token_storage.dart';

enum AuthStatus { unknown, authenticated, unauthenticated, locked }

/// Estado de autenticação do app, compartilhado via Provider a partir da
/// raiz (main.dart). Depois da migração para Firebase, quem sabe fazer
/// login/cadastro/logout de verdade é o próprio `FirebaseAuth` — esta
/// classe só traduz isso para o `AuthStatus` que o resto do app entende, e
/// continua guardando localmente a preferência de biometria (que nunca foi
/// uma credencial de API, sempre foi um cadeado só do app).
///
/// Conta unificada (decisão combinada com o Franck): não existe mais "OU
/// prestador OU cliente" — toda conta autenticada tem uma identidade base
/// de cliente (`clients/{uid}`, criada no cadastro ou preenchida na
/// primeira ação de cliente — ver `ensureClientDocument`), e pode
/// ADICIONALMENTE ter a capacidade de prestador (`providers/{uid}`, com
/// `isProvider == true`) — as duas nunca são mutuamente exclusivas. Ex.:
/// o João eletricista é prestador, mas pode favoritar o Marco jardineiro
/// como cliente, sem precisar de uma segunda conta.
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

  /// Se a conta logada também é prestador (tem `providers/{uid}`) — não é
  /// mais exclusivo com "ser cliente" (ver comentário da classe). `false`
  /// pra quem nunca ativou a capacidade de prestador.
  bool isProvider = false;
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

  /// E-mail da conta logada — usado pela tela "Meu perfil"
  /// (UserProfileScreen). `AuthController` não duplica isso num campo
  /// próprio porque o Firebase Auth já é a fonte da verdade.
  String? get currentUserEmail => _auth.currentUser?.email;

  /// Se existe uma sessão do Firebase Auth salva localmente — usada pelo
  /// botão de biometria da LoginScreen pra saber se dá pra tentar
  /// destravar por biometria a partir dali (igual ao app Resenha). Na
  /// prática, no fluxo normal do PrestadorAki, quem tem sessão salva E
  /// biometria ativada nunca chega a ver a LoginScreen — o bootstrap já
  /// manda direto pra `/unlock` (ver app_router.dart) — mas o botão fica
  /// certo mesmo assim, sem depender de nenhuma suposição sobre qual tela
  /// o usuário está vendo.
  bool get hasCachedSession => _auth.currentUser != null;

  /// Chamado uma vez na inicialização do app para restaurar a sessão. O
  /// Firebase Auth já persiste a sessão sozinho no dispositivo — só
  /// checamos se existe um usuário logado e, se existir, se ele também é
  /// prestador e se o cadeado biométrico está ativado.
  Future<void> bootstrap() async {
    // Duração mínima da splash — sem isso, num aparelho rápido (ou contra o
    // emulador local, sem latência de rede nenhuma) o bootstrap pode
    // terminar tão rápido que a splash nem chega a aparecer na tela, e a
    // transição parece um "pulo" direto pra busca/dashboard. `Future.wait`
    // garante que o que for mais lento dos dois manda — o trabalho real ou
    // esse mínimo — sem atrasar quem realmente precisa esperar mais (ex.:
    // resolver se a conta também é prestador pela rede).
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
        isProvider = await _checkIsProvider(user.uid);
        status = biometricEnabled ? AuthStatus.locked : AuthStatus.authenticated;
      }
    } catch (e) {
      // Se algo falhar (plugin de secure storage não registrado, sem
      // internet pra checar a capacidade de prestador etc.), não deixe o
      // app preso na splash pra sempre. Se já existe uma sessão do
      // Firebase, entra direto sem cadeado — mais seguro assumir "sem
      // cadeado" do que travar o usuário pra fora da própria conta por um
      // erro local.
      debugPrint('AuthController.bootstrap falhou: $e');
      status = _auth.currentUser == null ? AuthStatus.unauthenticated : AuthStatus.authenticated;
    }
    await minDuration;
    notifyListeners();
  }

  Future<bool> login(String email, String password) => _submit(() async {
        final credential =
            await _auth.signInWithEmailAndPassword(email: email, password: password);
        isProvider = await _checkIsProvider(credential.user!.uid);
        status = AuthStatus.authenticated;
      });

  /// Cadastro unificado — toda conta criada aqui sempre ganha uma
  /// identidade base de cliente (`clients/{uid}`); `asProvider: true`
  /// ADICIONA a capacidade de prestador por cima disso (`providers/{uid}`),
  /// nunca substitui. Ver `becomeProvider` pra uma conta já existente que
  /// decide virar prestador depois.
  Future<bool> register(
    String name,
    String email,
    String password, {
    bool asProvider = false,
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

        // Documento raiz do cliente (clients/{uid}) — identidade base de
        // TODA conta, prestador ou não (ver comentário da classe). A
        // própria regra `isOwner` do firestore.rules permite que o usuário
        // recém-criado grave este documento.
        await _firestore.collection('clients').doc(uid).set({
          'name': name,
          'email': email,
          'createdAt': now,
          'updatedAt': now,
        });

        if (asProvider) {
          await _createProviderDocument(
            uid: uid,
            name: name,
            email: email,
            category: category,
            city: city,
            state: state,
          );
          isProvider = true;
        }

        status = AuthStatus.authenticated;
      });

  /// SUPERADO pelo gate de assinatura (ver ProviderPaywallScreen +
  /// `confirmarAssinaturaPrestador` em functions/src/subscription.ts): a
  /// UI não chama mais este método diretamente — "virar prestador" agora
  /// sempre passa por uma assinatura mensal confirmada no servidor, que é
  /// quem de fato cria `providers/{uid}`. Mantido só por compatibilidade
  /// (ex.: testes/uso interno) — não remover `_createProviderDocument`
  /// nem este método quebraria nada em produção, mas nenhuma tela chama
  /// isso mais.
  Future<bool> becomeProvider({
    required String category,
    required String city,
    String? state,
  }) =>
      _submit(() async {
        final user = _auth.currentUser!;
        await _createProviderDocument(
          uid: user.uid,
          name: displayName,
          email: user.email ?? '',
          category: category,
          city: city,
          state: state,
        );
        isProvider = true;
      });

  /// Decisão de produto (combinada com o Franck — "só preparar o
  /// terreno"): um prestador recém-cadastrado NÃO aparece de graça na
  /// busca do cliente. `listingStatus` começa `'pending'` e só vira
  /// `'active'` por ativação manual (Firebase Console) por enquanto — sem
  /// pagamento de verdade integrado ainda. Por isso, diferente do
  /// comportamento antigo, isso NUNCA cria `providerDirectory/{uid}`
  /// diretamente; isso só acontece depois, quando o próprio prestador
  /// salvar o perfil com `listingStatus != 'pending'` (ver EditProfileScreen
  /// e `ProviderDirectoryRepository.upsertOwnListing`).
  Future<void> _createProviderDocument({
    required String uid,
    required String name,
    required String email,
    String? category,
    String? city,
    String? state,
  }) async {
    final now = FieldValue.serverTimestamp();
    // Copia os dados "pessoais" já preenchidos em clients/{uid} (WhatsApp,
    // endereço, chave Pix, logo) — sem isso, virar prestador fazia esses
    // campos sumirem da tela (o Franck notou com o WhatsApp): não é que os
    // dados eram apagados, é que updateOwnProfile/fetchOwnProfileData
    // passam a ler/gravar em providers/{uid} assim que isProvider vira
    // true (ver `_ownCollection`), e esse documento novo nascia sem eles.
    // Pra uma conta virando prestador pela primeira vez (`register` com
    // `asProvider: true`) o clients/{uid} acabou de ser criado, então essa
    // leitura só devolve campos vazios — inofensivo.
    final clientData = (await _firestore.collection('clients').doc(uid).get()).data() ?? const {};
    await _firestore.collection('providers').doc(uid).set({
      'name': name,
      'email': email,
      if (category != null && category.isNotEmpty) 'category': category,
      if (city != null && city.isNotEmpty) 'city': city,
      if (state != null && state.isNotEmpty) 'state': state,
      for (final field in const [
        'whatsapp',
        'addressZipCode',
        'addressStreet',
        'addressNeighborhood',
        'addressCity',
        'addressState',
        'pixKey',
        'logoUrl',
      ])
        if (clientData[field] != null) field: clientData[field],
      // kBypassProviderSubscriptionGate é TEMPORÁRIO — ver
      // lib/core/testing_flags.dart. Com ele ligado, isso já nasce
      // 'active' (sem paywall) só pra testar a busca/listagem antes do
      // Play Billing estar configurado de verdade.
      'listingStatus': kBypassProviderSubscriptionGate ? 'active' : 'pending',
      'nextBudgetNumber': 1,
      'createdAt': now,
      'updatedAt': now,
    }, SetOptions(merge: true));
  }

  /// Garante que a conta logada tem um `clients/{uid}` — chamado antes de
  /// qualquer ação de cliente (favoritar, solicitar orçamento) pra cobrir
  /// contas de prestador criadas antes desse documento existir sempre (ver
  /// `ClientAuthGate.ensureClientAccount`). Não faz nada se o documento já
  /// existir (nunca sobrescreve dados).
  Future<void> ensureClientDocument() async {
    final user = _auth.currentUser;
    if (user == null) return;
    final ref = _firestore.collection('clients').doc(user.uid);
    final doc = await ref.get();
    if (doc.exists) return;
    final now = FieldValue.serverTimestamp();
    await ref.set({
      'name': displayName,
      'email': user.email,
      'createdAt': now,
      'updatedAt': now,
    });
  }

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

  /// Nome da coleção do documento raiz "pessoal" do usuário logado —
  /// prestador continua guardando nome/e-mail/WhatsApp/endereço em
  /// `providers/{uid}` (como sempre foi); quem nunca ativou a capacidade
  /// de prestador usa `clients/{uid}`.
  String get _ownCollection => isProvider ? 'providers' : 'clients';

  /// Lê os campos "pessoais" do próprio documento raiz — WhatsApp e
  /// endereço não fazem parte do perfil público do diretório (ver
  /// `providerDirectory` no DATA_MODEL.md), só do documento
  /// `providers/{uid}`/`clients/{uid}` do próprio dono. Usado pela tela
  /// "Editar perfil" pra pré-preencher o formulário (inclusive
  /// `listingStatus`, pro prestador).
  Future<Map<String, dynamic>> fetchOwnProfileData() async {
    final user = _auth.currentUser!;
    final doc = await _firestore.collection(_ownCollection).doc(user.uid).get();
    return doc.data() ?? const <String, dynamic>{};
  }

  /// Atualiza os dados da conta logada — usado pela tela "Editar perfil"
  /// (EditProfileScreen). Grava em dois lugares: o `displayName` do
  /// Firebase Auth (usado por `displayName` acima, ex.: pra pré-preencher
  /// o nome do cliente num pedido de orçamento) e os campos do documento
  /// raiz (`providers/{uid}` ou `clients/{uid}`, dependendo da capacidade
  /// de prestador). Área de atuação (categoria/cidade/UF) do prestador é
  /// tratada à parte, em `updateProviderBusinessInfo` — este método aqui
  /// só cuida dos dados pessoais, os mesmos pros dois lados da conta.
  /// `whatsapp` e os campos de endereço são opcionais: passar `null` (ou
  /// uma string vazia) apaga o campo em vez de gravar vazio — `FieldValue
  /// .delete()` funciona normalmente dentro de um `.set(merge: true)`.
  /// Os campos de endereço são campos "planos" (`addressStreet`,
  /// `addressCity`...), não um mapa aninhado — mesma convenção que
  /// `Customer` já usa em `providers/{uid}/customers/{id}` (ver
  /// customers_repository.dart).
  Future<bool> updateOwnProfile({
    required String name,
    String? whatsapp,
    String? addressZipCode,
    String? addressStreet,
    String? addressNeighborhood,
    String? addressCity,
    String? addressState,
    String? pixKey,
    String? logoUrl,
  }) =>
      _submit(() async {
        final user = _auth.currentUser!;
        await user.updateDisplayName(name);
        // `.set(..., merge: true)` em vez de `.update(...)`: `update` exige
        // que o documento já exista, e lança `[cloud_firestore/not-found]`
        // se não existir (ex.: alguma conta antiga sem o documento raiz
        // completo) — merge grava o campo de qualquer jeito, sem apagar o
        // resto, igual ProviderDirectoryRepository.upsertOwnListing já faz.
        await _firestore.collection(_ownCollection).doc(user.uid).set(
          {
            'name': name,
            'whatsapp':
                (whatsapp != null && whatsapp.isNotEmpty) ? whatsapp : FieldValue.delete(),
            'addressZipCode':
                (addressZipCode != null && addressZipCode.isNotEmpty)
                    ? addressZipCode
                    : FieldValue.delete(),
            'addressStreet':
                (addressStreet != null && addressStreet.isNotEmpty)
                    ? addressStreet
                    : FieldValue.delete(),
            'addressNeighborhood':
                (addressNeighborhood != null && addressNeighborhood.isNotEmpty)
                    ? addressNeighborhood
                    : FieldValue.delete(),
            'addressCity':
                (addressCity != null && addressCity.isNotEmpty)
                    ? addressCity
                    : FieldValue.delete(),
            'addressState':
                (addressState != null && addressState.isNotEmpty)
                    ? addressState
                    : FieldValue.delete(),
            // Chave Pix e logo: só fazem sentido pro lado prestador (ver
            // EditProfileScreen, que só mostra os campos quando
            // `isProvider`), mas gravar aqui em vez de em
            // `updateProviderBusinessInfo` é mais simples — não são dados
            // "de negócio" (categoria/cidade) que decidem a busca, são só
            // dados da conta, igual telefone/endereço acima.
            'pixKey': (pixKey != null && pixKey.isNotEmpty) ? pixKey : FieldValue.delete(),
            'logoUrl': (logoUrl != null && logoUrl.isNotEmpty) ? logoUrl : FieldValue.delete(),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      });

  /// Atualiza a área de atuação do prestador (categoria/cidade/UF) direto
  /// em `providers/{uid}` — separado de `updateOwnProfile` porque só faz
  /// sentido pra quem já é (ou está virando) prestador. Guarda esses dados
  /// mesmo que `listingStatus` ainda seja `'pending'`, pra não se perderem
  /// enquanto a ativação não acontece (ver `_createProviderDocument`); o
  /// `EditProfileScreen` decide separadamente se chama
  /// `ProviderDirectoryRepository.upsertOwnListing` a partir disso.
  Future<bool> updateProviderBusinessInfo({
    required String category,
    required String city,
    String? state,
  }) =>
      _submit(() async {
        final user = _auth.currentUser!;
        await _firestore.collection('providers').doc(user.uid).set(
          {
            'category': category,
            'city': city,
            'state': (state != null && state.isNotEmpty) ? state : FieldValue.delete(),
            // TEMPORÁRIO (ver lib/core/testing_flags.dart) — com a flag
            // ligada, salvar aqui também já reativa uma conta que ficou
            // 'pending' (ex.: criada antes desse bypass existir), sem
            // precisar editar o Firestore na mão de novo.
            if (kBypassProviderSubscriptionGate) 'listingStatus': 'active',
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      });

  /// Troca o e-mail de login da conta — chamado pela tela "Editar perfil"
  /// quando o campo E-mail é alterado. Por segurança, o Firebase exige
  /// reautenticação recente antes de mexer no e-mail (senão lança
  /// `requires-recent-login`); e o método antigo `updateEmail` foi
  /// descontinuado nos SDKs recentes — agora só dá pra trocar via
  /// `verifyBeforeUpdateEmail`, que manda um link de confirmação pro
  /// e-mail NOVO. O e-mail de login só muda de fato (e `currentUserEmail`
  /// só reflete isso) depois que o usuário clica nesse link.
  Future<bool> updateEmailAddress(String newEmail, String currentPassword) =>
      _submit(() async {
        final user = _auth.currentUser!;
        final credential =
            EmailAuthProvider.credential(email: user.email!, password: currentPassword);
        await user.reauthenticateWithCredential(credential);
        await user.verifyBeforeUpdateEmail(newEmail);
      });

  /// Exclui a conta e todos os dados associados (perfil, cadastro de
  /// prestador com clientes/agenda/orçamentos, favoritos) — pedida na tela
  /// "Meu perfil", igual ao app Resenha. Reautentica primeiro (mesma
  /// exigência de segurança do Firebase que já existe em
  /// updateEmailAddress, acima), depois chama a Cloud Function
  /// excluirContaEDados, que apaga tudo no Firestore via recursiveDelete
  /// e só então remove a conta do Firebase Auth. Como o login já deixa de
  /// existir no servidor depois disso, encerra a sessão local do mesmo
  /// jeito que logout() faria, sem chamar signOut (o usuário já não
  /// existe mais pro Firebase).
  Future<bool> deleteAccount(String currentPassword) => _submit(() async {
        final user = _auth.currentUser!;
        final credential =
            EmailAuthProvider.credential(email: user.email!, password: currentPassword);
        await user.reauthenticateWithCredential(credential);
        await FirebaseFunctions.instance.httpsCallable('excluirContaEDados').call();
        await _storage.clear();
        biometricEnabled = false;
        isProvider = false;
        status = AuthStatus.unauthenticated;
      });

  Future<void> logout() async {
    await _auth.signOut();
    await _storage.clear();
    biometricEnabled = false;
    isProvider = false;
    status = AuthStatus.unauthenticated;
    notifyListeners();
  }

  /// Descobre se a conta também é prestador, olhando se `providers/{uid}`
  /// existe. Diferente de antes, isso NÃO é mais exclusivo com ser
  /// cliente — só responde "essa conta tem a capacidade de prestador?".
  Future<bool> _checkIsProvider(String uid) async {
    final providerDoc = await _firestore.collection('providers').doc(uid).get();
    return providerDoc.exists;
  }

  /// Chamado depois que a Cloud Function `confirmarAssinaturaPrestador`
  /// confirma a compra e cria/atualiza `providers/{uid}` no servidor —
  /// atualiza o `isProvider` em cache aqui no app (que só é lido no
  /// login/bootstrap) sem precisar deslogar e logar de novo. Ver
  /// ProviderPaywallScreen.
  Future<void> refreshProviderStatus() async {
    final user = _auth.currentUser;
    if (user == null) return;
    isProvider = await _checkIsProvider(user.uid);
    notifyListeners();
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
    } on FirebaseException catch (e) {
      // Erro do Firestore (ex.: updateOwnName gravando em providers/clients)
      // — classe diferente de FirebaseAuthException, então cairia no
      // catch genérico abaixo e mostraria sempre "Não foi possível
      // conectar ao servidor.", escondendo o motivo real (ex.: regra do
      // firestore.rules bloqueando, documento não encontrado). Mostrar a
      // mensagem de verdade ajuda a diagnosticar sem precisar olhar o
      // console do Firebase toda vez.
      debugPrint('AuthController: FirebaseException (${e.plugin}/${e.code}): ${e.message}');
      errorMessage = e.message ?? 'Não foi possível completar a operação.';
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
      case 'requires-recent-login':
        return 'Por segurança, saia e entre de novo antes de trocar o e-mail.';
      default:
        return 'Não foi possível completar a operação ($code).';
    }
  }
}
