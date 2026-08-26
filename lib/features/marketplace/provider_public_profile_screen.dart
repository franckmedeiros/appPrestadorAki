import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../core/auth_controller.dart';
import 'client_auth_gate.dart';
import 'favorites_repository.dart';
import 'models/provider_listing.dart';
import 'models/service_category.dart';
import 'provider_directory_repository.dart';

/// Perfil público de um prestador do marketplace — visto pelo cliente,
/// seja um perfil "reivindicado" (com conta no PrestadorAki) ou "não
/// reivindicado" (carga inicial/curadoria manual).
///
/// Depois da mudança de ideia, esta tela é aberta pra QUALQUER UM, sem
/// conta — só as duas ações (favoritar, solicitar orçamento) pedem login/
/// cadastro na hora, via `ensureClientAccount` (ver client_auth_gate.dart).
class ProviderPublicProfileScreen extends StatefulWidget {
  const ProviderPublicProfileScreen({super.key, required this.listingId});

  final String listingId;

  @override
  State<ProviderPublicProfileScreen> createState() => _ProviderPublicProfileScreenState();
}

class _ProviderPublicProfileScreenState extends State<ProviderPublicProfileScreen> {
  late Future<ProviderListing?> _future;
  bool _isFavorite = false;

  @override
  void initState() {
    super.initState();
    _future = context.read<ProviderDirectoryRepository>().get(widget.listingId);
    _checkFavorite();
  }

  Future<void> _checkFavorite() async {
    final auth = context.read<AuthController>();
    // Convidado (ou prestador logado) nunca tem um `clients/{uid}` pra
    // consultar — não adianta nem tentar, e evita um erro de "sem sessão"
    // ao ler o Firestore.
    if (auth.status != AuthStatus.authenticated || auth.role != AccountRole.client) return;
    final isFav = await context.read<FavoritesRepository>().isFavorite(widget.listingId);
    if (mounted) setState(() => _isFavorite = isFav);
  }

  Future<void> _toggleFavorite() async {
    if (!await ensureClientAccount(context)) return;
    if (!mounted) return;
    final favorites = context.read<FavoritesRepository>();
    if (_isFavorite) {
      await favorites.remove(widget.listingId);
    } else {
      await favorites.add(widget.listingId);
    }
    if (mounted) setState(() => _isFavorite = !_isFavorite);
  }

  Future<void> _requestQuote(ProviderListing listing) async {
    if (!await ensureClientAccount(context)) return;
    if (!mounted) return;
    context.push('/solicitar/${listing.id}', extra: listing);
  }

  @override
  Widget build(BuildContext context) {
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
          return Padding(
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
                const Spacer(),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _toggleFavorite,
                        icon: Icon(_isFavorite ? Icons.favorite : Icons.favorite_border),
                        label: Text(_isFavorite ? 'Favoritado' : 'Favoritar'),
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
              ],
            ),
          );
        },
      ),
    );
  }
}
