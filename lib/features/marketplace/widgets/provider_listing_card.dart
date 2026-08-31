import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/app_theme.dart';
import '../client_auth_gate.dart';
import '../models/provider_listing.dart';
import '../models/service_category.dart';

/// Card de listagem de um [ProviderListing], compartilhado entre a busca
/// (ClientHomeScreen) e Meus favoritos (MyFavoritesScreen).
///
/// Redesenhado a partir de um mockup que o Franck mandou (selo
/// "Verificado", caixa de destaque com a "carta de apresentação" (bio) e
/// a nota, rodapé com WhatsApp + atalho direto pra pedir orçamento) -
/// pedido pra tela "Encontre um profissional", mas como o card já era
/// compartilhado com "Meus favoritos" desde antes (ver nota mais antiga
/// abaixo), manter os dois com o mesmo visual evita as telas divergirem
/// de novo. As badges de qualidade do mockup ("Pontual", "Caprichoso"...)
/// ficaram de fora por decisão do Franck - não existe esse dado no app
/// ainda (nem vem de avaliação, nem de cadastro).
Widget providerListingCard({
  required ProviderListing listing,
  required VoidCallback onTap,
  required bool isFavorite,
  required VoidCallback onToggleFavorite,
}) {
  final hasWhatsapp = (listing.whatsapp ?? '').trim().isNotEmpty;

  return Card(
    margin: EdgeInsets.zero,
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
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
                                child: Text(
                                  listing.category.label,
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
                const SizedBox(height: 14),
                const _HighlightBox(),
                if (!listing.claimed) ...[
                  const SizedBox(height: 8),
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
          const Divider(height: 1),
          _ContactFooter(listing: listing, hasWhatsapp: hasWhatsapp),
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

/// Caixa de destaque - conteúdo FIXO (mesmo texto e mesma nota "5,0" pra
/// todo mundo), por pedido explícito do Franck a partir do mockup: ele
/// viu a alternativa (bio real do prestador + "Ainda sem avaliações"
/// quando não há nota de verdade) e preferiu esse texto fixo mesmo assim
/// - inclusive sabendo que a nota "5,0 (0 avaliações)" não reflete dado
/// real nenhum. Se um dia isso incomodar (parecer falso pros clientes,
/// por exemplo), é só trocar de volta pela versão anterior no histórico
/// do git.
class _HighlightBox extends StatelessWidget {
  const _HighlightBox();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.workspace_premium_outlined, size: 19, color: AppColors.primary),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Profissional especializado',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                ),
                SizedBox(height: 2),
                Text(
                  'Serviços de qualidade com acabamento impecável.',
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.star, size: 15, color: AppColors.primary),
                  SizedBox(width: 3),
                  Text('5,0', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.primary)),
                ],
              ),
              SizedBox(height: 2),
              Text('(0 avaliações)', style: TextStyle(fontSize: 10.5, color: AppColors.muted)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Rodapé com os dois atalhos de contato: WhatsApp (só quando tem, ver
/// [ProviderListing.whatsapp]) e "Enviar proposta" (sempre disponível -
/// vai direto pro formulário de orçamento, pulando a tela de perfil, ver
/// RequestQuoteFormScreen/app_router.dart). Sem WhatsApp, o "Enviar
/// proposta" ocupa a largura toda sozinho.
class _ContactFooter extends StatelessWidget {
  const _ContactFooter({required this.listing, required this.hasWhatsapp});

  final ProviderListing listing;
  final bool hasWhatsapp;

  Future<void> _enviarProposta(BuildContext context) async {
    if (!await ensureClientAccount(context)) return;
    if (!context.mounted) return;
    context.push('/solicitar/${listing.id}', extra: listing);
  }

  @override
  Widget build(BuildContext context) {
    final proposta = _FooterAction(
      icon: FontAwesomeIcons.commentDots,
      color: AppColors.primary,
      title: 'Enviar proposta',
      subtitle: 'Peça um orçamento',
      onTap: () => _enviarProposta(context),
      trailing: const Icon(Icons.chevron_right, color: AppColors.muted, size: 18),
    );
    if (!hasWhatsapp) return proposta;

    return IntrinsicHeight(
      child: Row(
        children: [
          Expanded(
            child: _FooterAction(
              icon: FontAwesomeIcons.whatsapp,
              color: const Color(0xFF25D366),
              title: 'Entrar em contato',
              subtitle: 'Fale pelo WhatsApp',
              onTap: () => abrirWhatsappDoPrestador(context, listing.whatsapp!),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: proposta),
        ],
      ),
    );
  }
}

class _FooterAction extends StatelessWidget {
  const _FooterAction({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 19),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  Text(subtitle, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
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
/// público (ver ProviderPublicProfileScreen) ao lado do número, num
/// formato mais discreto que os botões do rodapé acima (que usam
/// [_FooterAction] com ícone quadrado suave em vez deste círculo cheio).
class WhatsappBadge extends StatelessWidget {
  const WhatsappBadge({super.key, this.size = 18});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(color: Color(0xFF25D366), shape: BoxShape.circle),
      child: Icon(FontAwesomeIcons.whatsapp, size: size * 0.55, color: Colors.white),
    );
  }
}
