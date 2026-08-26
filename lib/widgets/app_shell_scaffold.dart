import 'package:flutter/material.dart';
import '../core/app_theme.dart';

/// Um destino da navegação inferior.
class AppNavItem {
  const AppNavItem({required this.icon, required this.selectedIcon, required this.label});

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// Scaffold compartilhado pelos dois lados do app (AppShell/ClientShell) —
/// mesma barra de navegação nos dois, só muda a lista de destinos.
///
/// Igual à referência do Resenha que o Franck mostrou: não existe um ícone
/// fixo de marca. O círculo flutuante representa a aba atualmente
/// selecionada — mostra o ícone dela e "desliza" pra cima da posição certa
/// na barra conforme o usuário navega. A barra escura por baixo mostra só
/// as abas que não estão selecionadas (a selecionada "sobe" pro círculo).
/// Usa o notch nativo do Flutter (`BottomAppBar` + `CircularNotchedRectangle`)
/// pra recortar o espaço onde o círculo encaixa, em vez de desenhar a curva
/// à mão — mais simples e resistente a mudanças de tamanho de tela.
class AppShellScaffold extends StatelessWidget {
  const AppShellScaffold({
    super.key,
    required this.body,
    required this.items,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final Widget body;
  final List<AppNavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: body,
      floatingActionButton: _BrandFab(icon: items[selectedIndex].selectedIcon),
      floatingActionButtonLocation: _DockedAtIndexFabLocation(
        index: selectedIndex,
        count: items.length,
      ),
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        color: AppColors.ink,
        padding: EdgeInsets.zero,
        child: SizedBox(
          height: 64,
          child: Row(
            children: List.generate(items.length, (index) {
              // A aba selecionada "vira" o círculo flutuante — o slot dela
              // aqui embaixo fica vazio (é onde o notch corta a barra).
              if (index == selectedIndex) {
                return const Expanded(child: SizedBox.shrink());
              }
              final item = items[index];
              return Expanded(
                child: InkWell(
                  onTap: () => onDestinationSelected(index),
                  child: Icon(item.icon, color: Colors.white54, size: 24),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

/// O círculo flutuante — mostra o ícone da aba atualmente selecionada
/// (troca com um fade curto quando a aba muda; a posição em si é animada
/// pelo próprio `Scaffold` ao trocar o `floatingActionButtonLocation`).
class _BrandFab extends StatelessWidget {
  const _BrandFab({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.primaryDark],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Icon(icon, key: ValueKey(icon), color: Colors.white, size: 28),
        ),
      ),
    );
  }
}

/// Posiciona o FAB "docado" na barra (metade acima, metade dentro dela),
/// alinhado ao centro do slot da aba [index] entre [count] abas — é isso
/// que faz o círculo deslizar pra posição certa conforme a navegação muda.
/// Implementa `==`/`hashCode` por (index, count) pra o `Scaffold` saber
/// quando a posição realmente mudou (e animar) e quando não mudou (e não
/// reiniciar a animação à toa).
class _DockedAtIndexFabLocation extends FloatingActionButtonLocation {
  const _DockedAtIndexFabLocation({required this.index, required this.count});

  final int index;
  final int count;

  @override
  Offset getOffset(ScaffoldPrelayoutGeometry scaffoldGeometry) {
    final slotWidth = scaffoldGeometry.scaffoldSize.width / count;
    final fabWidth = scaffoldGeometry.floatingActionButtonSize.width;
    final fabX = slotWidth * (index + 0.5) - fabWidth / 2.0;
    final fabY =
        scaffoldGeometry.contentBottom - scaffoldGeometry.floatingActionButtonSize.height / 2.0;
    return Offset(fabX, fabY);
  }

  @override
  bool operator ==(Object other) =>
      other is _DockedAtIndexFabLocation && other.index == index && other.count == count;

  @override
  int get hashCode => Object.hash(index, count);
}
