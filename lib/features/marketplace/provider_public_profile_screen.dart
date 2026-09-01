import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../core/auth_controller.dart';
import 'client_auth_gate.dart';
import 'favorites_controller.dart';
import 'widgets/provider_listing_card.dart' show abrirWhatsappDoPrestador;
import 'models/provider_listing.dart';
import 'models/provider_rating.dart';
import 'budget_requests_repository.dart';
import 'provider_directory_repository.dart';

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

  // Gamificação por estrelas: só um cliente com pelo menos um orçamento
  // aceito com ESSE prestador pode avaliar (ver
  // BudgetRequestsRepository.hasAcceptedBudgetWith) — evita nota de
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
        await context.read<BudgetRequestsRepository>().hasAcceptedBudgetWith(widget.listingId);
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
    final isFavorite =
        context.watch<FavoritesController>().isFavorite(widget.listingId);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Perfil do profissional'),
        elevation: 0,
      ),
      body: FutureBuilder<ProviderListing?>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final listing = snapshot.data;
          if (listing == null) {
            return const Center(
              child: Text('Este perfil não existe mais.'),
            );
          }

          return Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: AppColors.muted.withValues(alpha: 0.10),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.035),
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
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        listing.name,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 17,
                                          color: AppColors.ink,
                                        ),
                                      ),
                                      if (listing.isVerifiedSubscriber) ...[
                                        const SizedBox(height: 5),
                                        const _VerifiedPill(),
                                      ],
                                      const SizedBox(height: 8),
                                      _ProfileMeta(
                                        icon: Icons.grid_view_rounded,
                                        text: listing.category.label,
                                        primary: true,
                                      ),
                                      const SizedBox(height: 4),
                                      _ProfileMeta(
                                        icon: Icons.location_on_outlined,
                                        text: listing.locationLabel,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),

                            if ((listing.whatsapp ?? '').trim().isNotEmpty) ...[
                              const SizedBox(height: 14),
                              _ProfileActionRow(
                                leading: const _WhatsappContactIcon(),
                                background: AppColors.background,
                                title: listing.whatsapp!.trim(),
                                subtitle: 'Fale pelo WhatsApp',
                                onTap: () => abrirWhatsappDoPrestador(
                                  context,
                                  listing.whatsapp!,
                                ),
                              ),
                            ],

                            const SizedBox(height: 10),
                            _ProfileActionRow(
                              leading: Icon(
                                listing.ratingCount > 0
                                    ? Icons.star_rounded
                                    : Icons.star_outline_rounded,
                                color: AppColors.primary,
                                size: 21,
                              ),
                              background: AppColors.primary
                                  .withValues(alpha: 0.055),
                              title: listing.ratingCount > 0
                                  ? '${listing.ratingAverage.toStringAsFixed(1).replaceAll('.', ',')} (${listing.ratingCount} avaliações)'
                                  : 'Ainda sem avaliações',
                              subtitle: listing.ratingCount > 0
                                  ? 'Veja a reputação deste profissional'
                                  : 'Seja o primeiro a avaliar',
                              onTap: _handleRatingTap,
                            ),

                            const SizedBox(height: 14),
                            Divider(
                              height: 1,
                              color: AppColors.muted.withValues(alpha: 0.16),
                            ),
                            const SizedBox(height: 12),

                            const _SectionLabel(
                              icon: Icons.grid_view_rounded,
                              title: 'Serviços oferecidos',
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                Chip(
                                  label: Text(listing.category.label),
                                  visualDensity: VisualDensity.compact,
                                  backgroundColor: AppColors.background,
                                  side: BorderSide(
                                    color: AppColors.muted
                                        .withValues(alpha: 0.10),
                                  ),
                                ),
                              ],
                            ),

                            if ((listing.bio ?? '').trim().isNotEmpty) ...[
                              const SizedBox(height: 14),
                              Divider(
                                height: 1,
                                color: AppColors.muted
                                    .withValues(alpha: 0.16),
                              ),
                              const SizedBox(height: 12),
                              const _SectionLabel(
                                icon: Icons.person_outline_rounded,
                                title: 'Sobre',
                              ),
                              const SizedBox(height: 8),
                              Text(
                                listing.bio!.trim(),
                                style: const TextStyle(
                                  fontSize: 13,
                                  height: 1.45,
                                  color: AppColors.ink,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),

                      if (!listing.claimed) ...[
                        const SizedBox(height: 12),
                        const _UnclaimedNotice(),
                      ],

                      if (_canRate) ...[
                        const SizedBox(height: 14),
                        Container(
                          key: _ratingSectionKey,
                          child: _RatingForm(
                            stars: _pendingStars,
                            isEditing: _myRating != null,
                            submitting: _submittingRating,
                            commentController: _commentController,
                            onStarsChanged: (value) =>
                                setState(() => _pendingStars = value),
                            onSubmit: _submitRating,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border(
                    top: BorderSide(
                      color: AppColors.muted.withValues(alpha: 0.12),
                    ),
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 48,
                          height: 48,
                          child: Material(
                            color: isFavorite
                                ? AppColors.primary.withValues(alpha: 0.08)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(14),
                            child: InkWell(
                              onTap: _toggleFavorite,
                              borderRadius: BorderRadius.circular(14),
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: isFavorite
                                        ? AppColors.primary
                                            .withValues(alpha: 0.35)
                                        : AppColors.muted
                                            .withValues(alpha: 0.30),
                                  ),
                                ),
                                child: Icon(
                                  isFavorite
                                      ? Icons.favorite_rounded
                                      : Icons.favorite_border_rounded,
                                  color: isFavorite
                                      ? AppColors.primary
                                      : AppColors.muted,
                                  size: 21,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: ElevatedButton.icon(
                              onPressed: () => _requestQuote(listing),
                              icon: const Icon(
                                Icons.send_rounded,
                                size: 17,
                              ),
                              label: const Text(
                                'Solicitar orçamento',
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
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

/// Avatar compacto do profissional.
class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.primaryDark],
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Icon(icon, color: Colors.white, size: 29),
    );
  }
}

class _VerifiedPill extends StatelessWidget {
  const _VerifiedPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_rounded, size: 13, color: AppColors.success),
          SizedBox(width: 4),
          Text(
            'Verificado',
            style: TextStyle(
              color: AppColors.success,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileMeta extends StatelessWidget {
  const _ProfileMeta({
    required this.icon,
    required this.text,
    this.primary = false,
  });

  final IconData icon;
  final String text;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final color = primary ? AppColors.primary : AppColors.muted;
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: primary ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.icon,
    required this.title,
  });

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.primary),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 14,
            color: AppColors.ink,
          ),
        ),
      ],
    );
  }
}

class _WhatsappContactIcon extends StatelessWidget {
  const _WhatsappContactIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: Color(0xFF25D366),
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.phone_rounded,
        color: Colors.white,
        size: 17,
      ),
    );
  }
}

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
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              SizedBox(
                width: 32,
                height: 32,
                child: Center(child: leading),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.primary,
                size: 19,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UnclaimedNotice extends StatelessWidget {
  const _UnclaimedNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFF1C68C).withValues(alpha: 0.65),
        ),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            color: Color(0xFFB7791F),
            size: 19,
          ),
          SizedBox(width: 9),
          Expanded(
            child: Text(
              'Este profissional ainda não usa o PrestadorAki. Sua solicitação fica registrada e ele poderá responder quando criar uma conta.',
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: AppColors.ink,
              ),
            ),
          ),
        ],
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
