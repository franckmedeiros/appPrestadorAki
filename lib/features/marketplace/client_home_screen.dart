import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:geolocator/geolocator.dart';
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
/// limitações honestas da busca (sem nota média). A busca por localização
/// atual (abaixo) só preenche o campo cidade a partir do GPS — não é busca
/// por proximidade/raio de verdade, isso ainda não existe.
class ClientHomeScreen extends StatefulWidget {
  const ClientHomeScreen({super.key});

  @override
  State<ClientHomeScreen> createState() => _ClientHomeScreenState();
}

class _ClientHomeScreenState extends State<ClientHomeScreen> {
  ServiceCategory? _category;
  String? _city;
  late Future<List<String>> _citiesFuture;
  TextEditingController? _cityFieldController;
  bool _locating = false;
  late Future<List<ProviderListing>> _future;

  @override
  void initState() {
    super.initState();
    _future = _search();
    // Carregado uma vez só, antes do campo de cidade existir de verdade
    // (ver FutureBuilder abaixo) — assim o Autocomplete já nasce com a
    // lista pronta. Antes disso era um campo separado (_cities) atualizado
    // por setState depois que a tela já tinha montado, e o Autocomplete
    // não percebia a lista chegar no meio da digitação (só reavalia
    // opções quando o TEXTO muda, não quando `_cities` muda sozinho) —
    // por isso a lista "não vinha carregada" ao digitar.
    _citiesFuture = context.read<ProviderDirectoryRepository>().listCities();
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

  // Categorias em ordem alfabética pelo rótulo — "Outro" sempre por
  // último, como opção coringa, independente de onde caia no alfabeto.
  List<ServiceCategory> get _sortedCategories {
    final list = ServiceCategory.values.where((c) => c != ServiceCategory.outro).toList()
      ..sort((a, b) => a.label.compareTo(b.label));
    return [...list, ServiceCategory.outro];
  }

  // Usa o GPS do aparelho pra descobrir a cidade atual e já preencher o
  // filtro — não é busca por proximidade de verdade (isso pediria
  // geohash + índice), só um jeito rápido de não precisar digitar/rolar
  // pra achar a própria cidade.
  Future<void> _useCurrentLocation() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _locating = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Ative a localização do aparelho pra usar isso.')),
        );
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Sem permissão de localização — pode escolher a cidade na lista.'),
          ),
        );
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.low),
      );
      final placemarks = await geocoding.placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (placemarks.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Não conseguimos identificar sua cidade.')),
        );
        return;
      }
      final detected = placemarks.first.locality ?? placemarks.first.subAdministrativeArea ?? '';
      if (detected.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Não conseguimos identificar sua cidade.')),
        );
        return;
      }
      // Se a cidade detectada já existe no diretório (ignorando
      // acento/maiúscula), usa o nome exatamente como está gravado —
      // senão a busca por igualdade exata do Firestore não bateria.
      final cities = await _citiesFuture;
      final match = cities.firstWhere(
        (c) => _normalize(c) == _normalize(detected),
        orElse: () => detected,
      );
      _cityFieldController?.text = match;
      setState(() => _city = match);
      _runSearch();
      if (!cities.contains(match)) {
        messenger.showSnackBar(
          SnackBar(content: Text('Ainda não temos prestadores em $match.')),
        );
      }
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Não foi possível obter sua localização.')),
      );
    } finally {
      if (mounted) setState(() => _locating = false);
    }
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
                    ..._sortedCategories.map((c) => DropdownMenuItem(value: c, child: Text(c.label))),
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
                // Firestore continua batendo certinho. Fica dentro de um
                // FutureBuilder pra só existir depois que a lista de
                // cidades já chegou (ver nota em _citiesFuture).
                FutureBuilder<List<String>>(
                  future: _citiesFuture,
                  builder: (context, snapshot) {
                    final cities = snapshot.data ?? const <String>[];
                    final loadingCities =
                        snapshot.connectionState == ConnectionState.waiting;
                    return Autocomplete<String>(
                      initialValue: TextEditingValue(text: _city ?? ''),
                      optionsBuilder: (value) {
                        final query = _normalize(value.text);
                        if (query.isEmpty) return cities;
                        return cities.where((c) => _normalize(c).contains(query));
                      },
                      onSelected: (city) {
                        setState(() => _city = city);
                        _runSearch();
                      },
                      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                        _cityFieldController = controller;
                        return TextField(
                          controller: controller,
                          focusNode: focusNode,
                          enabled: !loadingCities,
                          decoration: InputDecoration(
                            labelText: 'Cidade',
                            hintText: loadingCities ? 'Carregando...' : 'Todas as cidades',
                            prefixIcon: const Icon(Icons.location_on_outlined),
                            suffixIcon: _locating
                                ? const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                  )
                                : IconButton(
                                    tooltip: 'Usar minha localização atual',
                                    icon: const Icon(Icons.my_location),
                                    onPressed: loadingCities ? null : _useCurrentLocation,
                                  ),
                          ),
                          onSubmitted: (_) => onFieldSubmitted(),
                          onChanged: (text) {
                            // Limpou o campo à mão (sem escolher uma opção
                            // da lista) — volta a buscar em todas as
                            // cidades.
                            if (text.isEmpty && _city != null) {
                              setState(() => _city = null);
                              _runSearch();
                            }
                          },
                        );
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
