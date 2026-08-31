import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../core/auth_controller.dart';
import 'client_auth_gate.dart';
import 'favorites_controller.dart';
import 'widgets/provider_listing_card.dart' show abrirWhatsappDoPrestador, WhatsappBadge;
import 'models/provider_listing.dart';
import 'models/provider_rating.dart';
import 'models/service_category.dart';
import 'provider_directory_repository.dart';
import 'service_requests_repository.dart';

/// Perfil público de um prestador do marketplace — visto pelo cliente,
/// seja um perfil "reivindicado" (com conta no PrestadorAki) ou "não
/// reivindicado" (carga inicial/curadoria manual).
///
/// Depois da mudança de ideia, esta tela é aberta pra QUALQUER UM, sem
/// conta — só as ações que dependem de identidade (favoritar, solicitar
/// orçamento, avaliar) pedem login/cadastro na hora, via
/// `ensureClientAccount` (ver client_auth_gate.dart) ou, no caso da
/// avaliação, simplesmente ficam escondidas pra quem é convidado.
class ProviderPublicProfileScreen extends StatefulWidget {
  const ProviderPublicProfileScreen({super.key, required this.listingId});

  final String listingId;

  @override
  State<ProviderPublicProfileScreen> createState() => _ProviderPublicProfileScreenState();
}

class _ProviderPublicProfileScreenState extends State<ProviderPublicProfileScreen> {
  late Future<ProviderListing?> _future;

  // Gamificação por estrelas: só um cliente com pelo menos um pedido
  // aceito com ESSE prestador pode avaliar (ver
  // ServiceRequestsRepository.hasAcceptedRequestWith) — evita nota de
  // quem nunca contratou. `_myRating` != null vira edição em vez de uma
  // segunda avaliação (ver ProviderDirectoryRepository.rate).
  bool _canRate = false;
  ProviderRating? _myRating;
  int _pendingStars = 0;
  final _commentController = TextEditingController();
  bool _submittingRating = false;
  final _ratingSectionKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _future = context.read<ProviderDirectoryRepository>().get(widget.listingId);
    context.read<FavoritesController>().ensureLoaded();
    _loadRatingContext();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _loadRatingContext() async {
    final auth = context.read<AuthController>();
    if (auth.status != AuthStatus.authenticated) return;
    final canRate =
        await context.read<ServiceRequestsRepository>().hasAcceptedRequestWith(widget.listingId);
    final myRating = await context.read<ProviderDirectoryRepository>().getMyRating(widget.listingId);
    if (!mounted) return;
    setState(() {
      _canRate = canRate;
      _myRating = myRating;
      _pendingStars = myRating?.stars ?? 0;
      _commentController.text = myRating?.comment ?? '';
    });
  }

  Future<void> _toggleFavorite() async {
    if (!await ensureClientAccount(context)) return;
    if (!mounted) return;
    // FavoritesController já notifica quem estiver observando (inclusive
    // esta tela, via `context.watch` no build) — não precisa de setState
    // próprio aqui.
    await context.read<FavoritesController>().toggle(widget.listingId);
  }

  Future<void> _requestQuote(ProviderListing listing) async {
    if (!await ensureClientAccount(context)) return;
    if (!mounted) return;
    context.push('/solicitar/${listing.id}', extra: listing);
  }

