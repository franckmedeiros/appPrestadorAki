import 'package:cloud_firestore/cloud_firestore.dart';

class Customer {
  Customer({
    required this.id,
    required this.name,
    this.phone,
    this.whatsapp,
    this.email,
    this.addressCity,
    this.addressState,
    this.clientUid,
  });

  factory Customer.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return Customer(
      id: doc.id,
      name: data['name'] as String? ?? '',
      phone: data['phone'] as String?,
      whatsapp: data['whatsapp'] as String?,
      email: data['email'] as String?,
      addressCity: data['addressCity'] as String?,
      addressState: data['addressState'] as String?,
      clientUid: data['clientUid'] as String?,
    );
  }

  final String id;
  final String name;
  final String? phone;
  final String? whatsapp;
  final String? email;
  final String? addressCity;
  final String? addressState;

  /// uid da conta de cliente do app que originou este cadastro, quando o
  /// cliente foi criado automaticamente a partir de um pedido de
  /// orçamento pelo marketplace (ver `CustomersRepository.findOrCreateForClient`).
  /// Nulo pra clientes cadastrados manualmente (fora do app).
  final String? clientUid;

  String get locationLabel {
    if (addressCity == null) return '';
    if (addressState == null) return addressCity!;
    return '$addressCity/$addressState';
  }
}
