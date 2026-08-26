import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/api_exception.dart';
import '../../core/app_theme.dart';
import '../../widgets/app_list_card.dart';
import 'models/provider_listing.dart';
import 'models/service_category.dart';
import 'provider_directory_repository.dart';

/// Home do lado do cliente — busca no diretório público de prestadores
/// por categoria e cidade. Ver ProviderDirectoryRepository para as
/// limitações honestas da busca (sem geolocalização, sem nota média).
class ClientHomeScreen extends StatefulWidget {
  const ClientHomeScreen({super.key});

  @override
  State<ClientHomeScreen> createState() => _ClientHomeScreenState();
}

class _ClientHomeScreenState extends State<ClientHomeScreen> {
  final _cityController = TextEditingController();
  ServiceCategory? _category;
  late Future<List<ProviderListing>> _future;

  @override
  void initState() {
    super.initState();
    _future = _search();
  }

  Future<List<ProviderListing>> _search() =>
      context.read<ProviderDirectoryRepository>().search(
            category: _category,
            city: _cityController.text.trim().isEmpty ? null : _cityController.text.trim(),
          );

  void _runSearch() => setState(() => _future = _search());

  @override
  void dispose() {
    _cityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Encontre um profissional')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                DropdownButtonFormField<ServiceCategory?>(
                  initialValue: _category,
                  decoration: const InputDecoration(labelText: 'O que você precisa?'),
                  items: [
                    const DropdownMenuItem<ServiceCategory?>(
                        value: null, child: Text('Todas as categorias')),
                    ...ServiceCategory.values
                        .map((c) => DropdownMenuItem(value: c, child: Text(c.label))),
                  ],
                  onChanged: (value) {
                    setState(() => _category = value);
                    _runSearch();
                  },
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _cityController,
                  decoration: const InputDecoration(
                    labelText: 'Cidade',
                    prefixIcon: Icon(Icons.location_on_outlined),
                  ),
                  onSubmitted: (_) => _runSearch(),
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<ProviderListing>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  final message = snapshot.error is ApiException
                      ? (snapshot.error as ApiException).message
                      : 'Não foi possível buscar prestadores.';
                  return Center(child: Text(message, textAlign: TextAlign.center));
                }
                final listings = snapshot.data ?? [];
                if (listings.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Nenhum prestador encontrado com esses filtros ainda.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.muted),
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: listings.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final listing = listings[index];
                    return AppListCard(
                      leading: AppListCard.iconAvatar(listing.category.icon),
                      title: listing.name,
                      subtitle: '${listing.category.label} · ${listing.locationLabel}',
                      // Emblema de largura fixa em vez de Chip — o texto
                      // ("Ainda não usa o PrestadorAki") é longo, e um Chip
                      // pede sua largura inteira numa linha só, espremendo o
                      // título/subtítulo do prestador até quase sumir. Com
                      // largura fixa e 2 linhas, o resto do card sempre tem
                      // espaço garantido.
                      trailing: listing.claimed
                          ? const Icon(Icons.chevron_right, color: AppColors.muted)
                          : Container(
                              width: 84,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                              decoration: BoxDecoration(
                                color: AppColors.background,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: AppColors.muted.withValues(alpha: 0.4),
                                ),
                              ),
                              child: const Text(
                                'Ainda não\ncadastrado',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 10,
                                  height: 1.2,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.muted,
                                ),
                              ),
                            ),
                      onTap: () => context.push('/prestador/${listing.id}'),
                    );
                  },
                );
              },
            ),
          ),
          // Único jeito de chegar na área do prestador a partir da busca —
          // ver mudança de ideia: procurar continua livre, quem tem um
          // negócio pra oferecer é quem precisa criar conta. Fica no
          // rodapé, discreto, pra não competir com a busca (que é o que a
          // maioria de quem abre o app quer fazer).
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: TextButton(
                onPressed: () => context.push('/welcome'),
                child: const Text('É prestador de serviços? Cadastre-se aqui'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
