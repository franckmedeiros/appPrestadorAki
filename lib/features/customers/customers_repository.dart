import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/api_exception.dart';
import 'models/customer.dart';

/// Repositório de clientes, direto no Firestore em
/// `providers/{uid}/customers` (ver firebase/DATA_MODEL.md) — sem Cloud
/// Function, porque não tem nenhuma regra de negócio especial aqui, só
/// CRUD escopado ao prestador logado (o isolamento entre prestadores é
/// garantido pelo firestore.rules, não só por este código).
///
/// Continua lançando `ApiException` (não `FirebaseException` diretamente)
/// nos erros — mesmo tipo que já era usado quando isso chamava a API REST
/// — só pra não precisar mexer nas telas que já sabem tratar esse erro
/// (CustomerFormScreen, CustomersListScreen).
///
/// Nota honesta: a busca (`search`) é feita no cliente, depois de baixar a
/// lista inteira — o Firestore não tem busca de texto parcial nativa.
/// Funciona bem para a quantidade de clientes esperada de um prestador
/// autônomo; se a base crescer muito, isso precisará virar uma solução de
/// busca de verdade (ex.: Algolia/Typesense via Cloud Function), não algo
/// que dê pra resolver só com consultas do Firestore.
class CustomersRepository {
  CustomersRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> get _collection => _firestore
      .collection('providers')
      .doc(_auth.currentUser!.uid)
      .collection('customers');

  Future<List<Customer>> list({String? search}) async {
    try {
      final snapshot = await _collection.orderBy('name').get();
      final customers = snapshot.docs.map(Customer.fromFirestore).toList();
      if (search == null || search.isEmpty) return customers;

      final query = search.toLowerCase();
      return customers
          .where((c) =>
              c.name.toLowerCase().contains(query) || (c.phone?.contains(query) ?? false))
          .toList();
    } on FirebaseException catch (e) {
      throw ApiException(0, e.message ?? 'Não foi possível carregar os clientes.');
    }
  }

  /// Versão "ao vivo" de `list()` — usada por `CustomersListScreen` no
  /// lugar de um `Future` recarregado manualmente depois de criar/editar
  /// um cliente. Com `.snapshots()`, o Firestore atualiza a lista sozinho
  /// assim que a escrita é confirmada (inclusive de forma otimista, antes
  /// mesmo da confirmação do servidor) — resolve de vez a reclamação de
  /// "salvei e não apareceu, precisei sair e entrar de novo" sem depender
  /// de acertar o momento exato de recarregar manualmente.
  Stream<List<Customer>> watchAll() {
    return _collection
        .orderBy('name')
        .snapshots()
        .map((snapshot) => snapshot.docs.map(Customer.fromFirestore).toList());
  }

  Future<Customer> create({
    required String name,
    String? phone,
    String? whatsapp,
    String? email,
    String? addressCity,
    String? addressState,
    String? clientUid,
  }) async {
    try {
      final now = FieldValue.serverTimestamp();
      final doc = await _collection.add({
        'name': name,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
        if (whatsapp != null && whatsapp.isNotEmpty) 'whatsapp': whatsapp,
        if (email != null && email.isNotEmpty) 'email': email,
        if (addressCity != null && addressCity.isNotEmpty) 'addressCity': addressCity,
        if (addressState != null && addressState.isNotEmpty) 'addressState': addressState,
        if (clientUid != null) 'clientUid': clientUid,
        'createdAt': now,
        'updatedAt': now,
      });
      final snapshot = await doc.get();
      return Customer.fromFirestore(snapshot);
    } on FirebaseException catch (e) {
      throw ApiException(0, e.message ?? 'Não foi possível salvar o cliente.');
    }
  }

  /// Busca um cliente já cadastrado a partir do uid da conta de cliente do
  /// app (`clientUid`) ou, se não existir ainda, cria um novo — usado
  /// quando chega um pedido de orçamento pelo marketplace (ver
  /// `Budget.clientUid`/`BudgetsRepository`): o prestador não precisa
  /// cadastrar manualmente um cliente que já veio pelo app. Cadastro
  /// manual continua existindo à parte, para clientes fora do app.
  Future<Customer> findOrCreateForClient({
    required String clientUid,
    required String name,
  }) async {
    try {
      final existing =
          await _collection.where('clientUid', isEqualTo: clientUid).limit(1).get();
      if (existing.docs.isNotEmpty) {
        return Customer.fromFirestore(existing.docs.first);
      }
    } on FirebaseException catch (e) {
      throw ApiException(0, e.message ?? 'Não foi possível buscar o cliente.');
    }
    return create(name: name, clientUid: clientUid);
  }

  /// Atualiza um cliente já existente — usado por `CustomerFormScreen` em
  /// modo de edição (tocar num cliente na lista). `.set(merge: true)` em
  /// vez de `.update(...)` pela mesma razão já documentada em
  /// `AuthController.updateOwnProfile`: nunca lança erro de "documento não
  /// encontrado" e nunca apaga campos que não foram passados aqui.
  Future<void> update(
    String id, {
    required String name,
    String? phone,
    String? whatsapp,
    String? email,
    String? addressCity,
    String? addressState,
  }) async {
    try {
      await _collection.doc(id).set({
        'name': name,
        'phone': (phone != null && phone.isNotEmpty) ? phone : FieldValue.delete(),
        'whatsapp': (whatsapp != null && whatsapp.isNotEmpty) ? whatsapp : FieldValue.delete(),
        'email': (email != null && email.isNotEmpty) ? email : FieldValue.delete(),
        'addressCity':
            (addressCity != null && addressCity.isNotEmpty) ? addressCity : FieldValue.delete(),
        'addressState':
            (addressState != null && addressState.isNotEmpty) ? addressState : FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } on FirebaseException catch (e) {
      throw ApiException(0, e.message ?? 'Não foi possível atualizar o cliente.');
    }
  }
}
