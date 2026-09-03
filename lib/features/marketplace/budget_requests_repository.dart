import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/api_exception.dart';
import '../budgets/models/budget.dart';
import 'models/provider_listing.dart';

/// Lado do CLIENTE no fluxo de pedido de orçamento pelo marketplace.
///
/// Antes existia uma coleção à parte, `serviceRequests`, com um "Pedido"
/// que só depois virava um orçamento de verdade — o Franck pediu pra
/// tirar essa etapa do meio: o pedido do cliente já nasce como um
/// orçamento (status `pendente`) na MESMA coleção que o prestador usa no
/// módulo formal de Orçamentos (`providers/{uid}/budgets`, ver
/// `Budget`/`BudgetsRepository`). Esta classe cobre só as operações que o
/// CLIENTE faz nessa coleção — que pertence à conta de OUTRO usuário (o
/// prestador) — enquanto `BudgetsRepository` cobre o que o PRESTADOR faz
/// na própria coleção. O firestore.rules autoriza esse `create`/`update`
/// entre contas de forma bem restrita (ver o bloco `budgets` nas regras).
class BudgetRequestsRepository {
  BudgetRequestsRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> _budgetsOf(String providerUid) => _firestore
      .collection('providers')
      .doc(providerUid)
      .collection('budgets');

  /// Cria o pedido de orçamento como um `Budget` pendente na subcoleção do
  /// prestador escolhido. Retorna `null` quando o prestador ainda não tem
  /// conta no app (listagem "não reivindicada", `provider.providerUid ==
  /// null`) — não existe onde gravar o pedido nesse caso; a tela continua
  /// oferecendo o convite manual por WhatsApp (ver RequestQuoteFormScreen).
  Future<Budget?> create({
    required String clientName,
    required ProviderListing provider,
    required String description,
    required String addressText,
    String? preferredDate,
    String? clientPhone,
  }) async {
    final providerUid = provider.providerUid;
    if (providerUid == null) return null;
    try {
      final ref = _budgetsOf(providerUid).doc();
      final now = FieldValue.serverTimestamp();
      await ref.set({
        'customerName': clientName,
        'date': Timestamp.fromDate(DateTime.now()),
        'items': const [],
        'discountCents': 0,
        'clientUid': _auth.currentUser!.uid,
        if (clientPhone != null && clientPhone.isNotEmpty) 'clientPhone': clientPhone,
        'providerUid': providerUid,
        'providerDirectoryId': provider.id,
        'providerName': provider.name,
        'category': provider.category.wireValue,
        'requestDescription': description,
        'addressText': addressText,
        if (preferredDate != null && preferredDate.isNotEmpty) 'preferredDate': preferredDate,
        'status': BudgetStatus.pendente.wireValue,
        'createdAt': now,
        'updatedAt': now,
      });
      final snapshot = await ref.get();
      return Budget.fromFirestore(snapshot);
    } on FirebaseException catch (e) {
      throw ApiException(0, e.message ?? 'Não foi possível enviar a solicitação.');
    }
  }

  /// Ao vivo, mais recente primeiro — todos os orçamentos pedidos por
  /// este cliente, em QUALQUER prestador (por isso `collectionGroup`, em
  /// vez de uma única subcoleção — ver `BudgetsRepository.watchAll` para
  /// o equivalente do lado do prestador, escopado a uma única conta).
  Stream<List<Budget>> watchMine() {
    return _firestore
        .collectionGroup('budgets')
        .where('clientUid', isEqualTo: _auth.currentUser!.uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(Budget.fromFirestore).toList());
  }

  /// Cliente aprova um orçamento que o prestador enviou (`status ==
  /// enviado`) — volta pro prestador, que ainda precisa dar o aceite
  /// final pra virar compromisso na agenda (pedido do Franck: "Se
  /// aprovar volta para o prestador para ele dar o aceita").
  Future<void> approve(Budget budget) => _respond(budget, approved: true);

  /// Cliente recusa um orçamento enviado.
  Future<void> reject(Budget budget) => _respond(budget, approved: false);

  Future<void> _respond(Budget budget, {required bool approved}) async {
    final providerUid = budget.providerDirectoryId;
    if (providerUid == null) {
      throw ApiException(0, 'Este orçamento não tem um prestador associado.');
    }
    try {
      await _budgetsOf(providerUid).doc(budget.id).set({
        'status': (approved ? BudgetStatus.aprovado : BudgetStatus.recusado).wireValue,
        if (!approved) 'rejectedBy': 'cliente',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } on FirebaseException catch (e) {
      throw ApiException(0, e.message ?? 'Não foi possível responder ao orçamento.');
    }
  }

  /// Arquiva/desarquiva, só pro CLIENTE, um pedido de "Meus orçamentos"
  /// (pedido do Franck) — não apaga nada, só marca `archivedByClient` pra
  /// essa tela deixar de mostrar por padrão. Precisa de uma regra própria
  /// em firestore.rules (fora da janela estreita de transição de
  /// `status` que as outras respostas do cliente exigem — ver `_respond`
  /// acima), porque este campo pode mudar em QUALQUER status, a qualquer
  /// momento, nos dois sentidos.
  Future<void> setArchivedByClient(Budget budget, bool archived) async {
    final providerUid = budget.providerUid;
    if (providerUid == null) {
      throw ApiException(0, 'Este orçamento não tem um prestador associado.');
    }
    try {
      await _budgetsOf(providerUid).doc(budget.id).set({
        'archivedByClient': archived,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } on FirebaseException catch (e) {
      throw ApiException(0, e.message ?? 'Não foi possível arquivar o pedido.');
    }
  }

  /// Usado como condição pra liberar a avaliação por estrelas (ver
  /// `ProviderDirectoryRepository.rate`): só quem já teve um orçamento
  /// aceito com esse prestador pode avaliar — evita nota de quem nunca
  /// contratou. Três filtros de igualdade sem `orderBy` não exigem
  /// índice composto no Firestore.
  Future<bool> hasAcceptedBudgetWith(String providerDirectoryId) async {
    try {
      final snapshot = await _firestore
          .collectionGroup('budgets')
          .where('clientUid', isEqualTo: _auth.currentUser!.uid)
          .where('providerDirectoryId', isEqualTo: providerDirectoryId)
          .where('status', isEqualTo: BudgetStatus.aceito.wireValue)
          .limit(1)
          .get();
      return snapshot.docs.isNotEmpty;
    } on FirebaseException catch (e) {
      throw ApiException(
          0, e.message ?? 'Não foi possível verificar seu histórico com esse prestador.');
    }
  }
}
