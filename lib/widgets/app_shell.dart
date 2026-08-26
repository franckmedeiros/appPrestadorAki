import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'app_shell_scaffold.dart';

/// Casca do lado do prestador — mesma barra de navegação do ClientShell
/// (ver AppShellScaffold), com os destinos do prestador. "Início" é o
/// primeiro item, então vira o círculo flutuante da barra.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _items = [
    AppNavItem(icon: Icons.home_outlined, selectedIcon: Icons.home, label: 'Início'),
    AppNavItem(icon: Icons.people_outline, selectedIcon: Icons.people, label: 'Clientes'),
    AppNavItem(
        icon: Icons.calendar_month_outlined,
        selectedIcon: Icons.calendar_month,
        label: 'Agenda'),
    AppNavItem(
        icon: Icons.description_outlined, selectedIcon: Icons.description, label: 'Orçamentos'),
    AppNavItem(icon: Icons.inbox_outlined, selectedIcon: Icons.inbox, label: 'Pedidos'),
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
