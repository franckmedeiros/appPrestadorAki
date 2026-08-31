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
    this.whatsapp,
    this.visible,
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
      whatsapp: data['whatsapp'] as String?,
      visible: data['visible'] as bool?,
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

  /// WhatsApp do prestador (formato local, ex.: "(48) 99999-0000") - so
  /// vem preenchido pro Firestore quando a assinatura esta ativa (ver
  /// ProviderDirectoryRepository.upsertOwnListing e
  /// functions/src/subscription.ts): pedido do Franck pra so mostrar o
  /// contato direto de quem realmente assina, no card de busca/favoritos
  /// (ver ProviderListingCard). Null/vazio pra quem nao assina (inclusive
  /// listagens "nao reivindicadas", que nunca tem esse campo).
  final String? whatsapp;

  /// `visible` cru do Firestore - null pra quem nunca passou pela
  /// assinatura (listagem nao reivindicada, ou reivindicada de antes
  /// dessa coluna existir), true/false pra quem ja passou (ver
  /// functions/src/subscription.ts). Use [isVerifiedSubscriber] em vez
  /// deste campo direto - ele ja aplica a regra certa (null conta como
  /// visivel, ver ProviderDirectoryRepository.search).
  final bool? visible;

  /// Verdadeiro só pra quem tem conta de verdade E assinatura ativa - a
  /// mesma regra que já controla o WhatsApp aparecer no card (ver
  /// upsertOwnListing/subscription.ts). Usado pro selo "Verificado" no
  /// card/perfil - pedido do Franck: reforça o valor de quem paga a
  /// assinatura, não aparece pra listagem "não reivindicada" nem pra
  /// quem deixou a assinatura vencer.
  bool get isVerifiedSubscriber => claimed && visible != false;

  String get locationLabel => state == null || state!.isEmpty ? city : '$city/$state';
}
