import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../core/auth_controller.dart';
import 'client_auth_gate.dart';
import 'favorites_controller.dart';
import 'favorites_repository.dart';
import 'models/provider_listing.dart';
import 'widgets/provider_listing_card.dart';

class MyFavoritesScreen extends StatefulWidget {
  const MyFavoritesScreen({super.key});

  @override
  State<MyFavoritesScreen> createState() => _MyFavoritesScreenState();
}

class _MyFavoritesScreenState extends State<MyFavoritesScreen> {
  Future<List<ProviderListing>>? _future;

  // Versão do FavoritesController na última vez que recarregamos a lista
  // resolvida — permite perceber que um favorito foi adicionado/removido
  // em OUTRA tela (ex.: coração de um card em "Encontre um profissional")
  // enquanto esta ficava viva no IndexedStack do shell, e recarregar sem
  // precisar de pull-to-refresh manual (bug relatado pelo Franck).
  int? _loadedAtVersion;

  void _load(int version) {
    _future = context.read<FavoritesRepository>().listResolved();
    _loadedAtVersion = version;
  }

  Future<void> _reload() async {
    setState(() => _load(context.read<FavoritesController>().version));
    await _future;
  }

  Future<void> _signIn() async {
    if (await ensureClientAccount(context) && mounted) {
      setState(() => _load(context.read<FavoritesController>().version));
    }
  }

  /// Desfavorita direto da lista (coração preenchido — pedido do Franck
  /// pra não precisar abrir o perfil só pra isso). Como aqui TODO item já
  /// é, por definição, um favorito, só existe o sentido de remover — tira
  /// da lista na hora em vez de esperar um recarregamento inteiro. Passa
  /// pelo FavoritesController (em vez do repositório direto) pra que o
  /// coração nos cards de busca já nasça certo se o usuário voltar pra lá.
  Future<void> _removeFavorite(ProviderListing listing) async {
    try {
      await context.read<FavoritesController>().remove(listing.id);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível remover dos favoritos.')),
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      _future = _future?.then((list) => list.where((l) => l.id != listing.id).toList());
      _loadedAtVersion = context.read<FavoritesController>().version;
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final isClient = auth.status == AuthStatus.authenticated;
    final favoritesVersion = context.watch<FavoritesController>().version;
    if (isClient && (_future == null || _loadedAtVersion != favoritesVersion)) {
      _load(favoritesVersion);
    }
    if (!isClient) _future = null;

    return Scaffold(
      appBar: AppBar(title: const Text('Meus favoritos')),
      body: !isClient
          ? ClientSignInPrompt(
              icon: Icons.favorite_border,
              message: 'Crie uma conta grátis para salvar os prestadores que você mais usa.',
              onPressed: _signIn,
            )
          : RefreshIndicator(
              onRefresh: _reload,
              child: FutureBuilder<List<ProviderListing>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final favorites = snapshot.data ?? [];
                  if (favorites.isEmpty) {
                    return ListView(
                      children: const [
                        SizedBox(height: 80),
                        Icon(Icons.favorite_border, size: 48, color: AppColors.muted),
                        SizedBox(height: 12),
                        Text('Nenhum prestador favoritado ainda.',
                            textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
                      ],
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: favorites.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final listing = favorites[index];
                      return providerListingCard(
                        context: context,
                        listing: listing,
                        onTap: () => context.push('/prestador/${listing.id}'),
                        isFavorite: true,
                        onToggleFavorite: () => _removeFavorite(listing),
                      );
                    },
                  );
                },
              ),
            ),
    );
  }
}
