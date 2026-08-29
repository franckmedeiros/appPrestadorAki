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

/// Orçamento formal (módulo "Orçamentos" — diferente e mais simples do
/// que o "Enviar orçamento" do marketplace, ver IncomingRequestsScreen):
/// pensado pra clientes cadastrados manualmente (ver CustomersRepository),
/// com itens, desconto e observações, no layout do PDF que o Franck
/// mandou de exemplo.
///
/// `customerName`/`addressText` são uma cópia ("snapshot") de quando o
/// orçamento foi criado — de propósito, igual a vários outros lugares do
/// app (ver ServiceRequest.providerName): um orçamento antigo não deve
/// mudar de nome/endereço só porque o cadastro do cliente foi editado
/// depois.
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
      };
}
