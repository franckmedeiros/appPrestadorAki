import 'package:cloud_firestore/cloud_firestore.dart';

/// Um item de linha do orçamento (ver `orcamento_Franck_Medeiros_...pdf`,
/// exemplo mandado pelo Franck: Descrição/Qtd/Preço unitário/Preço
/// total). `unit` é o texto ao lado da quantidade na coluna "Qtd" (ex.:
/// "1 serviço", "3 m²") — no exemplo, a unidade de medida de verdade (MT)
/// já vem embutida na descrição, então isso aqui é só um rótulo livre,
/// não uma lista fechada de unidades.
class BudgetItem {
  BudgetItem({
    required this.description,
    required this.quantity,
    required this.unitPriceCents,
    this.unit = 'serviço',
  });

  factory BudgetItem.fromMap(Map<String, dynamic> map) => BudgetItem(
        description: map['description'] as String? ?? '',
        quantity: (map['quantity'] as num?)?.toDouble() ?? 1,
        unit: map['unit'] as String? ?? 'serviço',
        unitPriceCents: (map['unitPriceCents'] as num?)?.toInt() ?? 0,
      );

  final String description;
  final double quantity;
  final String unit;
  final int unitPriceCents;

  int get totalCents => (quantity * unitPriceCents).round();

  /// "1 serviço", "2,5 m²" — a mesma regra de exibição usada tanto no
  /// formulário quanto no PDF, pra nunca ficarem divergentes.
  String get quantityLabel {
    final qtyText = quantity == quantity.roundToDouble()
        ? quantity.toInt().toString()
        : quantity.toString().replaceAll('.', ',');
    return '$qtyText $unit';
  }

  Map<String, dynamic> toMap() => {
        'description': description,
        'quantity': quantity,
        'unit': unit,
        'unitPriceCents': unitPriceCents,
      };
}

/// Status do fluxo de orçamento que vem de um pedido de cliente pelo
/// marketplace (ver `provider_directory`/`ProviderPublicProfileScreen`).
/// Um orçamento criado manualmente pelo prestador (fora do marketplace)
/// não tem status nenhum (`Budget.status == null`) — o campo só existe
/// pra orçamentos que nasceram de uma solicitação de cliente:
///
///   pendente  -> cliente pediu, prestador ainda não preencheu/enviou.
///   enviado   -> prestador preencheu itens/preço e mandou pro cliente.
///   aprovado  -> cliente aprovou; falta o prestador dar o aceite final.
///   aceito    -> prestador aceitou; serviço já lançado na agenda.
///   recusado  -> alguém recusou (ver `rejectedBy`); fluxo encerrado.
enum BudgetStatus { pendente, enviado, aprovado, aceito, recusado }

extension BudgetStatusWire on BudgetStatus {
  String get wireValue => switch (this) {
        BudgetStatus.pendente => 'pendente',
        BudgetStatus.enviado => 'enviado',
        BudgetStatus.aprovado => 'aprovado',
        BudgetStatus.aceito => 'aceito',
        BudgetStatus.recusado => 'recusado',
      };

  String get label => switch (this) {
        BudgetStatus.pendente => 'Pendente de envio',
        BudgetStatus.enviado => 'Aguardando aprovação do cliente',
        BudgetStatus.aprovado => 'Aprovado — falta confirmar',
        BudgetStatus.aceito => 'Aceito',
        BudgetStatus.recusado => 'Recusado',
      };
}

BudgetStatus? budgetStatusFromWire(String? value) {
  if (value == null) return null;
  for (final status in BudgetStatus.values) {
    if (status.wireValue == value) return status;
  }
  return null;
}

/// Orçamento formal (módulo "Orçamentos"): tanto os criados manualmente
/// pelo prestador pra um cliente já cadastrado (ver CustomersRepository),
/// quanto os que nascem de um pedido de orçamento feito por um cliente
/// pelo marketplace — nesse segundo caso `status`/`clientUid` não são
/// nulos e o orçamento tramita pelos estados de `BudgetStatus` até virar
/// um compromisso na agenda (ver AppointmentsRepository).
///
/// `customerName`/`addressText`/`providerName` são uma cópia
/// ("snapshot") de quando o orçamento foi criado — de propósito, igual a
/// vários outros lugares do app: um orçamento antigo não deve mudar de
/// nome/endereço só porque o cadastro foi editado depois.
class Budget {
  Budget({
    required this.id,
    required this.customerName,
    required this.date,
    required this.items,
    this.customerId,
    this.addressText,
    this.discountCents = 0,
    this.observations,
    this.status,
    this.clientUid,
    this.providerDirectoryId,
    this.providerName,
    this.category,
    this.requestDescription,
    this.preferredDate,
    this.rejectedBy,
    this.serviceScheduledAt,
    this.serviceDurationMinutes,
    this.appointmentId,
    this.createdAt,
  });

