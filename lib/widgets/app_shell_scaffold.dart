import 'package:flutter/material.dart';
import '../core/app_theme.dart';

/// Um destino da navegação inferior.
class AppNavItem {
  const AppNavItem({required this.icon, required this.selectedIcon, required this.label});

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// Scaffold usado pelo shell único do app (ver UnifiedShell) — a lista de
/// destinos varia dinamicamente conforme a conta logada tem ou não a
/// capacidade de prestador.
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
      floatingActionButton: _BrandFab(
        icon: items[selectedIndex].selectedIcon,
        label: items[selectedIndex].label,
      ),
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
                  // Ícone + rótulo (pedido do Franck, a partir de um
                  // mockup que ele gostou). Antes era só o ícone: bonito,
                  // mas obriga a adivinhar — "lista" e "painel" não dizem
                  // nada sozinhos pra quem abriu o app pela primeira vez.
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(item.icon, color: Colors.white54, size: 22),
                      const SizedBox(height: 3),
                      Padding(
                        // Respiro lateral pra o rótulo não encostar no
                        // vizinho quando são 5 abas numa tela estreita.
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Text(
                          item.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
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
  const _BrandFab({required this.icon, required this.label});

  final IconData icon;
  final String label;

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
          // Ícone + rótulo da aba atual, pra o círculo dizer ONDE a
          // pessoa está — antes ele mostrava só o ícone, e a única aba
          // sem nome na barra era justamente a selecionada.
          child: Column(
            key: ValueKey(icon),
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 24),
              const SizedBox(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
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
