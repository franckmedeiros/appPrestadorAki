import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/api_exception.dart';
import 'models/job.dart';

/// Repositório do módulo "Serviços" (Kanban), direto no Firestore em
/// `providers/{uid}/jobs` — mesmo padrão de CRUD simples sem Cloud
/// Function usado por `AppointmentsRepository`/`CustomersRepository`
/// (a Cloud Function em functions/src/jobs.ts só cuida de AVISAR o
/// cliente a cada mudança de etapa, não de criar/validar o job em si).
///
/// Diferente de `BudgetsRepository`, aqui NÃO existe (por enquanto)
/// nenhuma consulta `collectionGroup` do lado do cliente — só o
/// prestador lê a própria subcoleção, então a regra pode continuar
/// usando `isOwner(providerId)` sem o problema descrito em
/// `Budget.providerUid` (mistura de variável de caminho com campo numa
/// collectionGroup). Se um dia existir uma tela "Meus serviços" pro
/// cliente, valerá a pena revisitar isso.
class JobsRepository {
  JobsRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> get _collection => _firestore
      .collection('providers')
      .doc(_auth.currentUser!.uid)
      .collection('jobs');

  /// Ao vivo, mais recente primeiro — usado pelo Kanban (agrupa por
  /// status na tela, ver JobsKanbanScreen) e pelo selo de contagem no
  /// atalho do Dashboard.
  Stream<List<Job>> watchAll() {
    return _collection
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(Job.fromFirestore).toList());
  }

  /// Chamado só por `BudgetsRepository.acceptFinal`, junto com a criação
  /// do compromisso na Agenda — nunca direto de uma tela.
  Future<Job> create({
    required String customerName,
    required int totalCents,
    String? budgetId,
    String? appointmentId,
    String? clientUid,
    String? providerDirectoryId,
    String? providerName,
    String? category,
    String? addressText,
  }) async {
    try {
      final now = FieldValue.serverTimestamp();
      final doc = await _collection.add({
        'providerUid': _auth.currentUser!.uid,
        'status': JobStatus.novo.wireValue,
        'customerName': customerName,
        'totalCents': totalCents,
        if (budgetId != null) 'budgetId': budgetId,
        if (appointmentId != null) 'appointmentId': appointmentId,
        if (clientUid != null) 'clientUid': clientUid,
        if (providerDirectoryId != null) 'providerDirectoryId': providerDirectoryId,
        if (providerName != null) 'providerName': providerName,
        if (category != null) 'category': category,
        if (addressText != null && addressText.isNotEmpty) 'addressText': addressText,
        'createdAt': now,
        'updatedAt': now,
      });
      final snapshot = await doc.get();
      return Job.fromFirestore(snapshot);
    } on FirebaseException catch (e) {
      throw ApiException(0, e.message ?? 'Não foi possível criar o serviço.');
    }
  }

  /// Atualiza o valor do Job já existente ligado a um orçamento — pedido
  /// do Franck: "depois de aceito, preciso reenviar o valor do aditivo
  /// via qrcode ou o valor total novamente para pagamento". Chamado só
  /// por `BudgetsRepository.acceptFinal` quando o prestador reconfirma um
  /// orçamento que já tinha sido aceito antes (um aditivo mudou o valor
  /// e o cliente aprovou a revisão) — nesse caso NÃO nasce um Job novo
  /// (ver `create` acima), só atualiza o valor do que já existe.
  ///
  /// Busca pelo `budgetId` (1:1 com o orçamento) em vez de exigir o id do
  /// Job à parte — ninguém guarda essa referência fora daqui, então seria
  /// só mais um campo cruzado pra manter sincronizado.
  ///
  /// Só atualizar `totalCents` já basta: se o Job ainda não chegou em
  /// "aguardando pagamento", o valor novo é o que vai valer quando
  /// chegar. Se JÁ estava em "aguardando pagamento" (cobrança/QR Code Pix
  /// já enviados com o valor antigo), a escrita abaixo muda `totalCents`
  /// mesmo sem trocar de raia — é exatamente essa mudança que
  /// `functions/src/jobs.ts` (onJobStatusChanged) está de olho pra
  /// regerar o QR Code com o valor novo e avisar o cliente de novo, sem
  /// precisar de nenhuma tela nova aqui no app.
  Future<void> syncTotalFromAditivo({
    required String budgetId,
    required int totalCents,
  }) async {
    try {
      final snapshot = await _collection.where('budgetId', isEqualTo: budgetId).limit(1).get();
      if (snapshot.docs.isEmpty) return;
      await snapshot.docs.first.reference.update({
        'totalCents': totalCents,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      throw ApiException(0, e.message ?? 'Não foi possível atualizar o valor do serviço.');
    }
  }

  /// Avança (ou volta, ex.: interrompido -> em andamento) o serviço pra
  /// outra raia do Kanban — `paidAt`/`completedAt` só fazem sentido nas
  /// transições correspondentes (ver chamadas em JobsKanbanScreen).
  Future<void> updateStatus(
    String id,
    JobStatus status, {
    bool markPaidNow = false,
    bool markCompletedNow = false,
  }) async {
    try {
      await _collection.doc(id).update({
        'status': status.wireValue,
        'updatedAt': FieldValue.serverTimestamp(),
        if (markPaidNow) 'paidAt': FieldValue.serverTimestamp(),
        if (markCompletedNow) 'completedAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      throw ApiException(0, e.message ?? 'Não foi possível atualizar o serviço.');
    }
  }
}
