import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../core/date_text_utils.dart';
import '../marketplace/models/provider_listing.dart';
import '../marketplace/models/provider_rating.dart';
import '../marketplace/provider_directory_repository.dart';
import '../marketplace/widgets/star_rating_bar.dart';

/// "Minhas avaliações" — pedido do Franck: "ter a opção no app do
/// prestador ver as suas avaliações". Antes só existia o lado do cliente
/// (`ProviderPublicProfileScreen`, quem navega o marketplace); o próprio
/// prestador não tinha como ver o que os clientes escreveram sobre ele
/// sem sair da própria conta e abrir o perfil público. Reaproveita
/// `ProviderDirectoryRepository.watchRatings` (mesma fonte da tela
/// pública) — o id do documento de avaliações é o uid do prestador (ver
/// `ProviderDirectoryRepository.get`), então não precisa de mais nada
/// além do uid pra abrir esta tela (ver UserProfileScreen).
class MyReviewsScreen extends StatelessWidget {
  const MyReviewsScreen({super.key, required this.providerId, this.listing});

  final String providerId;

  /// Usado só pro resumo (média + total) no topo — pode chegar nulo se
  /// o carregamento do perfil público falhar por algum motivo; a lista
  /// de avaliações em si não depende disso.
  final ProviderListing? listing;

  @override
  Widget build(BuildContext context) {
    final repository = context.read<ProviderDirectoryRepository>();
    return Scaffold(
      appBar: AppBar(title: const Text('Minhas avaliações')),
      body: StreamBuilder<List<ProviderRating>>(
        stream: repository.watchRatings(providerId, limit: 100),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final ratings = snapshot.data ?? const <ProviderRating>[];
          if (ratings.isEmpty) {
            return const _EmptyState();
          }
          final listing = this.listing;
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            itemCount: ratings.length + (listing != null ? 1 : 0),
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              if (listing != null) {
                if (index == 0) return _SummaryCard(listing: listing);
                return _ReviewTile(rating: ratings[index - 1]);
              }
              return _ReviewTile(rating: ratings[index]);
            },
          );
        },
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.listing});

  final ProviderListing listing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.muted.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Text(
            listing.ratingAverage.toStringAsFixed(1),
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: AppColors.ink),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StarRatingBar(rating: listing.ratingAverage, count: listing.ratingCount, starSize: 16),
                const SizedBox(height: 4),
                Text(
                  '${listing.ratingCount} avaliação${listing.ratingCount == 1 ? '' : 'ões'} de clientes',
                  style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({required this.rating});

  final ProviderRating rating;

  @override
  Widget build(BuildContext context) {
    final comment = rating.comment?.trim();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.muted.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  (rating.clientName ?? '').trim().isNotEmpty ? rating.clientName!.trim() : 'Cliente',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: AppColors.ink),
                ),
              ),
              Text(
                formatDateDdMmYyyy(rating.createdAt),
                style: const TextStyle(fontSize: 11, color: AppColors.muted),
              ),
            ],
          ),
          const SizedBox(height: 4),
          StarRatingBar(rating: rating.stars.toDouble(), count: 1, starSize: 14, showCount: false),
          if (comment != null && comment.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              comment,
              style: const TextStyle(fontSize: 13, height: 1.4, color: AppColors.ink),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withValues(alpha: 0.08),
              ),
              child: const Icon(Icons.star_border_rounded, color: AppColors.primary, size: 38),
            ),
            const SizedBox(height: 18),
            const Text(
              'Nenhuma avaliação ainda',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              'Quando um cliente avaliar um serviço seu, a nota e o comentário aparecem aqui.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.muted, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
