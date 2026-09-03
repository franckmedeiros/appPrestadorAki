import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/app_theme.dart';
import '../models/provider_listing.dart';
import '../models/service_category.dart';

/// Card de listagem de um [ProviderListing], compartilhado entre a busca
/// (ClientHomeScreen) e Meus favoritos (MyFavoritesScreen).
///
/// Só informativo por decisão do Franck: uma versão anterior tinha a
/// caixa de destaque fixa ("Profissional especializado" + nota) e um
/// rodapé com WhatsApp/"Enviar proposta" (ver histórico do git), mas
/// ficou "carregado" demais - ele preferiu tirar as duas coisas do card
/// e detalhar mais a tela de perfil (ver ProviderPublicProfileScreen),
/// que já concentra contato, avaliação e orçamento. O card virou só a
/// porta de entrada pro perfil (ou favoritar direto, sem abrir nada).
Widget providerListingCard({
  required ProviderListing listing,
  required VoidCallback onTap,
  required bool isFavorite,
  required VoidCallback onToggleFavorite,
}) {
  return Card(
    margin: EdgeInsets.zero,
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _CardAvatar(icon: listing.category.icon),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 2,
                            children: [
                              Text(
                                listing.name,
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (listing.isVerifiedSubscriber) const _VerifiedBadge(),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.grid_view_rounded, size: 13, color: AppColors.primary),
                              const SizedBox(width: 5),
                              Flexible(
                                // Todas as categorias, não só a
                                // "principal" — pedido do Franck: um
                                // prestador em 2+ categorias (ex.:
                                // "Esquadrias de Alumínio" e
                                // "Vidraçaria") precisa aparecer com as
                                // duas aqui, não só a primeira escolhida.
                                child: Text(
                                  listing.categories.map((c) => c.label).join(', '),
                                  style: const TextStyle(color: AppColors.muted, fontSize: 13),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              const Icon(Icons.location_on_outlined, size: 13, color: AppColors.muted),
                              const SizedBox(width: 5),
                              Flexible(
                                child: Text(
                                  listing.locationLabel,
                                  style: const TextStyle(color: AppColors.muted, fontSize: 13),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.muted.withValues(alpha: 0.3)),
                          ),
                          child: IconButton(
                            onPressed: onToggleFavorite,
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                            icon: Icon(
                              isFavorite ? Icons.favorite : Icons.favorite_border,
                              color: isFavorite ? AppColors.primary : AppColors.muted,
                              size: 20,
                            ),
                            tooltip: isFavorite ? 'Remover dos favoritos' : 'Favoritar',
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 24,
                          margin: const EdgeInsets.symmetric(horizontal: 6),
                          color: AppColors.muted.withValues(alpha: 0.2),
                        ),
                        const Icon(Icons.chevron_right, color: AppColors.muted),
                      ],
                    ),
                  ],
                ),
                if (!listing.claimed) ...[
                  const SizedBox(height: 10),
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
            ),
          ),
        ],
      ),
    ),
  );
}

/// Avatar do card — maior que o `AppListCard.iconAvatar` compartilhado
/// (usado em Orçamentos/Solicitações, que tem menos espaço de sobra),
/// pra chegar mais perto da proporção do mockup que o Franck mandou
/// nessa tela específica de busca.
class _CardAvatar extends StatelessWidget {
  const _CardAvatar({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 62,
      height: 62,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.primaryDark],
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Icon(icon, color: Colors.white, size: 30),
    );
  }
}

/// Selo "Verificado" - só pra quem tem conta de verdade com assinatura
/// ativa (ver [ProviderListing.isVerifiedSubscriber]) - reforça o valor
/// de quem paga a assinatura, pedido do Franck.
class _VerifiedBadge extends StatelessWidget {
  const _VerifiedBadge();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.verified, size: 15, color: AppColors.success),
        SizedBox(width: 3),
        Text(
          'Verificado',
          style: TextStyle(color: AppColors.success, fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

/// Número do WhatsApp só aparece pra quem assina de verdade - pedido do
/// Franck. Publica (sem "_") porque também é usada no perfil público
/// (ver ProviderPublicProfileScreen), não só aqui no card. Abre direto
/// na conversa via link https://wa.me/... (funciona com ou sem o
/// WhatsApp instalado: com o app, abre nele; sem, cai no WhatsApp Web) -
/// por isso não precisa nenhuma configuração nativa extra no
/// Android/iOS, só o pacote url_launcher.
Future<void> abrirWhatsappDoPrestador(BuildContext context, String whatsappLocal) async {
  final digits = whatsappLocal.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return;
  // Número guardado no formato local brasileiro (DDD + número, sem
  // "55") - ver MaskTextInputFormatter('(##) #####-####') em
  // EditProfileScreen. Se por algum motivo já vier com o "55" na frente
  // (ex.: cadastro futuro que inclua o país), não duplica.
  final comCodigoDoPais = digits.startsWith('55') ? digits : '55$digits';
  final uri = Uri.parse('https://wa.me/$comCodigoDoPais');
  final abriu = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!abriu && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Não foi possível abrir o WhatsApp.')),
    );
  }
}

/// Selo redondo verde com um telefone branco dentro - usado no perfil
/// público (ver ProviderPublicProfileScreen) ao lado do número.
class WhatsappBadge extends StatelessWidget {
  const WhatsappBadge({super.key, this.size = 18});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(color: Color(0xFF25D366), shape: BoxShape.circle),
      child: FaIcon(FontAwesomeIcons.whatsapp, size: size * 0.55, color: Colors.white),
    );
  }
}
