import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/api_exception.dart';
import '../../core/app_theme.dart';
import '../../core/auth_controller.dart';
import '../../core/text_normalize.dart';
import '../../widgets/biometric_offer_card.dart';
import '../../widgets/notification_bell.dart';
import '../../widgets/service_category_field.dart';
import 'client_auth_gate.dart';
import 'favorites_controller.dart';
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

/// Resultado de uma tentativa de descobrir a cidade atual via GPS —
/// [city] vem preenchido (já casado com a lista de cidades conhecidas, ou
/// o nome bruto detectado se não bater com nenhuma) quando dá certo;
/// [errorMessage] vem preenchido quando falha, pronto pra mostrar na UI.
/// Nunca os dois ao mesmo tempo.
typedef _LocationLookup = ({String? city, String? errorMessage});

class _ClientHomeScreenState extends State<ClientHomeScreen> {
  ServiceCategory? _category;
  String? _city;
  late Future<List<String>> _citiesFuture;
  bool _locating = false;
  bool _autoLocationAttempted = false;
  late Future<List<ProviderListing>> _future;

  // Mesma ideia do DashboardScreen (lado do prestador): oferece ativar a
  // biometria com um cartão fixo, não um dialog — aqui do lado do
  // cliente, que antes não tinha NENHUM jeito de ativar isso fora do
  // checkbox do cadastro (ver BiometricOfferCard/RegisterScreen). Só faz
  // sentido pra quem já está logado de fato (um convidado navegando livre
  // por aqui não tem sessão nenhuma pra "destravar" depois).
  bool? _biometricAvailable;
  bool _dismissedBiometricOffer = false;

  @override
  void initState() {
    super.initState();
    _checkBiometricAvailability();
    // FavoritesController é compartilhado com MyFavoritesScreen/
    // ProviderPublicProfileScreen — carregar aqui (uma vez por conta
    // logada, ver ensureLoaded) garante que o coração de cada card já
    // nasce certo, sem precisar de nenhum estado próprio desta tela.
    context.read<FavoritesController>().ensureLoaded();
    _future = _search();
    _citiesFuture = context.read<ProviderDirectoryRepository>().listCities();
    // Igual o iFood: tenta preencher a cidade sozinho assim que a tela
    // abre, sem esperar a pessoa tocar em nada — só uma vez (ver
    // `_autoLocationAttempted`), e só se ainda não tem cidade nenhuma
    // escolhida. Essa StatefulShellRoute mantém esta tela viva o tempo
    // todo (ver UnifiedShell), então "só uma vez" aqui já cobre a sessão
    // inteira do app, sem ficar reaparecendo o pedido de permissão toda
    // vez que a pessoa volta pra essa aba.
    _citiesFuture.then((_) => _maybeAutoDetectLocation());
  }

  Future<void> _checkBiometricAvailability() async {
    final available = await context.read<AuthController>().biometricAvailable;
    if (!mounted) return;
    setState(() => _biometricAvailable = available);
  }

  Future<void> _enableBiometrics() async {
    await context.read<AuthController>().setBiometricEnabled(true);
  }

