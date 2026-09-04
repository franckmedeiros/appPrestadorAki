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
    this.aditivoNumber,
  });

  factory BudgetItem.fromMap(Map<String, dynamic> map) => BudgetItem(
        description: map['description'] as String? ?? '',
        quantity: (map['quantity'] as num?)?.toDouble() ?? 1,
        unit: map['unit'] as String? ?? 'serviço',
        unitPriceCents: (map['unitPriceCents'] as num?)?.toInt() ?? 0,
        aditivoNumber: (map['aditivoNumber'] as num?)?.toInt(),
      );

  final String description;
  final double quantity;
  final String unit;
  final int unitPriceCents;

  /// `null` pro item ORIGINAL do orçamento; um número (1, 2, ...) pro
  /// item que foi ACRESCENTADO por um aditivo — pedido do Franck: "eu
  /// sempre preciso ver o orçamento original e o aditivo... seja como um
  /// item a mais no orçamento, marcando como aditivo". Diferente do
  /// desenho anterior (substituir a lista inteira de itens e guardar o
  /// estado anterior à parte, numa subcoleção `versions` que ninguém via
  /// na tela), agora o aditivo só ACRESCENTA item(ns) na MESMA lista — o
  /// orçamento original nunca é escondido, só ganha linhas novas
  /// marcadas com um selo "Aditivo nº N" (ver BudgetFormScreen/
  /// MyRequestsScreen/budget_pdf.dart).
  final int? aditivoNumber;

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
        if (aditivoNumber != null) 'aditivoNumber': aditivoNumber,
      };
}

/// Status do fluxo de orçamento que vem de um pedido de cliente pelo
/// marketplace (ver `provider_directory`/`ProviderPublicProfileScreen`).
/// Um orçamento criado manualmente pelo prestador (fora do marketplace)
/// não tem status nenhum (`Budget.status == null`) — o campo só existe
/// pra orçamentos que nasceram de uma solicitação de cliente:
///
///   pendente       -> cliente pediu, prestador ainda não preencheu/enviou.
///   enviado        -> prestador preencheu itens/preço e mandou pro cliente.
///   aprovado       -> cliente aprovou; falta o prestador dar o aceite final.
///   aceito         -> prestador aceitou; serviço já lançado na agenda.
///   aditivoEnviado -> orçamento já tinha ido pro cliente (em qualquer
///                     estado) e o prestador registrou um ADITIVO (ver
///                     BudgetsRepository.registerAditivo) — pedido do
///                     Franck: "quando eu reenvio o aditivo... ele não
///                     poderia estar como Aceito, e sim indicando que
///                     foi enviado pro cliente o aditivo e aguardando
///                     aprovação do mesmo". Aceita a mesma decisão do
///                     cliente que `enviado` (aprovar vira `aprovado`,
///                     recusar vira `recusado`) — só existe pra dar um
///                     rótulo/cor diferentes, deixando claro que o que
///                     está pendente agora é a REVISÃO, não a proposta
///                     original.
///   recusado       -> alguém recusou (ver `rejectedBy`); fluxo encerrado.
enum BudgetStatus { pendente, enviado, aprovado, aceito, aditivoEnviado, recusado }

extension BudgetStatusWire on BudgetStatus {
  String get wireValue => switch (this) {
        BudgetStatus.pendente => 'pendente',
        BudgetStatus.enviado => 'enviado',
        BudgetStatus.aprovado => 'aprovado',
        BudgetStatus.aceito => 'aceito',
        BudgetStatus.aditivoEnviado => 'aditivo_enviado',
        BudgetStatus.recusado => 'recusado',
      };

