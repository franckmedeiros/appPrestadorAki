import 'package:cloud_firestore/cloud_firestore.dart';
import 'service_category.dart';

/// Uma entrada no diretório público de prestadores (coleção
/// `providerDirectory`, ver firebase/DATA_MODEL.md). Pode ser um perfil
/// "reivindicado" (prestador de verdade, com conta no PrestadorAki — nesse
/// caso o id do documento é o próprio uid) ou "não reivindicado" (carga
/// inicial/curadoria manual, sem conta ainda, sem `providerUid`).
class ProviderListing {
  ProviderListing({
    required this.id,
    required this.name,
    required this.category,
    required this.city,
    this.state,
    required this.claimed,
    this.providerUid,
  });

  factory ProviderListing.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return ProviderListing(
      id: doc.id,
      name: data['name'] as String? ?? '',
      category: serviceCategoryFromWire(data['category'] as String? ?? 'outro'),
      city: data['city'] as String? ?? '',
      state: data['state'] as String?,
      claimed: data['claimed'] as bool? ?? false,
      providerUid: data['providerUid'] as String?,
    );
  }

  final String id;
  final String name;
  final ServiceCategory category;
  final String city;
  final String? state;
  final bool claimed;
  final String? providerUid;

  String get locationLabel => state == null || state!.isEmpty ? city : '$city/$state';
}
