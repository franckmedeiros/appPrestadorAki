import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../core/auth_controller.dart';
import '../core/notification_service.dart';
import 'app_shell_scaffold.dart';

/// Casca única do app depois da conta unificada (decisão combinada com o
/// Franck: uma conta pode ser cliente E prestador ao mesmo tempo, não mais
/// OU um OU outro — ver AuthController). Substitui os dois shells antigos
/// (AppShell/ClientShell).
///
/// A árvore de rotas sempre tem 6 branches fixos (Buscar/Favoritos/
/// Solicitações/Dashboard/Perfil/Conversas — StatefulShellRoute exige uma
/// lista estática), mas a barra mostra SUBCONJUNTOS diferentes conforme a
/// conta tenha ou não a capacidade de prestador:
///
///   prestador -> Buscar · Conversas · Gerenciamento · Perfil
///   cliente   -> Buscar · Favoritos · Solicitações · Conversas · Perfil
///
/// Por isso o índice "de exibição" (posição na barra) e o índice real do
/// branch não coincidem: `branches` é a tradução de um pro outro, e o
/// redirect do go_router continua impedindo que `/dashboard` seja
/// alcançado por quem não é prestador (ver app_router.dart).
class UnifiedShell extends StatelessWidget {
  const UnifiedShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _searchItem =
      AppNavItem(icon: Icons.search_outlined, selectedIcon: Icons.search, label: 'Buscar');
  static const _favoritesItem =
      AppNavItem(icon: Icons.favorite_border, selectedIcon: Icons.favorite, label: 'Favoritos');
  // "Solicitações", não mais "Meus orçamentos": a barra passou a mostrar
  // o rótulo embaixo do ícone (ver AppShellScaffold), e o nome antigo não
  // cabe — vira reticências numa tela de 5 abas. O nome curto ainda
  // resolve a confusão que o antigo evitava na marra: o prestador tem um
  // "Orçamentos" próprio no Painel, e a mesma conta pode ver os dois
  // (conta unificada, ver comentário da classe).
  static const _requestsItem = AppNavItem(
      icon: Icons.list_alt_outlined, selectedIcon: Icons.list_alt, label: 'Solicitações');
  // "Gerenciamento" continua: cheguei a encurtar pra "Painel" achando que
  // não caberia com o rótulo embaixo do ícone, mas o mockup que o Franck
  // aprovou mostra o nome inteiro na barra, e em 9,5px ele cabe.
  //
  // NÃO virou "Serviços" (como o primeiro mockup sugeria), de propósito:
  // já existe uma tela "Serviços" de verdade — o quadro de trabalhos em
  // andamento, alcançado a partir desta. Duas coisas diferentes com o
  // mesmo nome seria pior que um nome comprido.
  static const _dashboardItem = AppNavItem(
      icon: Icons.dashboard_outlined, selectedIcon: Icons.dashboard, label: 'Gerenciamento');
  static const _profileItem =
      AppNavItem(icon: Icons.person_outline, selectedIcon: Icons.person, label: 'Perfil');
  static const _chatItem = AppNavItem(
      icon: Icons.chat_bubble_outline, selectedIcon: Icons.chat_bubble, label: 'Conversas');

  // Índices dos branches na árvore de rotas (ver app_router.dart). A ordem
  // lá é fixa e não pode ser mexida sem renumerar tudo, então "Conversas"
  // é o 5 mesmo aparecendo no meio da barra.
  static const _buscarBranch = 0;
  static const _favoritosBranch = 1;
  static const _solicitacoesBranch = 2;
  static const _dashboardBranch = 3;
  static const _perfilBranch = 4;
  static const _conversasBranch = 5;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final isProvider = auth.isProvider;
    // Antes isso só rodava dentro de ClientHomeScreen (aba "Buscar") —
    // então um prestador que abrisse o app direto no Dashboard e nunca
    // tocasse em "Buscar" nunca tinha o token FCM salvo, e por isso nunca
    // recebia o push de "novo pedido de orçamento" com som nenhum (só a
    // entrada na central de notificações, gravada à parte no Firestore
    // pela Cloud Function, aparecia). Aqui em UnifiedShell roda pra
    // QUALQUER aba, já que toda conta logada passa por essa casca — e
    // `NotificationService.init()` já é seguro de chamar toda hora que
    // o shell reconstrói (só faz efeito na primeira, ver `_started`).
    // Convidado sem conta (a aba "Buscar" é livre pra visitante) não
    // tem UID nenhum pra salvar token, então segue sem pedir permissão.
    if (auth.status == AuthStatus.authenticated) {
      NotificationService.instance.init();
    }
    // A barra mostra coisas diferentes conforme a conta (pedido do Franck,
    // 28/09): "se eu sou prestador, não precisa aparecer o Favoritos e
    // Solicitações — essas informações só aparecem pro cliente".
    //
    // Favoritar prestador e acompanhar pedidos que EU fiz são ações de
    // quem contrata. Pra quem está trabalhando elas competiam por espaço
    // com o que ele usa o dia inteiro. Tirando as duas, "Conversas" entra
    // sem estourar a barra — que era o problema de somar uma sexta aba.
    //
    // Elas continuam existindo como rota: a mesma conta pode contratar
    // alguém (conta unificada, ver AuthController), e nesse caso chega
    // nelas por dentro do app, não pela barra.
    final branches = isProvider
        ? const [_buscarBranch, _conversasBranch, _dashboardBranch, _perfilBranch]
        : const [
            _buscarBranch,
            _favoritosBranch,
            _solicitacoesBranch,
            _conversasBranch,
            _perfilBranch,
          ];
    final items = isProvider
        ? const [_searchItem, _chatItem, _dashboardItem, _profileItem]
        : const [_searchItem, _favoritesItem, _requestsItem, _chatItem, _profileItem];

    // Um prestador PODE estar numa rota que não tem ícone na barra dele
    // (ex.: abriu "Meus pedidos" por dentro do app). Sem o corte pra zero,
    // `items[-1]` derrubaria a tela inteira — é o tipo de crash que só
    // aparece no caminho que ninguém testa.
    final selecionado = branches.indexOf(navigationShell.currentIndex);

    return AppShellScaffold(
      body: navigationShell,
      items: items,
      selectedIndex: selecionado < 0 ? 0 : selecionado,
      onDestinationSelected: (displayIndex) {
        final branchIndex = branches[displayIndex];
        navigationShell.goBranch(
          branchIndex,
          initialLocation: branchIndex == navigationShell.currentIndex,
        );
      },
    );
  }
}
