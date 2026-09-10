import 'package:flutter/material.dart';
import '../core/app_theme.dart';

/// Fundo da marca: o gradiente laranja padrão do app
/// (`AppColors.primaryGradient`) com círculos brancos translúcidos
/// soltos por cima.
///
/// Nasceu dentro da WelcomeScreen (o layout que o Franck aprovou) e virou
/// um widget próprio quando ele pediu que a SplashScreen tivesse o MESMO
/// fundo — antes a splash usava um gradiente diferente, então o fundo
/// "trocava" no meio do caminho entre abrir o app e cair na tela de
/// boas-vindas.
///
/// Segundo ajuste, também a pedido dele ("preciso que fique com o mesmo
/// fundo das demais telas, pra mim está diferente"): o gradiente daqui
/// tinha uma TERCEIRA parada em `AppColors.ink` (o quase-preto da marca),
/// que escurecia bastante a parte de baixo e destoava de todo o resto do
/// app — login, cadastro e o cabeçalho de "Meu perfil" usam
/// `AppColors.primaryGradient`, que é só laranja. Agora este widget usa
/// exatamente esse mesmo gradiente, então TODAS as telas com fundo de
/// marca combinam, e mudar a cor num lugar só (app_theme.dart) muda em
/// todas de uma vez.
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
            decoration: BoxDecoration(gradient: AppColors.primaryGradient),
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
