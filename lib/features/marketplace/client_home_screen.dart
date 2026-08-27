import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/api_exception.dart';
import '../../core/app_theme.dart';
import '../../core/auth_controller.dart';
import '../../widgets/biometric_offer_card.dart';
import 'client_auth_gate.dart';
import 'favorites_repository.dart';
import 'models/provider_listing.dart';
import 'models/service_category.dart';
import 'provider_directory_repository.dart';
import 'widgets/provider_listing_card.dart';

/// Home do lado do cliente — busca no diretório público de prestadores
/// por categoria e cidade, ordenados por nome (ver
/// ProviderDirectoryRepository.search) — a classificação por estrelas
/// aparece em cada card, mas não decide a ordem da lista. A busca por
/// localização atual (abaixo) só preenche o campo cidade a partir do GPS
/// — não é busca por proximidade/raio de verdade, isso ainda não existe.
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

  // Mesma ideia do DashboardScreen (lado do prestador): oferece ativar a
  // biometria com um cartão fixo, não um dialog — aqui do lado do
  // cliente, que antes não tinha NENHUM jeito de ativar isso fora do
  // checkbox do cadastro (ver BiometricOfferCard/RegisterScreen). Só faz
  // sentido pra quem já está logado de fato (um convidado navegando livre
  // por aqui não tem sessão nenhuma pra "destravar" depois).
  bool? _biometricAvailable;
  bool _dismissedBiometricOffer = false;

  // Ids já favoritados pelo cliente logado, pra pintar o coração certo em
  // cada card da lista sem precisar abrir o perfil de cada um — pedido do
  // Franck ("só coloca o coração, que no mercado o pessoal já sabe que é
  // favoritar"). Convidado/prestador nunca tem favoritos pra carregar (ver
  // _loadFavoriteIds), então fica sempre vazio pra eles.
  Set<String> _favoriteIds = {};

  @override
  void initState() {
    super.initState();
    _checkBiometricAvailability();
    _loadFavoriteIds();
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

  Future<void> _checkBiometricAvailability() async {
    final available = await context.read<AuthController>().biometricAvailable;
    if (!mounted) return;
    setState(() => _biometricAvailable = available);
  }

  Future<void> _enableBiometrics() async {
    await context.read<AuthController>().setBiometricEnabled(true);
  }

  Future<void> _loadFavoriteIds() async {
    final auth = context.read<AuthController>();
    if (auth.status != AuthStatus.authenticated || auth.role != AccountRole.client) return;
    final ids = await context.read<FavoritesRepository>().listFavoriteIds();
    if (mounted) setState(() => _favoriteIds = ids);
  }

  /// Alterna favorito direto na lista de busca — pede conta na hora (via
  /// `ensureClientAccount`) se quem tocou ainda for um convidado, igual já
  /// acontecia no perfil público. Atualiza `_favoriteIds` otimisticamente
  /// (sem esperar recarregar a lista inteira).
  Future<void> _toggleFavorite(ProviderListing listing) async {
    final wasGuest = context.read<AuthController>().status != AuthStatus.authenticated;
    if (!await ensureClientAccount(context)) return;
    if (!mounted) return;
    if (wasGuest) {
      // Quem tocou era convidado até agora — `_favoriteIds` ficou vazio
      // esse tempo todo. Se a pessoa escolheu "Já tenho conta" (em vez de
      // criar uma nova), essa conta pode já ter favoritos de antes;
      // recarrega antes de decidir favoritar/desfavoritar, senão um
      // prestador já favoritado nessa conta acabaria sendo desfavoritado
      // por engano no primeiro toque.
      await _loadFavoriteIds();
      if (!mounted) return;
    }
    final favorites = context.read<FavoritesRepository>();
    final isFavorite = _favoriteIds.contains(listing.id);
    try {
      if (isFavorite) {
        await favorites.remove(listing.id);
      } else {
        await favorites.add(listing.id);
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível atualizar seus favoritos.')),
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      if (isFavorite) {
        _favoriteIds.remove(listing.id);
      } else {
        _favoriteIds.add(listing.id);
      }
    });
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
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 12),
        ),
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
      final detected = placemarks.first.locality ??
          placemarks.first.subAdministrativeArea ??
          placemarks.first.subLocality ??
          '';
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
    } on TimeoutException {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('A localização demorou demais pra responder. Tente de novo.'),
        ),
      );
    } catch (e) {
      debugPrint('ClientHomeScreen._useCurrentLocation falhou: $e');
      messenger.showSnackBar(
        const SnackBar(content: Text('Não foi possível obter sua localização.')),
      );
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final showBiometricOffer = auth.status == AuthStatus.authenticated &&
        _biometricAvailable == true &&
        !auth.biometricEnabled &&
        !_dismissedBiometricOffer;

    return Scaffold(
      appBar: AppBar(title: const Text('Encontre um profissional')),
      body: Column(
        children: [
          if (showBiometricOffer)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: BiometricOfferCard(
                onEnable: _enableBiometrics,
                onDismiss: () => setState(() => _dismissedBiometricOffer = true),
              ),
            ),
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
                        // Além de tocar numa sugestão da lista (onSelected
                        // acima), o usuário pode digitar o nome da cidade
                        // inteiro e apertar "concluído"/buscar no teclado —
                        // isso não aciona onSelected (só funciona tocando na
                        // sugestão), então antes desse fix a cidade nunca
                        // mudava nesse caso. Casa o texto digitado (ignorando
                        // acento/maiúscula) com a lista de cidades conhecidas.
                        void trySelectTypedCity() {
                          final query = _normalize(controller.text);
                          if (query.isEmpty) return;
                          final match = cities.firstWhere(
                            (c) => _normalize(c) == query,
                            orElse: () => '',
                          );
                          if (match.isNotEmpty && match != _city) {
                            setState(() => _city = match);
                            _runSearch();
                          }
                        }

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
                          onSubmitted: (_) {
                            trySelectTypedCity();
                            onFieldSubmitted();
                          },
                          onChanged: (text) {
                            // Limpou o campo à mão (sem escolher uma opção
                            // da lista) — volta a buscar em todas as
                            // cidades.
                            if (text.isEmpty && _city != null) {
                              setState(() => _city = null);
                              _runSearch();
                            } else {
                              trySelectTypedCity();
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
                    return providerListingCard(
                      listing: listing,
                      onTap: () => context.push('/prestador/${listing.id}'),
                      isFavorite: _favoriteIds.contains(listing.id),
                      onToggleFavorite: () => _toggleFavorite(listing),
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