  /// Alterna favorito direto na lista de busca — pede conta na hora (via
  /// `ensureClientAccount`) se quem tocou ainda for um convidado, igual já
  /// acontecia no perfil público. O `FavoritesController` compartilhado
  /// cuida de propagar a mudança pra `MyFavoritesScreen`/perfil público na
  /// hora, sem precisar de nenhum estado próprio aqui.
  Future<void> _toggleFavorite(ProviderListing listing) async {
    final wasGuest = context.read<AuthController>().status != AuthStatus.authenticated;
    if (!await ensureClientAccount(context)) return;
    if (!mounted) return;
    final favorites = context.read<FavoritesController>();
    if (wasGuest) {
      // Quem tocou era convidado até agora. Se a pessoa escolheu "Já tenho
      // conta" (em vez de criar uma nova), essa conta pode já ter
      // favoritos de antes; recarrega antes de decidir favoritar/
      // desfavoritar, senão um prestador já favoritado nessa conta
      // acabaria sendo desfavoritado por engano no primeiro toque.
      await favorites.refresh();
      if (!mounted) return;
    }
    try {
      await favorites.toggle(listing.id);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível atualizar seus favoritos.')),
      );
    }
  }

  Future<List<ProviderListing>> _search() =>
      context.read<ProviderDirectoryRepository>().search(category: _category, city: _city);

  void _runSearch() => setState(() => _future = _search());

  // Extraído pra core/text_normalize.dart (agora reaproveitado também
  // por ProviderDirectoryRepository e pelos seletores de Estado/Cidade —
  // ver widgets/state_city_fields.dart). Mantido aqui como um atalho de
  // instância, só pra não precisar trocar todo `_normalize(...)` abaixo
  // por `normalizeForSearch(...)`.
  String _normalize(String value) => normalizeForSearch(value);

  /// Tenta preencher a cidade sozinho, sem pedir nenhum toque — chamado
  /// uma vez, na abertura da tela (ver `initState`). Silencioso de
  /// propósito: se a pessoa negar a permissão, o serviço de localização
  /// estiver desligado, ou o GPS falhar por qualquer motivo, isso não
  /// mostra nenhum erro — a busca continua em "Todas as cidades" e a
  /// pessoa escolhe manualmente pelo seletor (que também tem "usar minha
  /// localização atual" pra tentar de novo). Um erro logo na abertura do
  /// app, antes de qualquer ação da pessoa, seria mais confuso que útil.
  Future<void> _maybeAutoDetectLocation() async {
    if (_autoLocationAttempted || _city != null || !mounted) return;
    _autoLocationAttempted = true;
    setState(() => _locating = true);
    final result = await _detectCityViaGps();
    if (!mounted) return;
    setState(() {
      _locating = false;
      if (result.city != null) _city = result.city;
    });
    if (result.city != null) _runSearch();
  }

  // Usa o GPS do aparelho pra descobrir a cidade atual — não é busca por
  // proximidade de verdade (isso pediria geohash + índice), só um jeito
  // rápido de não precisar procurar a própria cidade na lista. Devolve o
  // resultado em vez de já aplicar/mostrar snackbar, porque isso é usado
  // tanto pela detecção automática silenciosa (`_maybeAutoDetectLocation`)
  // quanto pelo botão manual dentro do seletor de cidade
  // (`_CityPickerSheet`), que reagem cada um do seu jeito ao resultado.
  Future<_LocationLookup> _detectCityViaGps() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return (city: null, errorMessage: 'Ative a localização do aparelho pra usar isso.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return (
          city: null,
          errorMessage: 'Sem permissão de localização — pode escolher a cidade na lista.',
        );
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
        return (city: null, errorMessage: 'Não conseguimos identificar sua cidade.');
      }
      final detected = placemarks.first.locality ??
          placemarks.first.subAdministrativeArea ??
          placemarks.first.subLocality ??
          '';
      if (detected.isEmpty) {
        return (city: null, errorMessage: 'Não conseguimos identificar sua cidade.');
      }
      // Se a cidade detectada já existe no diretório (ignorando
      // acento/maiúscula), usa o nome exatamente como está gravado —
      // senão a busca por igualdade exata do Firestore não bateria.
      final cities = await _citiesFuture;
      final match = cities.firstWhere(
        (c) => _normalize(c) == _normalize(detected),
        orElse: () => detected,
      );
      return (city: match, errorMessage: null);
    } on TimeoutException {
      return (
        city: null,
        errorMessage: 'A localização demorou demais pra responder. Tente de novo.',
      );
    } catch (e) {
      debugPrint('ClientHomeScreen._detectCityViaGps falhou: $e');
      return (city: null, errorMessage: 'Não foi possível obter sua localização.');
    }
  }

  /// Abre o seletor de cidade (busca por texto + "usar minha localização
  /// atual" + lista completa) — ver `_CityPickerSheet`. Substituiu um
  /// campo `Autocomplete` embutido direto no formulário que, na prática
  /// (relatado em teste real, mais de uma vez), não trocava de cidade de
  /// forma confiável — a combinação de teclado + overlay de sugestões +
  /// estado interno do `Autocomplete` sobrevivendo a rebuilds da tela
  /// (StatefulShellRoute mantém tudo vivo, ver UnifiedShell) tinha
  /// espaço de sobra pra dessincronizar. Um bottom sheet com uma lista
  /// simples de toque é muito mais difícil de deixar preso num estado
  /// inconsistente.
  Future<void> _openCityPicker() async {
    // `_citiesFuture` já terminou a essa altura — `loadingCities` no
    // FutureBuilder abaixo desabilita o toque enquanto ela não resolve —
    // então este `await` é só uma formalidade pra pegar o valor.
    final cities = await _citiesFuture;
    if (!mounted) return;
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _CityPickerSheet(
        cities: cities,
        currentCity: _city,
        normalize: _normalize,
        onUseLocation: _detectCityViaGps,
      ),
    );
    // `null` = fechou o sheet sem escolher nada (voltar, tocar fora) —
    // mantém a cidade que já estava. String vazia é o sentinela usado
    // pra "Todas as cidades" (nomes de cidade nunca são vazios).
    if (result == null || !mounted) return;
    setState(() => _city = result.isEmpty ? null : result);
    _runSearch();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final favoriteIds = context.watch<FavoritesController>().ids;
    final showBiometricOffer = auth.status == AuthStatus.authenticated &&
        _biometricAvailable == true &&
        !auth.biometricEnabled &&
        !_dismissedBiometricOffer;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Encontre um profissional'),
        actions: const [NotificationBell()],
      ),
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
                ServiceCategorySelectorField(
                  label: 'O que você precisa?',
                  initialValue: _category,
                  allowClear: true,
                  onChanged: (value) {
                    setState(() => _category = value);
                    _runSearch();
                  },
                ),
                const SizedBox(height: 8),
                // Campo "de mentira": não digita nada aqui, só abre o
                // seletor de verdade (`_openCityPicker`/`_CityPickerSheet`)
                // ao tocar — ver o comentário em `_openCityPicker` sobre
                // por que isso substituiu um Autocomplete embutido.
                FutureBuilder<List<String>>(
                  future: _citiesFuture,
                  builder: (context, snapshot) {
                    final loadingCities = snapshot.connectionState == ConnectionState.waiting;
                    return InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: loadingCities ? null : _openCityPicker,
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Cidade',
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
                              : const Icon(Icons.arrow_drop_down),
                        ),
                        child: Text(
                          loadingCities ? 'Carregando...' : (_city ?? 'Todas as cidades'),
                          style: TextStyle(color: _city == null ? AppColors.muted : null),
                        ),
                      ),
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
                      onTap: () async {
                        await context.push('/prestador/${listing.id}');
                        // Volta do perfil (onde mora a avaliação, ver
                        // ProviderPublicProfileScreen) e recarrega a busca —
                        // sem isso a nota ficava desatualizada aqui até a
                        // pessoa trocar de filtro ou reabrir a tela.
                        if (mounted) _runSearch();
                      },
                      isFavorite: favoriteIds.contains(listing.id),
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
                onPressed: () => context.push(
                  context.read<AuthController>().status == AuthStatus.authenticated
                      ? '/perfil'
                      : '/welcome',
                ),
                child: const Text('É prestador de serviços? Cadastre-se aqui'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet do seletor de cidade — busca por texto (sem precisar
/// acertar acento/maiúscula, ver `normalize`), "usar minha localização
/// atual" como primeira opção, e a lista completa abaixo. Fecha
/// devolvendo o nome da cidade escolhida, string vazia pra "Todas as
/// cidades", ou `null` se a pessoa voltou/tocou fora sem escolher nada.
class _CityPickerSheet extends StatefulWidget {
  const _CityPickerSheet({
    required this.cities,
    required this.currentCity,
    required this.normalize,
    required this.onUseLocation,
  });

  final List<String> cities;
  final String? currentCity;
  final String Function(String) normalize;
  final Future<_LocationLookup> Function() onUseLocation;

  @override
  State<_CityPickerSheet> createState() => _CityPickerSheetState();
}

class _CityPickerSheetState extends State<_CityPickerSheet> {
  final _searchController = TextEditingController();
  String _query = '';
  bool _locating = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<String> get _filtered {
    if (_query.isEmpty) return widget.cities;
    final query = widget.normalize(_query);
    return widget.cities.where((c) => widget.normalize(c).contains(query)).toList();
  }

  Future<void> _useLocation() async {
    setState(() => _locating = true);
    final result = await widget.onUseLocation();
    if (!mounted) return;
    setState(() => _locating = false);
    if (result.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.errorMessage!)));
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop(result.city);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.muted.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Escolha a cidade',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _searchController,
                decoration: const InputDecoration(labelText: 'Buscar cidade', prefixIcon: Icon(Icons.search)),
                onChanged: (value) => setState(() => _query = value),
              ),
              const SizedBox(height: 12),
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: _locating ? null : _useLocation,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.primary),
                        child: _locating
                            ? const Padding(
                                padding: EdgeInsets.all(10),
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.my_location, color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Usar minha localização atual', style: TextStyle(fontWeight: FontWeight.w700)),
                            SizedBox(height: 2),
                            Text(
                              'Detectamos sua localização automática',
                              style: TextStyle(fontSize: 12, color: AppColors.muted),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: AppColors.primary),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => Navigator.of(context).pop(''),
                child: Row(
                  children: [
                    const Text(
                      'Todas as cidades',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.muted),
                    ),
                    const Spacer(),
                    if (widget.currentCity == null)
                      const Icon(Icons.check, color: AppColors.primary, size: 18),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final city = filtered[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _CityTile(
                        city: city,
                        color: _cityTileColors[index % _cityTileColors.length],
                        selected: city == widget.currentCity,
                        onTap: () => Navigator.of(context).pop(city),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Paleta de cores dos selos redondos da lista de cidades — mesma ideia
/// de `_groupTileColors` em `service_category_field.dart` (gira por
/// índice, só pra dar variedade visual).
const _cityTileColors = <Color>[
  Color(0xFFE7502E), // laranja da marca
  Color(0xFF546E7A), // azul acinzentado
  Color(0xFF00ACC1), // ciano
  Color(0xFF8E24AA), // roxo
  Color(0xFF2E9E5B), // verde
  Color(0xFF1E88E5), // azul
];

/// Linha de cidade no seletor — selo redondo com ícone de prédio, nome em
/// negrito e seta, dentro de um card com borda leve (visual a partir de
/// um mockup que o Franck mandou). Mesmo comportamento de antes (toca
/// pra escolher, ✓ se já é a cidade selecionada); não inventa dado que
/// o app não tem hoje, como estado/UF de cada cidade.
class _CityTile extends StatelessWidget {
  const _CityTile({
    required this.city,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String city;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.primary.withValues(alpha: 0.4) : AppColors.muted.withValues(alpha: 0.15),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.15)),
              child: Icon(Icons.location_city, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                city,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (selected)
              const Icon(Icons.check, color: AppColors.primary, size: 20)
            else
              const Icon(Icons.chevron_right, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}
