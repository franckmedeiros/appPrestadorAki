import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
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
  required BuildContext context,
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
    footer: _footerFor(context, listing),
    onTap: onTap,
  );
}

Widget _footerFor(BuildContext context, ProviderListing listing) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      StarRatingBar(rating: listing.ratingAverage, count: listing.ratingCount, starSize: 18),
      if ((listing.whatsapp ?? '').trim().isNotEmpty) ...[
        const SizedBox(height: 6),
        InkWell(
          onTap: () => _abrirWhatsapp(context, listing.whatsapp!),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.chat_bubble, size: 15, color: Color(0xFF25D366)),
              const SizedBox(width: 4),
              Text(
                listing.whatsapp!.trim(),
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ],
          ),
        ),
      ],
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

/// Numero do WhatsApp so aparece no card (ver acima) pra quem assina de
/// verdade - pedido do Franck. Abre direto na conversa via link
/// https://wa.me/... (funciona com ou sem o WhatsApp instalado: com o
/// app, abre nele; sem, cai no WhatsApp Web) - por isso nao precisa
/// nenhuma configuracao nativa extra no Android/iOS, so o pacote
/// url_launcher.
Future<void> _abrirWhatsapp(BuildContext context, String whatsappLocal) async {
  final digits = whatsappLocal.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return;
  // Numero guardado no formato local brasileiro (DDD + numero, sem
  // "55") - ver MaskTextInputFormatter('(##) #####-####') em
  // EditProfileScreen. Se por algum motivo ja vier com o "55" na frente
  // (ex.: cadastro futuro que inclua o pais), nao duplica.
  final comCodigoDoPais = digits.startsWith('55') ? digits : '55$digits';
  final uri = Uri.parse('https://wa.me/$comCodigoDoPais');
  final abriu = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!abriu && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Não foi possível abrir o WhatsApp.')),
    );
  }
}
