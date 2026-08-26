import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../core/auth_controller.dart';
import '../../widgets/app_list_card.dart';
import 'client_auth_gate.dart';
import 'favorites_repository.dart';
import 'models/provider_listing.dart';
import 'models/service_category.dart';

class MyFavoritesScreen extends StatefulWidget {
  const MyFavoritesScreen({super.key});

  @override
  State<MyFavoritesScreen> createState() => _MyFavoritesScreenState();
}

class _MyFavoritesScreenState extends State<MyFavoritesScreen> {
  Future<List<ProviderListing>>? _future;

  void _load() {
    final auth = context.read<AuthController>();
    if (auth.status == AuthStatus.authenticated && auth.role == AccountRole.client) {
      _future = context.read<FavoritesRepository>().listResolved();
    }
  }

  Future<void> _reload() async {
    setState(_load);
    await _future;
  }

  Future<void> _signIn() async {
    if (await ensureClientAccount(context) && mounted) setState(_load);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final isClient = auth.status == AuthStatus.authenticated && auth.role == AccountRole.client;
    if (isClient && _future == null) _load();
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
                      return AppListCard(
                        leading: AppListCard.iconAvatar(listing.category.icon),
                        title: listing.name,
                        subtitle: '${listing.category.label} · ${listing.locationLabel}',
                        trailing: const Icon(Icons.chevron_right, color: AppColors.muted),
                        onTap: () => context.push('/prestador/${listing.id}'),
                      );
                    },
                  );
                },
              ),
            ),
    );
  }
}
