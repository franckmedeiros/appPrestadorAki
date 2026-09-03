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
    required this.categories,
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
    // `categories` (lista) é o formato novo — pedido do Franck: "hoje o
    // prestador pode atuar em 2 ou mais categorias... hoje não é possível
    // selecionar mais de uma". Documentos gravados antes dessa mudança só
    // têm o campo singular `category` — tratado aqui como uma lista de
    // um item só, pra continuar funcionando sem precisar de migração/
    // resave em massa (o próprio prestador resolve isso ao salvar o
    // perfil de novo, ver EditProfileScreen).
    final categoriesWire = (data['categories'] as List?)?.cast<String>() ??
        (data['category'] != null ? [data['category'] as String] : const <String>[]);
    return ProviderListing(
      id: doc.id,
      name: data['name'] as String? ?? '',
      categories: categoriesWire.isEmpty
          ? [ServiceCategoryCatalog.outro]
          : categoriesWire.map(serviceCategoryFromWire).toList(),
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

  /// Todas as categorias de serviço em que o prestador atua (ex.:
  /// "Esquadrias de Alumínio" + "Vidraçaria") — pedido do Franck. A
  /// PRIMEIRA da lista é tratada como a "principal" em lugares que só
  /// têm espaço pra uma (ver [category], o ícone do card/avatar).
  final List<ServiceCategory> categories;
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
  /// (ver ProviderListingCard). Null/vazio pra quem nao assina.
  ///
  /// Uma listagem "não reivindicada" (carga inicial, ver comentário da
  /// classe) TAMBÉM pode ter esse campo preenchido — é justamente o que
  /// permite achar essa entrada de novo quando a pessoa finalmente se
  /// cadastra e assina de verdade, casando pelo telefone (não exibido
  /// pro cliente enquanto não reivindicada; ver
  /// `functions/src/subscription.ts`, `reivindicarListagemPorTelefone`).
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

  /// Categoria "principal" (a primeira escolhida) — usada onde só cabe
  /// uma (ícone do avatar do card/perfil). Pra ver TODAS as categorias
  /// (ex.: "Serviços oferecidos" no perfil público, ou a busca por
  /// qualquer uma delas), use [categories].
  ServiceCategory get category => categories.isEmpty ? ServiceCategoryCatalog.outro : categories.first;

  String get locationLabel => state == null || state!.isEmpty ? city : '$city/$state';
}
