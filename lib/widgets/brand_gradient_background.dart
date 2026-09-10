import 'package:flutter/material.dart';
import '../core/app_theme.dart';

/// Fundo da marca: gradiente em três paradas (primaryDark → primary →
/// ink) com círculos brancos translúcidos soltos por cima.
///
/// Nasceu dentro da WelcomeScreen (o layout que o Franck aprovou) e virou
/// um widget próprio quando ele pediu que a SplashScreen tivesse o MESMO
/// fundo — antes a splash usava um gradiente diferente, de duas paradas e
/// sem os círculos, então o fundo "trocava" no meio do caminho entre
/// abrir o app e cair na tela de boas-vindas. Com as duas telas usando
/// este widget, a transição fica contínua e qualquer ajuste futuro na
/// marca vale pras duas de uma vez.
class BrandGradientBackground extends StatelessWidget {
  const BrandGradientBackground({super.key, required this.child});

  /// Conteúdo desenhado por cima do fundo (já dentro do Stack) — quem usa
  /// é que decide se envolve num SafeArea/Center/Padding.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.primaryDark, AppColors.primary, AppColors.ink],
              ),
            ),
          ),
        ),
        const _DecorativeBlob(top: -60, left: -60, size: 220),
        const _DecorativeBlob(top: 120, right: -80, size: 260),
        const _DecorativeBlob(bottom: 40, left: -70, size: 200),
        child,
      ],
    );
  }
}

class _DecorativeBlob extends StatelessWidget {
  const _DecorativeBlob({this.top, this.left, this.right, this.bottom, required this.size});

  final double? top;
  final double? left;
  final double? right;
  final double? bottom;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: top,
      left: left,
      right: right,
      bottom: bottom,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.08),
        ),
      ),
    );
  }
}
