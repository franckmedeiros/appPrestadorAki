import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'app_shell_scaffold.dart';

/// Casca do lado do cliente — mesma barra de navegação do AppShell (ver
/// AppShellScaffold), com os destinos do marketplace. "Buscar" é o
/// primeiro item, então vira o círculo flutuante da barra.
class ClientShell extends StatelessWidget {
  const ClientShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _items = [
    AppNavItem(icon: Icons.search_outlined, selectedIcon: Icons.search, label: 'Buscar'),
    AppNavItem(icon: Icons.favorite_border, selectedIcon: Icons.favorite, label: 'Favoritos'),
    AppNavItem(
        icon: Icons.list_alt_outlined, selectedIcon: Icons.list_alt, label: 'Solicitações'),
  ];

  @override
  Widget build(BuildContext context) {
    return AppShellScaffold(
      body: navigationShell,
      items: _items,
      selectedIndex: navigationShell.currentIndex,
      onDestinationSelected: (index) => navigationShell.goBranch(
        index,
        initialLocation: index == navigationShell.currentIndex,
      ),
    );
  }
}
