import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../core/auth_controller.dart';
import 'app_shell_scaffold.dart';

/// Casca única do app depois da conta unificada (decisão combinada com o
/// Franck: uma conta pode ser cliente E prestador ao mesmo tempo, não mais
/// OU um OU outro — ver AuthController). Substitui os dois shells antigos
/// (AppShell/ClientShell).
///
/// A árvore de rotas sempre tem 5 branches fixos (Buscar/Favoritos/
/// Solicitações/Dashboard/Perfil — StatefulShellRoute exige uma lista
/// estática), mas a barra de navegação só MOSTRA a aba "Dashboard" pra
/// quem tem a capacidade de prestador (`auth.isProvider`) — pra quem não
/// tem, ela some da barra (vira 4 abas) e o redirect do go_router nunca
/// deixa a rota `/dashboard` ser alcançada por engano (ver app_router.dart).
/// Por isso o índice "de exibição" (o que aparece na barra) e o índice
/// real do branch podem divergir só nesse caso — `_displayToBranch`/
/// `_branchToDisplay` fazem essa tradução.
class UnifiedShell extends StatelessWidget {
  const UnifiedShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _searchItem =
      AppNavItem(icon: Icons.search_outlined, selectedIcon: Icons.search, label: 'Buscar');
  static const _favoritesItem =
      AppNavItem(icon: Icons.favorite_border, selectedIcon: Icons.favorite, label: 'Favoritos');
  static const _requestsItem = AppNavItem(
      icon: Icons.list_alt_outlined, selectedIcon: Icons.list_alt, label: 'Solicitações');
  static const _dashboardItem = AppNavItem(
      icon: Icons.dashboard_outlined, selectedIcon: Icons.dashboard, label: 'Dashboard');
  static const _profileItem =
      AppNavItem(icon: Icons.person_outline, selectedIcon: Icons.person, label: 'Perfil');

  // Índice fixo do branch "Perfil" na árvore de rotas (ver
  // app_router.dart) — sempre o último dos 5, independente do que aparece
  // na barra.
  static const _profileBranchIndex = 4;

  @override
  Widget build(BuildContext context) {
    final isProvider = context.watch<AuthController>().isProvider;
    final items = isProvider
        ? const [_searchItem, _favoritesItem, _requestsItem, _dashboardItem, _profileItem]
        : const [_searchItem, _favoritesItem, _requestsItem, _profileItem];

    int displayToBranch(int displayIndex) {
      if (!isProvider && displayIndex == items.length - 1) return _profileBranchIndex;
      return displayIndex;
    }

    int branchToDisplay(int branchIndex) {
      if (!isProvider && branchIndex == _profileBranchIndex) return items.length - 1;
      return branchIndex;
    }

    return AppShellScaffold(
      body: navigationShell,
      items: items,
      selectedIndex: branchToDisplay(navigationShell.currentIndex),
      onDestinationSelected: (displayIndex) {
        final branchIndex = displayToBranch(displayIndex);
        navigationShell.goBranch(
          branchIndex,
          initialLocation: branchIndex == navigationShell.currentIndex,
        );
      },
    );
  }
}
