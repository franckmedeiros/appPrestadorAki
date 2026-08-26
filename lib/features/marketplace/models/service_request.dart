import 'package:cloud_firestore/cloud_firestore.dart';
import 'service_category.dart';

enum ServiceRequestStatus { aguardandoPrestador, orcamentoEnviado, aceito, recusado }

ServiceRequestStatus serviceRequestStatusFromWire(String value) =>
    ServiceRequestStatus.values.firstWhere(
      (s) => s.wireValue == value,
      orElse: () => ServiceRequestStatus.aguardandoPrestador,
    );

extension ServiceRequestStatusWire on ServiceRequestStatus {
  String get wireValue => switch (this) {
        ServiceRequestStatus.aguardandoPrestador => 'aguardando_prestador',
        ServiceRequestStatus.orcamentoEnviado => 'orcamento_enviado',
        ServiceRequestStatus.aceito => 'aceito',
        ServiceRequestStatus.recusado => 'recusado',
      };

  String get label => switch (this) {
        ServiceRequestStatus.aguardandoPrestador => 'Aguardando resposta',
        ServiceRequestStatus.orcamentoEnviado => 'Orçamento recebido',
        ServiceRequestStatus.aceito => 'Aceito',
        ServiceRequestStatus.recusado => 'Recusado',
      };
}

/// Pedido de orçamento do marketplace (coleção `serviceRequests`, fora de
/// `/providers` — ver firebase/DATA_MODEL.md): o primeiro contato entre um
/// cliente e um prestador do diretório. É deliberadamente mais simples que
/// o módulo formal de Orçamentos (que já existe para prestador × cliente
/// cadastrado manualmente, com numeração sequencial e versionamento via
/// Cloud Function) — aqui é só um valor total e uma mensagem.
class ServiceRequest {
  ServiceRequest({
    required this.id,
    required this.clientUid,
    required this.clientName,
    required this.providerDirectoryId,
    this.providerUid,
    required this.providerName,
    required this.category,
    required this.description,
    required this.addressText,
    this.preferredDate,
    required this.status,
    this.quoteAmountCents,
    this.quoteMessage,
    required this.createdAt,
  });

  factory ServiceRequest.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return ServiceRequest(
      id: doc.id,
      clientUid: data['clientUid'] as String? ?? '',
      clientName: data['clientName'] as String? ?? '',
      providerDirectoryId: data['providerDirectoryId'] as String? ?? '',
      providerUid: data['providerUid'] as String?,
      providerName: data['providerName'] as String? ?? '',
      category: serviceCategoryFromWire(data['category'] as String? ?? 'outro'),
      description: data['description'] as String? ?? '',
      addressText: data['addressText'] as String? ?? '',
      preferredDate: data['preferredDate'] as String?,
      status: serviceRequestStatusFromWire(data['status'] as String? ?? 'aguardando_prestador'),
      quoteAmountCents: data['quoteAmountCents'] as int?,
      quoteMessage: data['quoteMessage'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  final String id;
  final String clientUid;
  final String clientName;
  final String providerDirectoryId;
  final String? providerUid;
  final String providerName;
  final ServiceCategory category;
  final String description;
  final String addressText;
  final String? preferredDate;
  final ServiceRequestStatus status;
  final int? quoteAmountCents;
  final String? quoteMessage;
  final DateTime createdAt;
}
