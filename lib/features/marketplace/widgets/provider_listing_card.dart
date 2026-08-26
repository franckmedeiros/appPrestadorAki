import 'package:flutter/material.dart';
import '../../../core/app_theme.dart';
import '../../../widgets/app_list_card.dart';
import '../models/provider_listing.dart';

/// Card de listagem de um [ProviderListing], compartilhado entre a busca
/// (ClientHomeScreen) e Meus favoritos (MyFavoritesScreen) — antes cada
/// tela montava o card na mão, e só a busca mostrava o selo de "ainda não
/// usa o PrestadorAki" (favoritos ficava sem esse aviso). Reunir num lugar
/// só evita as duas telas divergirem de novo agora que também precisam
/// mostrar a nota média (gamificação) e o selo de Destaque (plano pago).
AppListCard providerListingCard({
  required ProviderListing listing,
  required VoidCallback onTap,
}) {
  return AppListCard(
    leading: AppListCard.iconAvatar(listing.category.icon),
    title: listing.name,
    subtitle: '${listing.category.label} · ${listing.locationLabel}',
    // A seta fica igual pros dois casos (reivindicado ou não) — os dois
    // são clicáveis, levam pro perfil público.
    trailing: const Icon(Icons.chevron_right, color: AppColors.muted),
    // Nota média só aparece quando já existe pelo menos uma avaliação —
    // um prestador novo com "0.0 (0)" pareceria mal avaliado, quando na
    // verdade só ainda não foi avaliado (ver ProviderPublicProfileScreen,
    // que já distingue os dois casos).
    stats: listing.ratingCount > 0
        ? [
            AppListCardStat(
              icon: Icons.star_rounded,
              value: '${listing.ratingAverage.toStringAsFixed(1)} (${listing.ratingCount})',
              color: Colors.amber[700],
            ),
          ]
        : const [],
    // Selo de Destaque e selo de "ainda não usa" nunca aparecem juntos —
    // só um prestador com conta (claimed) pode estar em Destaque (ver
    // ProviderListing.isFeatured e scripts/set_provider_plan.js), então
    // os dois casos são mutuamente exclusivos por natureza dos dados, não
    // por uma escolha arbitrária de exibição.
    footer: _footerFor(listing),
    onTap: onTap,
  );
}

Widget? _footerFor(ProviderListing listing) {
  if (listing.isFeatured) {
    return const Align(
      alignment: Alignment.centerLeft,
      child: Chip(
        avatar: Icon(Icons.star, size: 14, color: Colors.white),
        label: Text('Destaque',
            style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w700)),
        backgroundColor: Color(0xFFB8860B),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
  if (!listing.claimed) {
    return const Align(
      alignment: Alignment.centerLeft,
      child: Chip(
        label: Text('Ainda não usa o PrestadorAki', style: TextStyle(fontSize: 10)),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
  return null;
}
