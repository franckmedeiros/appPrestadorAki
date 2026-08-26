import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/api_exception.dart';
import 'models/provider_listing.dart';
import 'models/service_category.dart';
import 'models/service_request.dart';

/// Pedidos de orçamento do marketplace (coleção `serviceRequests`, fora de
/// `/providers` — ver firebase/DATA_MODEL.md).
///
/// Nota honesta: `listForClient`/`listForProvider` combinam um filtro de
/// igualdade com `orderBy` num campo diferente — o Firestore exige um
/// índice composto pra isso. Já deixei os dois índices necessários em
/// `firebase/firestore.indexes.json`, mas se você rodar isso antes de
/// fazer `firebase deploy --only firestore:indexes`, a primeira chamada
/// falha com um erro que traz um link direto pra criar o índice em um
/// clique — não é um bug, é assim que o Firestore funciona.
class ServiceRequestsRepository {
  ServiceRequestsRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('serviceRequests');

  Future<ServiceRequest> create({
    required String clientName,
    required ProviderListing provider,
    required String description,
    required String addressText,
    String? preferredDate,
  }) async {
    try {
      final doc = await _collection.add({
        'clientUid': _auth.currentUser!.uid,
        'clientName': clientName,
        'providerDirectoryId': provider.id,
        if (provider.providerUid != null) 'providerUid': provider.providerUid,
        'providerName': provider.name,
        'category': provider.category.wireValue,
        'description': description,
        'addressText': addressText,
        if (preferredDate != null && preferredDate.isNotEmpty) 'preferredDate': preferredDate,
        'status': ServiceRequestStatus.aguardandoPrestador.wireValue,
        'createdAt': FieldValue.serverTimestamp(),
      });
      final snapshot = await doc.get();
      return ServiceRequest.fromFirestore(snapshot);
    } on FirebaseException catch (e) {
      throw ApiException(0, e.message ?? 'Não foi possível enviar a solicitação.');
    }
  }

  Future<List<ServiceRequest>> listForClient() async {
    try {
      final snapshot = await _collection
          .where('clientUid', isEqualTo: _auth.currentUser!.uid)
          .orderBy('createdAt', descending: true)
          .get();
      return snapshot.docs.map(ServiceRequest.fromFirestore).toList();
    } on FirebaseException catch (e) {
      throw ApiException(0, e.message ?? 'Não foi possível carregar suas solicitações.');
    }
  }

  Future<List<ServiceRequest>> listForProvider() async {
    try {
      final snapshot = await _collection
          .where('providerUid', isEqualTo: _auth.currentUser!.uid)
          .orderBy('createdAt', descending: true)
          .get();
      return snapshot.docs.map(ServiceRequest.fromFirestore).toList();
    } on FirebaseException catch (e) {
      throw ApiException(0, e.message ?? 'Não foi possível carregar os pedidos recebidos.');
    }
  }

  /// Resposta simples do prestador — valor total + mensagem, sem itens
  /// detalhados (é o que diferencia esse fluxo do módulo formal de
  /// Orçamentos). Se aceito, hoje isso não cria nada automaticamente (nem
  /// job, nem cliente cadastrado) — é uma lacuna consciente: fechar esse
  /// laço de verdade (virar um serviço agendado) é o próximo passo depois
  /// que esse fluxo básico estiver testado.
  Future<void> sendQuote(String requestId, {required int amountCents, String? message}) async {
    try {
      await _collection.doc(requestId).update({
        'status': ServiceRequestStatus.orcamentoEnviado.wireValue,
        'quoteAmountCents': amountCents,
        if (message != null && message.isNotEmpty) 'quoteMessage': message,
      });
    } on FirebaseException catch (e) {
      throw ApiException(0, e.message ?? 'Não foi possível enviar o orçamento.');
    }
  }

  Future<void> respond(String requestId, {required bool accepted}) async {
    try {
      await _collection.doc(requestId).update({
        'status':
            (accepted ? ServiceRequestStatus.aceito : ServiceRequestStatus.recusado).wireValue,
      });
    } on FirebaseException catch (e) {
      throw ApiException(0, e.message ?? 'Não foi possível responder à solicitação.');
    }
  }

  /// Usado como condição pra liberar a avaliação por estrelas (ver
  /// ProviderDirectoryRepository.rate): só quem já teve um pedido aceito
  /// com esse prestador pode avaliar - evita nota de quem nunca contratou.
  /// Três filtros de igualdade sem `orderBy` não exigem índice composto no
  /// Firestore (diferente de listForClient/listForProvider acima).
  Future<bool> hasAcceptedRequestWith(String providerDirectoryId) async {
    try {
      final snapshot = await _collection
          .where('clientUid', isEqualTo: _auth.currentUser!.uid)
          .where('providerDirectoryId', isEqualTo: providerDirectoryId)
          .where('status', isEqualTo: ServiceRequestStatus.aceito.wireValue)
          .limit(1)
          .get();
      return snapshot.docs.isNotEmpty;
    } on FirebaseException catch (e) {
      throw ApiException(
          0, e.message ?? 'Não foi possível verificar seu histórico com esse prestador.');
    }
  }
}
