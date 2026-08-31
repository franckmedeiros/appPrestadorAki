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
    this.ratingAverage = 0,
    this.ratingCount = 0,
    this.bio,
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
      ratingAverage: (data['ratingAverage'] as num?)?.toDouble() ?? 0,
      ratingCount: (data['ratingCount'] as num?)?.toInt() ?? 0,
      bio: data['bio'] as String?,
    );
  }

  final String id;
  final String name;
  final ServiceCategory category;
  final String city;
  final String? state;
  final bool claimed;
  final String? providerUid;

  /// Média (0-5) e quantidade de avaliações — ver
  /// `ProviderDirectoryRepository.rate`/`getMyRating` e a subcoleção
  /// `ratings` no DATA_MODEL.md. Mantidos como campos agregados no próprio
  /// documento (em vez de somar as avaliações a cada leitura) pra a busca
  /// e os cards de lista não pagarem o preço de ler a subcoleção inteira
  /// toda vez. É essa nota (classificação por estrelas) que decide a
  /// ordem de exibição — ver ProviderDirectoryRepository.search.
  final double ratingAverage;
  final int ratingCount;

  /// "Carta de apresentação" curta que o prestador escreve (com ajuda
  /// opcional de IA — ver ProviderBioAiService/EditProfileScreen), visível
  /// pro cliente no perfil público. Null/vazio pra quem ainda não
  /// preencheu.
  final String? bio;

  String get locationLabel => state == null || state!.isEmpty ? city : '$city/$state';
}