  String get label => switch (this) {
        BudgetStatus.pendente => 'Pendente de envio',
        BudgetStatus.enviado => 'Aguardando aprovação do cliente',
        BudgetStatus.aprovado => 'Aprovado — falta confirmar',
        BudgetStatus.aceito => 'Aceito',
        BudgetStatus.aditivoEnviado => 'Aditivo enviado — aguardando aprovação',
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
    this.clientPhone,
    this.providerUid,
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
    this.paymentPixPayload,
    this.paymentAmountCents,
    this.paymentRequestedAt,
    this.paymentPaidAt,
    this.archivedByClient = false,
    this.archivedByProvider = false,
    this.revisionNumber = 0,
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
      clientPhone: data['clientPhone'] as String?,
      providerUid: data['providerUid'] as String?,
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
      paymentPixPayload: data['paymentPixPayload'] as String?,
      paymentAmountCents: (data['paymentAmountCents'] as num?)?.toInt(),
      paymentRequestedAt: (data['paymentRequestedAt'] as Timestamp?)?.toDate(),
      paymentPaidAt: (data['paymentPaidAt'] as Timestamp?)?.toDate(),
      archivedByClient: data['archivedByClient'] as bool? ?? false,
      archivedByProvider: data['archivedByProvider'] as bool? ?? false,
      revisionNumber: (data['revisionNumber'] as num?)?.toInt() ?? 0,
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

  /// Telefone do cliente no momento do pedido (cópia/"snapshot", mesma
  /// razão de `customerName`/`addressText` — ver comentário da classe) —
  /// usado só pra casar por telefone com um cadastro de cliente já
  /// existente do prestador (ver
  /// `CustomersRepository.findOrCreateForClient`), nunca reexibido como
  /// se fosse o telefone atual da conta.
  final String? clientPhone;

  /// Uid do prestador dono deste orçamento — gravado explicitamente como
  /// CAMPO (em vez de só inferido do próprio caminho do documento,
  /// `providers/{uid}/budgets/...`) porque o Firestore recusa consultas
  /// em `collectionGroup` quando a regra de segurança mistura uma
  /// variável do caminho (`isOwner(providerId)`) com uma condição sobre
  /// campo do documento (`clientUid`) dentro de um OR — mesmo sendo
  /// logicamente seguro, ele não consegue provar isso pra uma
  /// collectionGroup query e nega a consulta inteira (documentado pelo
  /// próprio Firebase). Por isso `firestore.rules` usa este campo (em vez
  /// de `isOwner`) na regra de `list`, e tanto `BudgetsRepository` quanto
  /// `BudgetRequestsRepository` sempre gravam ele.
  final String? providerUid;
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

  /// Os quatro campos abaixo só existem em orçamentos vindos de um
  /// pedido de cliente pelo marketplace, e só são gravados pelo Admin
  /// SDK (ver `functions/src/jobs.ts` — `onJobStatusChanged`), nunca pelo
  /// app: quando o serviço (Job, ver `JobStatus`) entra em "aguardando
  /// pagamento", a function monta o QR Code Pix (a chave mora em
  /// `providers/{uid}.pixKey`, campo privado que o cliente não tem como
  /// ler direto) e grava aqui, pra "Meus orçamentos" mostrar o QR Code
  /// sem precisar o cliente estar presencialmente com o prestador (pedido
  /// do Franck: "deve ser enviado via app"). Por isso NÃO entram em
  /// `toMap()` abaixo — o app nunca deveria escrever neles.
  final String? paymentPixPayload;
  final int? paymentAmountCents;
  final DateTime? paymentRequestedAt;

  /// Preenchido quando o serviço é concluído (`JobStatus.concluido`) —
  /// usado só pra trocar o call-to-action "pagar agora" por uma
  /// confirmação depois que o prestador já bateu o pagamento como
  /// recebido (ver JobDetailsSheet — "Confirmar pagamento e concluir").
  final DateTime? paymentPaidAt;

  /// Marca só pro CLIENTE esconder um pedido antigo da lista padrão de
  /// "Meus orçamentos" (pedido do Franck) — não afeta a visão do
  /// prestador em "Orçamentos" nenhum pouco (é um campo por conta, não
  /// uma exclusão). Gravado pelo próprio cliente via
  /// `BudgetRequestsRepository.setArchivedByClient` — ver regra dedicada
  /// em firestore.rules que libera só ESSE campo pra ele, mesmo fora da
  /// janela estreita de transição de `status` que as outras regras de
  /// update do cliente exigem.
  final bool archivedByClient;

  /// Mesma ideia de `archivedByClient`, só que do lado do PRESTADOR —
  /// pedido do Franck: "criar a opção de arquivar" na tela "Orçamentos"
  /// (ver BudgetsScreen/BudgetsRepository.setArchivedByProvider), pra
  /// tirar da lista principal orçamentos já resolvidos (`aceito`/
  /// `recusado`) sem apagar nada. Independente de `archivedByClient` —
  /// cada lado arquiva (ou não) por conta própria.
  final bool archivedByProvider;

  /// Contagem de aditivos já registrados neste orçamento (0 = nunca
  /// revisado) — pedido do Franck: "quando o orçamento sofrer revisão,
  /// realizar a opção de aditivo de orçamento". Cada aditivo grava uma
  /// "foto" do estado anterior em `versions` (ver
  /// `BudgetsRepository.registerAditivo`) e atualiza `date` pra data do
  /// aditivo — é por isso que `date` (usado no PDF e no card do cliente)
  /// sempre reflete a revisão mais recente, nunca a data de criação
  /// original (essa fica só em `createdAt`, que nunca muda).
  final int revisionNumber;

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
        if (clientPhone != null) 'clientPhone': clientPhone,
        if (providerUid != null) 'providerUid': providerUid,
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
        'revisionNumber': revisionNumber,
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
        clientPhone: clientPhone,
        providerUid: providerUid,
        providerDirectoryId: providerDirectoryId,
        providerName: providerName,
        category: category,
        requestDescription: requestDescription,
        rejectedBy: rejectedBy,
        serviceScheduledAt: serviceScheduledAt,
        serviceDurationMinutes: serviceDurationMinutes,
        appointmentId: appointmentId,
        createdAt: createdAt,
        paymentPixPayload: paymentPixPayload,
        paymentAmountCents: paymentAmountCents,
        paymentRequestedAt: paymentRequestedAt,
        paymentPaidAt: paymentPaidAt,
        archivedByClient: archivedByClient,
        archivedByProvider: archivedByProvider,
        revisionNumber: revisionNumber,
      );
}
