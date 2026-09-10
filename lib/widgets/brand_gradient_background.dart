import 'package:flutter/material.dart';
import '../core/app_theme.dart';

/// Fundo da marca: o gradiente laranja padrão do app
/// (`AppColors.primaryGradient`), liso.
///
/// Nasceu dentro da WelcomeScreen (o layout que o Franck aprovou) e virou
/// um widget próprio quando ele pediu que a SplashScreen tivesse o MESMO
/// fundo — antes a splash usava um gradiente diferente, então o fundo
/// "trocava" no meio do caminho entre abrir o app e cair na tela de
/// boas-vindas.
///
/// Depois disso passou por dois ajustes, os dois a pedido dele: o
/// gradiente tinha uma terceira parada em `AppColors.ink` (o quase-preto
/// da marca), que escurecia a parte de baixo e destoava do resto do app
/// ("pra mim está diferente") — hoje usa o mesmo `AppColors.primaryGradient`
/// de login/cadastro/"Meu perfil"; e tinha três círculos brancos
/// translúcidos de enfeite, removidos em seguida ("retire essas bolas").
/// O mesmo enfeite foi tirado do DecorativeHeader, pelo mesmo motivo.
///
/// Sobrou um widget bem simples, mas mantido de propósito: é o ponto
/// único onde o fundo de marca é definido, então mudar ele muda a splash
/// e as boas-vindas juntas, sem chance de uma ficar diferente da outra.
class BrandGradientBackground extends StatelessWidget {
  const BrandGradientBackground({super.key, required this.child});

  /// Conteúdo desenhado por cima do fundo — quem usa é que decide se
  /// envolve num SafeArea/Center/Padding.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
      child: SizedBox.expand(child: child),
    );
  }
}
