import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/api_exception.dart';
import '../../core/app_theme.dart';
import '../../widgets/decorative_header.dart';
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

/// Ordem da lista de resultados, escolhida pela pessoa na linha acima da
/// lista (ver `_linhaDeResultados`).
///
/// O mockup que originou essa linha trazia "Mais relevantes". Não existe
/// relevância calculada em lugar nenhum do app, e um rótulo desses
/// promete um critério que ninguém definiu — então as opções aqui são só
/// as que dá pra cumprir com o dado que o diretório já tem.
enum OrdemDaBusca {
  melhorAvaliados('Melhor avaliados'),
  nome('Nome (A-Z)');

  const OrdemDaBusca(this.rotulo);
  final String rotulo;
}

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

  /// Texto do campo "Buscar por nome" — pedido do Franck: além de filtrar
  /// por categoria e cidade, poder procurar um prestador pelo nome direto
  /// na tela principal (quem já conhece o profissional não quer garimpar
  /// a lista inteira).
  ///
  /// Filtra AQUI no app, sobre o resultado que já está na tela, em vez de
  /// refazer a consulta a cada tecla: a busca por categoria/cidade já
  /// baixa os prestadores todos e filtra em Dart (ver
  /// ProviderDirectoryRepository.search), então filtrar por nome também
  /// aqui sai de graça, responde instantaneamente e não gasta leitura no
  /// Firestore a cada letra digitada.
  final _nameController = TextEditingController();
  String _nameQuery = '';

  /// Ordem escolhida na linha de resultados. Aplicada aqui no app, sobre
  /// o que a consulta trouxe — não é um `orderBy` no Firestore. Com o
  /// teto de 60 documentos por busca (ver `_limiteDaBusca` no
  /// repositório), ordenar aqui é barato e evita um índice composto
  /// diferente pra cada combinação de filtro.
  OrdemDaBusca _ordem = OrdemDaBusca.melhorAvaliados;
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

  @override
  void dispose() {
    _debounceNome?.cancel();
    _nameController.dispose();
    super.dispose();
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

  Future<List<ProviderListing>> _search() => context
      .read<ProviderDirectoryRepository>()
      .search(category: _category, city: _city, nome: _nameQuery);

  void _runSearch() => setState(() => _future = _search());

  Timer? _debounceNome;

  /// Espera a pessoa parar de digitar antes de consultar o servidor.
  ///
  /// A busca por nome passou a ser feita no Firestore — antes era no app,
  /// sobre a coleção inteira já baixada, o que deixou de ser viável com
  /// ~9.700 entradas no diretório. Sem esta espera seriam cinco consultas
  /// pra quem digita "pedro", uma por tecla; e a resposta de uma poderia
  /// chegar depois da seguinte e sobrescrever o resultado certo.
  void _aoDigitarNome(String valor) {
    setState(() => _nameQuery = valor);
    _debounceNome?.cancel();
    _debounceNome = Timer(const Duration(milliseconds: 350), () {
      if (mounted) _runSearch();
    });
  }

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
    // então este `await` seria só uma formalidade pra pegar o valor.
    //
    // Só que "terminou" inclui "terminou com erro", e aí o `await`
    // RELANÇA a exceção: o seletor nunca abria e o campo virava um botão
    // morto, sem mensagem nenhuma. Foi o que o Franck viu quando a regra
    // de `meta/cidades` ainda não estava publicada e a leitura era
    // negada. Com o try/catch, uma falha na lista vira uma lista vazia —
    // o seletor abre do mesmo jeito, e de dentro dele ainda dá pra usar a
    // localização atual ou escolher "Todas as cidades".
    List<String> cities;
    try {
      cities = await _citiesFuture;
    } catch (e) {
      cities = const [];
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível carregar a lista de cidades.')),
        );
      }
    }
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
    final showBiometricOffer = auth.status == AuthStatus.authenticated &&
        _biometricAvailable == true &&
        !auth.biometricEnabled &&
        !_dismissedBiometricOffer;

    return Scaffold(
      backgroundColor: AppColors.background,
      // Sem AppBar: o topo virou um bloco de gradiente com título e
      // subtítulo, e o campo de busca "sobe" por cima dele (ver o
      // Transform.translate abaixo). Desenho aprovado pelo Franck a
      // partir de um mockup. É o mesmo `DecorativeHeader` já usado no
      // login, no cadastro e no perfil — a tela principal era a última
      // que ainda tinha uma AppBar comum.
      body: Column(
        children: [
          DecorativeHeader(
            height: 150,
            padding: const EdgeInsets.fromLTRB(20, 4, 12, 40),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Encontre um profissional',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          height: 1.15,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Serviços de qualidade, perto de você.',
                        style: TextStyle(fontSize: 13, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                const NotificationBell(),
              ],
            ),
          ),
          if (showBiometricOffer)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: BiometricOfferCard(
                onEnable: _enableBiometrics,
                onDismiss: () => setState(() => _dismissedBiometricOffer = true),
              ),
            ),
          // O deslocamento negativo é o que faz o campo de busca invadir
          // o gradiente. Só vale quando o convite de biometria não está
          // na frente — com ele no meio, o campo já não encosta no topo.
          Transform.translate(
            offset: Offset(0, showBiometricOffer ? 0 : -28),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: Column(
                children: [
                // Busca por nome — pedido do Franck. Fica em PRIMEIRO
                // lugar de propósito: quem já sabe o nome do profissional
                // não deveria precisar passar por categoria e cidade
                // antes. Filtra na hora, sem tocar no Firestore (ver
                // `_nameQuery`).
                // Cartão branco com sombra em vez do campo comum: é ele
                // que "flutua" sobre o gradiente. Sem rótulo fixo, só o
                // texto de exemplo — o ícone de lupa já diz o que é, e o
                // rótulo roubava uma linha inteira do topo.
                Material(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  elevation: 3,
                  shadowColor: Colors.black26,
                  child: TextField(
                    controller: _nameController,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Buscar pelo nome do profissional',
                      hintStyle: const TextStyle(color: AppColors.muted, fontSize: 14),
                      prefixIcon: const Icon(Icons.search, color: AppColors.muted),
                      filled: true,
                      fillColor: AppColors.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
                      ),
                      suffixIcon: _nameQuery.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close, size: 20, color: AppColors.muted),
                              tooltip: 'Limpar',
                              onPressed: () {
                                _nameController.clear();
                                _aoDigitarNome('');
                              },
                            ),
                    ),
                    onChanged: _aoDigitarNome,
                  ),
                ),
                const SizedBox(height: 10),
                // Categoria e cidade lado a lado (mockup aprovado pelo
                // Franck): antes eram duas linhas empilhadas, e junto com
                // a busca por nome empurravam a lista de prestadores pra
                // fora da primeira dobra no celular.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: ServiceCategorySelectorField(
                        label: 'O que você precisa?',
                        initialValue: _category,
                        allowClear: true,
                        onChanged: (value) {
                          setState(() => _category = value);
                          _runSearch();
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: _campoCidade()),
                  ],
                ),
                const SizedBox(height: 12),
                _linhaDeResultados(),
              ],
            ),
          ),
          ),
          Expanded(child: _listaDeResultados()),
          _rodapeConvitePrestador(),
        ],
      ),
    );
  }

  /// Contagem de resultados + ordenação, na linha logo acima da lista.
  ///
  /// Sobre a ordenação: o mockup trazia "Mais relevantes", que não existe
  /// — não há nenhum cálculo de relevância no app, e inventar um rótulo
  /// desses é prometer um critério que ninguém definiu. Troquei por duas
  /// ordens que a gente consegue cumprir de verdade, com dado que já está
  /// no diretório: nota média e ordem alfabética.
  Widget _linhaDeResultados() {
    return FutureBuilder<List<ProviderListing>>(
      future: _future,
      builder: (context, snapshot) {
        final total = snapshot.data?.length ?? 0;
        // Enquanto carrega, não anuncia "0 profissionais" — seria uma
        // informação errada aparecendo por um instante a cada busca.
        final carregando = snapshot.connectionState == ConnectionState.waiting;
        final ondeLabel = _city ?? 'todas as cidades';
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    carregando
                        ? 'Buscando...'
                        : '$total ${total == 1 ? 'profissional encontrado' : 'profissionais encontrados'}',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  Text(
                    'Resultados para $ondeLabel',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
                  ),
                ],
              ),
            ),
            PopupMenuButton<OrdemDaBusca>(
              initialValue: _ordem,
              tooltip: 'Ordenar',
              onSelected: (valor) => setState(() => _ordem = valor),
              itemBuilder: (context) => [
                for (final ordem in OrdemDaBusca.values)
                  PopupMenuItem(value: ordem, child: Text(ordem.rotulo)),
              ],
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.muted.withValues(alpha: 0.25)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.swap_vert, size: 16, color: AppColors.ink),
                    const SizedBox(width: 5),
                    Text(
                      _ordem.rotulo,
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                    const Icon(Icons.expand_more, size: 16, color: AppColors.muted),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Campo de cidade — "de mentira": não digita nada nele, só abre o
  /// seletor de verdade (`_openCityPicker`/`_CityPickerSheet`) ao tocar.
  /// Virou método próprio quando categoria e cidade passaram a dividir a
  /// mesma linha: o `FutureBuilder` inteiro dentro de um `Expanded` dentro
  /// de um `Row` deixava o `build` ilegível.
  Widget _campoCidade() {
    return FutureBuilder<List<String>>(
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
    );
  }

  /// A lista de resultados. Virou método próprio junto com `_campoCidade`
  /// — o `build` estava com seis níveis de indentação só de estrutura, e
  /// qualquer mexida no topo da tela obrigava a contar parênteses até o
  /// fim do arquivo.
  Widget _listaDeResultados() {
    // Lido aqui, e não recebido por parâmetro: este método roda dentro do
    // `build`, então o `watch` continua valendo — a tela se redesenha
    // sozinha quando o cliente favorita ou desfavorita alguém.
    final favoriteIds = context.watch<FavoritesController>().ids;
    return FutureBuilder<List<ProviderListing>>(
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
                // O filtro por nome agora é feito no SERVIDOR (ver
                // ProviderDirectoryRepository.search) — aqui não sobra
                // nada a filtrar. Antes era um `contains` sobre a
                // coleção inteira baixada no aparelho, o que deixou de
                // ser viável quando o diretório passou de algumas dezenas
                // pra ~9.700 entradas.
                //
                // Junto veio uma mudança de comportamento que vale
                // conhecer: no servidor a comparação é por COMEÇO do
                // nome, não por trecho. "OPOut" acha "OPOutsourcingBr";
                // "sourcing" não acha mais. Um "contém" de verdade
                // exigiria índice invertido, que o Firestore não tem.
                // Ordena aqui, sobre o que veio da consulta (ver `_ordem`).
                // `..sort` numa cópia: a lista do snapshot é reusada a
                // cada rebuild, e ordenar ela no lugar mexeria no cache do
                // Future.
                final listings = [...(snapshot.data ?? const <ProviderListing>[])]
                  ..sort((a, b) => switch (_ordem) {
                        // Empate na nota cai no nome, pra a ordem não
                        // dançar a cada rebuild entre quem tem a mesma
                        // nota (inclusive os muitos que têm zero).
                        OrdemDaBusca.melhorAvaliados =>
                          b.ratingAverage.compareTo(a.ratingAverage) != 0
                              ? b.ratingAverage.compareTo(a.ratingAverage)
                              : a.name.toLowerCase().compareTo(b.name.toLowerCase()),
                        OrdemDaBusca.nome =>
                          a.name.toLowerCase().compareTo(b.name.toLowerCase()),
                      });
                final termo = _nameQuery.trim();
                if (listings.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        // Mensagem diferente quando o vazio veio da busca
                        // por nome: "nenhum com esses filtros" mandaria a
                        // pessoa mexer na categoria/cidade quando o que
                        // ela precisa é conferir o nome digitado.
                        termo.isEmpty
                            ? 'Nenhum prestador encontrado com esses filtros ainda.'
                            : 'Nenhum prestador com "$termo" nos filtros atuais.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.muted),
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
            );
  }

  /// Rodapé fixo da tela — ver o comentário dentro sobre por que ele mora
  /// aqui embaixo e não no topo.
  Widget _rodapeConvitePrestador() {
    return
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
                // `go('/perfil')` (não `push('/welcome')`, como era
                // antes): o push abria a tela de boas-vindas POR CIMA de
                // tudo, em tela cheia, sem a barra de navegação embaixo —
                // o Franck reparou ("mas ele abre a tela fora"). Indo pra
                // aba "Perfil", a pessoa vê a MESMA tela de boas-vindas
                // (é o que UserProfileScreen mostra pra quem não tem
                // conta), só que dentro da casca do app, com a barra de
                // baixo no lugar e a aba certa marcada. Serve pros dois
                // casos sem precisar checar a sessão aqui: quem já tem
                // conta cai no próprio perfil, quem não tem cai nas
                // boas-vindas.
                onPressed: () => context.go('/perfil'),
                child: const Text('É prestador de serviços? Cadastre-se aqui'),
              ),
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
