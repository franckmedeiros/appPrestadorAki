import 'package:flutter/material.dart';
import '../../../core/app_theme.dart';
import '../../../widgets/app_list_card.dart';
import '../models/provider_listing.dart';
import '../models/service_category.dart';
import 'star_rating_bar.dart';

/// Card de listagem de um [ProviderListing], compartilhado entre a busca
/// (ClientHomeScreen) e Meus favoritos (MyFavoritesScreen) — antes cada
/// tela montava o card na mão, e só a busca mostrava o selo de "ainda não
/// usa o PrestadorAki" (favoritos ficava sem esse aviso). Reunir num lugar
/// só evita as duas telas divergirem de novo agora que também precisam
/// mostrar a classificação por estrelas (gamificação) e o coração de
/// favoritar direto no card — pedido do Franck pra não precisar abrir o
/// perfil só pra favoritar/desfavoritar ("no mercado o pessoal já sabe
/// que é favoritar", só o ícone, sem texto).
AppListCard providerListingCard({
  required ProviderListing listing,
  required VoidCallback onTap,
  required bool isFavorite,
  required VoidCallback onToggleFavorite,
}) {
  return AppListCard(
    leading: AppListCard.iconAvatar(listing.category.icon),
    title: listing.name,
    subtitle: '${listing.category.label} · ${listing.locationLabel}',
    // Coração + seta juntos à direita — o coração tem seu próprio toque
    // (favorita ali mesmo, sem abrir o perfil); o resto do card continua
    // levando pro perfil público, igual antes.
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: onToggleFavorite,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          icon: Icon(
            isFavorite ? Icons.favorite : Icons.favorite_border,
            color: isFavorite ? AppColors.primary : AppColors.muted,
          ),
          tooltip: isFavorite ? 'Remover dos favoritos' : 'Favoritar',
        ),
        const Icon(Icons.chevron_right, color: AppColors.muted),
      ],
    ),
    footer: _footerFor(listing),
    onTap: onTap,
  );
}

Widget _footerFor(ProviderListing listing) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      StarRatingBar(rating: listing.ratingAverage, count: listing.ratingCount, starSize: 18),
      if (!listing.claimed) ...[
        const SizedBox(height: 6),
        const Align(
          alignment: Alignment.centerLeft,
          child: Chip(
            label: Text('Ainda não usa o PrestadorAki', style: TextStyle(fontSize: 10)),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ],
    ],
  );
}
