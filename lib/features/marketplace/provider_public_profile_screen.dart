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
import 'models/service_category.dart';
import 'provider_directory_repository.dart';
import 'widgets/star_rating_bar.dart';
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
                      Text(
                        listing.name,
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text('${listing.category.label} · ${listing.locationLabel}',
                          style: const TextStyle(color: AppColors.muted)),
                      if ((listing.whatsapp ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: () => abrirWhatsappDoPrestador(context, listing.whatsapp!),
                          borderRadius: BorderRadius.circular(8),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.chat_bubble, size: 18, color: Color(0xFF25D366)),
                              const SizedBox(width: 6),
                              Text(
                                listing.whatsapp!.trim(),
                                style: const TextStyle(fontSize: 14, color: AppColors.muted),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      StarRatingBar(rating: listing.ratingAverage, count: listing.ratingCount, starSize: 26),
                      if ((listing.bio ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          listing.bio!.trim(),
                          style: const TextStyle(fontSize: 14, height: 1.4),
                        ),
                      ],
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
                        _RatingForm(
                          stars: _pendingStars,
                          isEditing: _myRating != null,
                          submitting: _submittingRating,
                          commentController: _commentController,
                          onStarsChanged: (value) => setState(() => _pendingStars = value),
                          onSubmit: _submitRating,
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
                        child: ElevatedButton(
                          onPressed: () => _requestQuote(listing),
                          child: const Text('Solicitar orçamento'),
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