  factory Budget.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final rawItems = (data['items'] as List<dynamic>?) ?? const [];
    return Budget(
      id: doc.id,
      customerId: data['customerId'] as String?,
      customerName: data['customerName'] as String? ?? '',
      addressText: data['addressText'] as String?,
      date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      items: rawItems
          .map((raw) => BudgetItem.fromMap(raw as Map<String, dynamic>))
          .toList(),
      discountCents: (data['discountCents'] as num?)?.toInt() ?? 0,
      observations: data['observations'] as String?,
      status: budgetStatusFromWire(data['status'] as String?),
      clientUid: data['clientUid'] as String?,
      providerDirectoryId: data['providerDirectoryId'] as String?,
      providerName: data['providerName'] as String?,
      category: data['category'] as String?,
      requestDescription: data['requestDescription'] as String?,
      preferredDate: data['preferredDate'] as String?,
      rejectedBy: data['rejectedBy'] as String?,
      serviceScheduledAt: (data['serviceScheduledAt'] as Timestamp?)?.toDate(),
      serviceDurationMinutes: (data['serviceDurationMinutes'] as num?)?.toInt(),
      appointmentId: data['appointmentId'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  final String id;
  final String? customerId;
  final String customerName;
  final String? addressText;
  final DateTime date;
  final List<BudgetItem> items;
  final int discountCents;
  final String? observations;

  /// Não nulo apenas pra orçamentos que nasceram de um pedido de cliente
  /// pelo marketplace (ver classe acima).
  final BudgetStatus? status;
  final String? clientUid;
  final String? providerDirectoryId;
  final String? providerName;
  final String? category;
  final String? requestDescription;

  /// Data preferida em texto livre, informada pelo cliente ao pedir o
  /// orçamento (a data/hora real do serviço só é definida no aceite
  /// final do prestador — ver `serviceScheduledAt`).
  final String? preferredDate;

  /// 'prestador' ou 'cliente' — quem recusou, só relevante quando
  /// `status == BudgetStatus.recusado`.
  final String? rejectedBy;

  final DateTime? serviceScheduledAt;
  final int? serviceDurationMinutes;
  final String? appointmentId;
  final DateTime? createdAt;

  /// Se veio de um pedido de cliente pelo marketplace (em vez de criado
  /// manualmente pelo prestador).
  bool get isFromClientRequest => clientUid != null;

  int get subtotalCents => items.fold(0, (sum, item) => sum + item.totalCents);

  int get totalCents {
    final total = subtotalCents - discountCents;
    return total < 0 ? 0 : total;
  }

  Map<String, dynamic> toMap() => {
        if (customerId != null) 'customerId': customerId,
        'customerName': customerName,
        if (addressText != null && addressText!.isNotEmpty) 'addressText': addressText,
        'date': Timestamp.fromDate(date),
        'items': items.map((item) => item.toMap()).toList(),
        'discountCents': discountCents,
        if (observations != null && observations!.isNotEmpty) 'observations': observations,
        if (status != null) 'status': status!.wireValue,
        if (clientUid != null) 'clientUid': clientUid,
        if (providerDirectoryId != null) 'providerDirectoryId': providerDirectoryId,
        if (providerName != null) 'providerName': providerName,
        if (category != null) 'category': category,
        if (requestDescription != null) 'requestDescription': requestDescription,
        if (preferredDate != null) 'preferredDate': preferredDate,
        if (rejectedBy != null) 'rejectedBy': rejectedBy,
        if (serviceScheduledAt != null)
          'serviceScheduledAt': Timestamp.fromDate(serviceScheduledAt!),
        if (serviceDurationMinutes != null)
          'serviceDurationMinutes': serviceDurationMinutes,
        if (appointmentId != null) 'appointmentId': appointmentId,
      };

  Budget copyWith({
    String? customerId,
    String? customerName,
    String? addressText,
    DateTime? date,
    List<BudgetItem>? items,
    int? discountCents,
    String? observations,
    BudgetStatus? status,
  }) =>
      Budget(
        id: id,
        customerId: customerId ?? this.customerId,
        customerName: customerName ?? this.customerName,
        addressText: addressText ?? this.addressText,
        date: date ?? this.date,
        items: items ?? this.items,
        discountCents: discountCents ?? this.discountCents,
        observations: observations ?? this.observations,
        status: status ?? this.status,
        clientUid: clientUid,
        providerDirectoryId: providerDirectoryId,
        providerName: providerName,
        category: category,
        requestDescription: requestDescription,
        rejectedBy: rejectedBy,
        serviceScheduledAt: serviceScheduledAt,
        serviceDurationMinutes: serviceDurationMinutes,
        appointmentId: appointmentId,
        createdAt: createdAt,
      );
}
