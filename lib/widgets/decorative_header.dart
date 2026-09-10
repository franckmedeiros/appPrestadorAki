import 'package:flutter/material.dart';

import '../core/app_theme.dart';

/// Cabeçalho em gradiente com o canto de baixo arredondado, usado no topo
/// de Login, Cadastro, Esqueci minha senha e "Meu perfil" — mesmo desenho
/// do app Resenha, nas cores da marca OP OutSourcing
/// (AppColors.primaryGradient) em vez de azul.
///
/// Tinha também três círculos brancos translúcidos ao fundo (daí o nome
/// "decorative"), removidos a pedido do Franck — ver o comentário no
/// build. O nome ficou por compatibilidade com quem já usa o widget.
class DecorativeHeader extends StatelessWidget {
  const DecorativeHeader({
    super.key,
    required this.child,
    this.height = 230,
    this.borderRadius = 32,
    this.padding = const EdgeInsets.fromLTRB(24, 12, 24, 32),
  });

  final Widget child;
  final double height;
  final double borderRadius;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.only(
        bottomLeft: Radius.circular(borderRadius),
        bottomRight: Radius.circular(borderRadius),
      ),
      child: Container(
        constraints: BoxConstraints(minHeight: height),
        width: double.infinity,
        decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
        // Os três círculos brancos translúcidos que ficavam soltos aqui
        // atrás foram removidos a pedido do Franck ("retire essas bolas")
        // — o mesmo enfeite saiu do BrandGradientBackground (splash e
        // boas-vindas), então hoje todo fundo de marca do app é o
        // gradiente laranja liso, sem enfeite nenhum.
        child: SafeArea(
          bottom: false,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}
