import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/api_exception.dart';
import '../budgets/models/budget.dart';
import '../jobs/models/job.dart';
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

  /// Texto que marca um pedido que nasceu de uma CONVERSA pelo card, e não
  /// do formulário de orçamento. Fica em `requestDescription` porque a
  /// regra de criação do cliente (firestore.rules, bloco `budgets`) aceita
  /// só uma lista fechada de campos — um campo novo tipo `origem` faria o
  /// `hasOnly` recusar a gravação inteira.
  static const textoDeConversa = 'Conversa iniciada pelo cliente no app.';

  /// Devolve o orçamento onde a conversa com [provider] acontece —
  /// criando um se ainda não existir.
  ///
  /// POR QUE PRECISA DE ORÇAMENTO: o chat do app mora dentro de um
  /// orçamento (`providers/{uid}/budgets/{id}/mensagens`, ver
  /// BudgetChatScreen). Não existe conversa solta. Pedido do Franck:
  /// "ter a funcionalidade de chat que já tem lá no orçamento, mas ali no
  /// card" — então o botão do card reaproveita esse mesmo chat.
  ///
  /// SE JÁ HOUVER UM PEDIDO com esse prestador, a conversa continua nele:
  /// abrir um segundo pedido só pra "mandar um oi" espalharia o assunto em
  /// dois lugares, e o prestador perderia o fio.
  ///
  /// SE NÃO HOUVER, cria um pedido pendente sem itens, marcado com
  /// [textoDeConversa]. É deliberado que ele apareça nas Solicitações do
  /// prestador: um cliente puxando conversa É um contato comercial, e é
  /// ali que o prestador procura contato comercial. Dali ele responde e,
  /// se fechar, monta o orçamento no mesmo lugar.
  Future<({String providerUid, String budgetId})?> conversaCom(
    ProviderListing provider, {
    required String clientName,
  }) async {
    final providerUid = provider.providerUid;
    // Listagem de curadoria (sem conta no app) não tem onde receber
    // mensagem — o card nem oferece o botão nesse caso, isto é cinto de
    // segurança.
    if (providerUid == null) return null;
    final uid = _auth.currentUser!.uid;

    try {
      // `collectionGroup` por `clientUid` + ordem por data: exatamente a
      // consulta de "Meus orçamentos" (ver watchMine), que já tem índice.
      // O filtro por prestador fica no app — um cliente tem poucos
      // pedidos, e filtrar no servidor exigiria um índice só pra isso.
      final snapshot = await _firestore
          .collectionGroup('budgets')
          .where('clientUid', isEqualTo: uid)
          .orderBy('createdAt', descending: true)
          .get();
      for (final doc in snapshot.docs) {
        if (doc.data()['providerUid'] == providerUid) {
          return (providerUid: providerUid, budgetId: doc.id);
        }
      }

      final ref = _budgetsOf(providerUid).doc();
      final now = FieldValue.serverTimestamp();
      await ref.set({
        'customerName': clientName,
        'date': Timestamp.fromDate(DateTime.now()),
        'items': const [],
        'discountCents': 0,
        'clientUid': uid,
        'providerUid': providerUid,
        'providerDirectoryId': provider.id,
        'providerName': provider.name,
        'category': provider.category.wireValue,
        'requestDescription': textoDeConversa,
        'status': BudgetStatus.pendente.wireValue,
        'createdAt': now,
        'updatedAt': now,
      });
      return (providerUid: providerUid, budgetId: ref.id);
    } on FirebaseException catch (e) {
      throw ApiException(0, e.message ?? 'Não foi possível abrir a conversa.');
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

  /// Ao vivo, o Job (execução do serviço — ver `lib/features/jobs/`)
  /// ligado a cada orçamento deste cliente, indexado por `budgetId` —
  /// pedido do Franck: "o tramite do serviço precisa aparecer no card do
  /// cliente e a avaliação, só quando concluir todo o processo". Antes
  /// disso "Meus orçamentos" não sabia de nada depois que o prestador
  /// dava o aceite final — `Job` mora na subcoleção do PRESTADOR
  /// (`providers/{uid}/jobs`), então só dá pra achar via
  /// `collectionGroup`, filtrando por `clientUid` (mesma razão/mesma
  /// regra de `watchMine` acima, ver o comentário grande em
  /// firestore.rules sobre `collectionGroup` precisar do wildcard
  /// recursivo `{path=**}`).
  Stream<Map<String, Job>> watchMyJobsByBudgetId() {
    return _firestore
        .collectionGroup('jobs')
        .where('clientUid', isEqualTo: _auth.currentUser!.uid)
        .snapshots()
        .map((snapshot) => <String, Job>{
              for (final doc in snapshot.docs)
                if (doc.data()['budgetId'] is String) doc.data()['budgetId'] as String: Job.fromFirestore(doc),
            });
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
  /// `ProviderDirectoryRepository.rate`): só quem já teve um SERVIÇO
  /// CONCLUÍDO com esse prestador pode avaliar — evita nota de quem
  /// nunca contratou, e evita liberar cedo demais (pedido do Franck:
  /// "não esta errado, o tramite do serviço precisa aparecer no card do
  /// cliente e a avaliação, só quando concluir todo o processo"; antes
  /// disso checava só `Budget.status == aceito`, que acontece bem antes
  /// do serviço de fato começar/terminar).
  ///
  /// ATENÇÃO ao índice: havia aqui um comentário afirmando que "três
  /// filtros de igualdade sem orderBy não exigem índice composto no
  /// Firestore". Isso é verdade pra uma consulta de COLEÇÃO comum, mas
  /// não pra esta, que é `collectionGroup` com TRÊS igualdades — essa
  /// combinação precisa de um índice COLLECTION_GROUP declarado à mão.
  /// Ele não existia (só o equivalente de `budgets`, sobra de quando
  /// esta checagem olhava os orçamentos em vez dos jobs), então a
  /// consulta falhava sempre e o perfil do prestador respondia "Não foi
  /// possível verificar se você pode avaliar agora" ao tocar em "Ainda
  /// sem avaliações".
  ///
  /// Já uma `collectionGroup` com UMA igualdade só (ex.:
  /// `watchMyJobsByBudgetId` acima, que filtra só por `clientUid`) NÃO
  /// precisa de nada declarado — o índice de campo único que o Firestore
  /// cria sozinho já cobre o escopo de grupo. Declarar um índice assim
  /// no firestore.indexes.json inclusive DERRUBA o deploy, com "this
  /// index is not necessary, configure using single field index
  /// controls". Ver firestore.indexes.json.
  Future<bool> hasAcceptedBudgetWith(String providerDirectoryId) async {
    try {
      final snapshot = await _firestore
          .collectionGroup('jobs')
          .where('clientUid', isEqualTo: _auth.currentUser!.uid)
          .where('providerDirectoryId', isEqualTo: providerDirectoryId)
          .where('status', isEqualTo: JobStatus.concluido.wireValue)
          .limit(1)
          .get();
      return snapshot.docs.isNotEmpty;
    } on FirebaseException catch (e) {
      throw ApiException(
          0, e.message ?? 'Não foi possível verificar seu histórico com esse prestador.');
    }
  }
}
