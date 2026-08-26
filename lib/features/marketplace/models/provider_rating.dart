import 'package:cloud_firestore/cloud_firestore.dart';

/// Uma avaliação de cliente sobre um prestador do diretório (coleção
/// `providerDirectory/{listingId}/ratings/{clientUid}` — ver
/// DATA_MODEL.md). O id do documento é sempre o uid de quem avaliou, então
/// cada cliente só pode ter UMA avaliação por prestador — avaliar de novo
/// edita a mesma, nunca duplica (ver ProviderDirectoryRepository.rate).
class ProviderRating {
  ProviderRating({
    required this.clientUid,
    required this.stars,
    this.comment,
    required this.createdAt,
  });

  factory ProviderRating.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return ProviderRating(
      clientUid: doc.id,
      stars: (data['stars'] as num?)?.toInt() ?? 0,
      comment: data['comment'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  final String clientUid;
  final int stars;
  final String? comment;
  final DateTime createdAt;
}
