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
  ServiceCategory? _category;
  String? _city;
  List<String> _cities = [];
  late Future<List<ProviderListing>> _future;

  @override
  void initState() {
    super.initState();
    _future = _search();
    _loadCities();
  }

  // Lista de cidades pra escolher, em vez de campo de texto livre — ver
  // ProviderDirectoryRepository.listCities(). Carrega em paralelo com a
  // busca inicial; se falhar, o dropdown só fica com "Todas as cidades"
  // (não trava a tela por causa disso).
  Future<void> _loadCities() async {
    try {
      final cities = await context.read<ProviderDirectoryRepository>().listCities();
      if (mounted) setState(() => _cities = cities);
    } catch (_) {
      // busca por categoria continua funcionando mesmo sem a lista de
      // cidades — não é um erro que precise de tela própria.
    }
  }

  Future<List<ProviderListing>> _search() =>
      context.read<ProviderDirectoryRepository>().search(category: _category, city: _city);

  void _runSearch() => setState(() => _future = _search());

  // Remove acentos pra comparar digitação com o nome da cidade sem exigir
  // que o usuário digite certinho (ex.: "sertaozi" ou "Sertãozi" acham
  // "Sertãozinho" do mesmo jeito).
  static const _accented = 'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ';
  static const _plain = 'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC';
  String _normalize(String value) {
    var result = value.toLowerCase();
    for (var i = 0; i < _accented.length; i++) {
      result = result.replaceAll(_accented[i].toLowerCase(), _plain[i].toLowerCase());
    }
    return result;
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
                // Autocomplete em vez de dropdown — igual o campo de
                // cidade do iFood: vai filtrando a lista conforme digita,
                // em vez de abrir tudo pra rolar. Continua escolhendo de
                // uma lista (nunca digita livre), então a busca exata do
                // Firestore continua batendo certinho.
                Autocomplete<String>(
                  initialValue: TextEditingValue(text: _city ?? ''),
                  optionsBuilder: (value) {
                    final query = _normalize(value.text);
                    if (query.isEmpty) return _cities;
                    return _cities.where((c) => _normalize(c).contains(query));
                  },
                  onSelected: (city) {
                    setState(() => _city = city);
                    _runSearch();
                  },
                  fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                    return TextField(
                      controller: controller,
                      focusNode: focusNode,
                      decoration: const InputDecoration(
                        labelText: 'Cidade',
                        hintText: 'Todas as cidades',
                        prefixIcon: Icon(Icons.location_on_outlined),
                      ),
                      onSubmitted: (_) => onFieldSubmitted(),
                      onChanged: (text) {
                        // Limpou o campo à mão (sem escolher uma opção da
                        // lista) — volta a buscar em todas as cidades.
                        if (text.isEmpty && _city != null) {
                          setState(() => _city = null);
                          _runSearch();
                        }
                      },
                    );
                  },
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
                      // A seta fica igual pros dois casos (reivindicado ou
                      // não) — os dois são clicáveis, levam pro perfil
                      // público. O selo "ainda não usa" vai no rodapé do
                      // card (footer), não do lado do título — do lado, o
                      // texto inteiro espremia o nome/categoria/cidade do
                      // prestador (ver histórico); embaixo, com a largura
                      // do card inteiro, cabe numa linha só sem apertar
                      // nada.
                      trailing: const Icon(Icons.chevron_right, color: AppColors.muted),
                      footer: listing.claimed
                          ? null
                          : Align(
                              alignment: Alignment.centerLeft,
                              child: Chip(
                                label: const Text('Ainda não usa o PrestadorAki',
                                    style: TextStyle(fontSize: 10)),
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