  Future<void> _submitRating() async {
    if (_pendingStars == 0) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _submittingRating = true);
    try {
      await context.read<ProviderDirectoryRepository>().rate(
            widget.listingId,
            stars: _pendingStars,
            comment: _commentController.text,
          );
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Avaliação registrada. Obrigado!')));
      setState(() {
        // Recarrega o perfil pra já mostrar a média atualizada.
        _future = context.read<ProviderDirectoryRepository>().get(widget.listingId);
      });
      await _loadRatingContext();
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Não foi possível registrar sua avaliação.')),
      );
    } finally {
      if (mounted) setState(() => _submittingRating = false);
    }
  }

  void _handleRatingTap() {
    if (_canRate) {
      final ctx = _ratingSectionKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
      }
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Você poderá avaliar depois de ter uma solicitação aceita com esse profissional.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isFavorite = context.watch<FavoritesController>().isFavorite(widget.listingId);
    return Scaffold(
      appBar: AppBar(title: const Text('Perfil do profissional')),
      body: FutureBuilder<ProviderListing?>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final listing = snapshot.data;
          if (listing == null) {
            return const Center(child: Text('Este perfil não existe mais.'));
          }
          return Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _ProfileAvatar(icon: listing.category.icon),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Wrap(
                                        crossAxisAlignment: WrapCrossAlignment.center,
                                        spacing: 8,
                                        runSpacing: 4,
                                        children: [
                                          Text(
                                            listing.name,
                                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
                                          ),
                                          if (listing.isVerifiedSubscriber) const _VerifiedPill(),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          const Icon(Icons.grid_view_rounded, size: 14, color: AppColors.primary),
                                          const SizedBox(width: 6),
                                          Flexible(
                                            child: Text(
                                              listing.category.label,
                                              style: const TextStyle(color: AppColors.muted, fontSize: 14),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 3),
                                      Row(
                                        children: [
                                          const Icon(Icons.location_on_outlined, size: 14, color: AppColors.muted),
                                          const SizedBox(width: 6),
                                          Flexible(
                                            child: Text(
                                              listing.locationLabel,
                                              style: const TextStyle(color: AppColors.muted, fontSize: 14),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            if ((listing.whatsapp ?? '').trim().isNotEmpty) ...[
                              const SizedBox(height: 16),
                              _ProfileActionRow(
                                leading: const WhatsappBadge(size: 36),
                                background: AppColors.background,
                                title: listing.whatsapp!.trim(),
                                subtitle: 'Fale pelo WhatsApp',
                                onTap: () => abrirWhatsappDoPrestador(context, listing.whatsapp!),
                              ),
                            ],
                            const SizedBox(height: 10),
                            _ProfileActionRow(
                              leading: Icon(
                                listing.ratingCount > 0 ? Icons.star_rounded : Icons.star_outline_rounded,
                                color: AppColors.primary,
                                size: 22,
                              ),
                              background: AppColors.primary.withValues(alpha: 0.06),
                              title: listing.ratingCount > 0
                                  ? '${listing.ratingAverage.toStringAsFixed(1).replaceAll('.', ',')} (${listing.ratingCount} avaliações)'
                                  : 'Ainda sem avaliações',
                              subtitle: listing.ratingCount > 0
                                  ? 'Média das avaliações dos clientes'
                                  : 'Seja o primeiro a avaliar',
                              onTap: _handleRatingTap,
                            ),
                            const SizedBox(height: 14),
                            const Divider(height: 1),
                            const SizedBox(height: 14),
                            const Row(
                              children: [
                                Icon(Icons.grid_view_rounded, size: 16, color: AppColors.primary),
                                SizedBox(width: 6),
                                Text('Serviços oferecidos', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                Chip(
                                  label: Text(listing.category.label),
                                  backgroundColor: AppColors.background,
                                  side: BorderSide.none,
                                ),
                              ],
                            ),
                            if ((listing.bio ?? '').trim().isNotEmpty) ...[
                              const SizedBox(height: 16),
                              const Divider(height: 1),
                              const SizedBox(height: 14),
                              const Text('Sobre', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                              const SizedBox(height: 6),
                              Text(
                                listing.bio!.trim(),
                                style: const TextStyle(fontSize: 14, height: 1.4, color: AppColors.ink),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (!listing.claimed) ...[
                        const SizedBox(height: 12),
                        const Card(
                          color: Color(0xFFFFF4E5),
                          child: Padding(
                            padding: EdgeInsets.all(12),
                            child: Text(
                              '⚠️ Este profissional ainda não usa o PrestadorAki. Sua '
                              'solicitação fica registrada e, se você convidá-lo, ele '
                              'poderá respondê-la assim que criar a conta.',
                              style: TextStyle(fontSize: 13),
                            ),
                          ),
                        ),
                      ],
                      if (_canRate) ...[
                        const SizedBox(height: 20),
                        Container(
                          key: _ratingSectionKey,
                          child: _RatingForm(
                            stars: _pendingStars,
                            isEditing: _myRating != null,
                            submitting: _submittingRating,
                            commentController: _commentController,
                            onStarsChanged: (value) => setState(() => _pendingStars = value),
                            onSubmit: _submitRating,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: Row(
                    children: [
                      // Só o ícone, sem texto — pedido do Franck: "no
                      // mercado o pessoal já sabe que é favoritar", igual
                      // já ficou nos cards da busca/favoritos.
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.muted.withValues(alpha: 0.4)),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: IconButton(
                          onPressed: _toggleFavorite,
                          tooltip: isFavorite ? 'Remover dos favoritos' : 'Favoritar',
                          icon: Icon(
                            isFavorite ? Icons.favorite : Icons.favorite_border,
                            color: isFavorite ? AppColors.primary : AppColors.muted,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _requestQuote(listing),
                          icon: const Icon(Icons.send_rounded, size: 18),
                          label: const Text('Solicitar orçamento'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Avatar grande do cabeçalho do perfil - mesma linguagem visual do
/// _CardAvatar do card de listagem, só que maior (72x72) pra esta tela
/// ter mais espaço de sobra.
class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.primaryDark],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Icon(icon, color: Colors.white, size: 34),
    );
  }
}

/// Selo "Verificado" em formato de pílula (fundo verde clarinho), pro
/// cabeçalho do perfil - mesmo texto do selo do card de listagem (ver
/// _VerifiedBadge), só que redesenhado pra bater com o mockup desta tela.
class _VerifiedPill extends StatelessWidget {
  const _VerifiedPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified, size: 14, color: AppColors.success),
          SizedBox(width: 4),
          Text('Verificado', style: TextStyle(color: AppColors.success, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// Linha de ação em caixa arredondada (ícone + título/subtítulo + seta) -
/// usada pro contato via WhatsApp e pro resumo de avaliação. Esse
/// contato e essa nota saíram do card de listagem (ver
/// provider_listing_card.dart, decisão do Franck de simplificar o card)
/// e se concentraram aqui, com mais espaço pra detalhar cada um.
class _ProfileActionRow extends StatelessWidget {
  const _ProfileActionRow({
    required this.leading,
    required this.background,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final Widget leading;
  final Color background;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            SizedBox(width: 36, height: 36, child: Center(child: leading)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  Text(subtitle, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.primary, size: 20),
          ],
        ),
      ),
    );
  }
}

/// Formulário de avaliação — 5 estrelas tocáveis + comentário opcional.
/// Serve tanto pra criar quanto pra editar a própria avaliação (ver
/// `isEditing`), nunca cria uma segunda.
class _RatingForm extends StatelessWidget {
  const _RatingForm({
    required this.stars,
    required this.isEditing,
    required this.submitting,
    required this.commentController,
    required this.onStarsChanged,
    required this.onSubmit,
  });

  final int stars;
  final bool isEditing;
  final bool submitting;
  final TextEditingController commentController;
  final ValueChanged<int> onStarsChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.primary.withValues(alpha: 0.06),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isEditing ? 'Sua avaliação' : 'Avalie esse prestador',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text(
              'Você já contratou esse prestador pelo PrestadorAki — conte pra outros '
              'clientes como foi.',
              style: TextStyle(color: AppColors.muted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Row(
              children: List.generate(5, (index) {
                final starIndex = index + 1;
                return IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => onStarsChanged(starIndex),
                  icon: Icon(
                    starIndex <= stars ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: const Color(0xFFB8860B),
                    size: 32,
                  ),
                );
              }),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: commentController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Comentário (opcional)',
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: (stars == 0 || submitting) ? null : onSubmit,
                child: submitting
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(isEditing ? 'Atualizar avaliação' : 'Enviar avaliação'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
