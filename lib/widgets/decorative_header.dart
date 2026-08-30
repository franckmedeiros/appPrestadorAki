import 'package:flutter/material.dart';

import '../core/app_theme.dart';

/// Cabeçalho decorativo em gradiente com círculos translúcidos ao fundo —
/// mesmo desenho usado no app Resenha pras telas de Boas-vindas, Login e
/// Cadastro (ver DecorativeHeader de lá), só que nas cores da marca OP
/// OutSourcing (AppColors.primaryGradient) em vez de azul.
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
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(top: -50, right: -40, child: _bubble(150, 0.12)),
            Positioned(bottom: -60, left: -50, child: _bubble(170, 0.10)),
            Positioned(top: 30, left: -20, child: _bubble(60, 0.14)),
            SafeArea(
              bottom: false,
              child: Padding(padding: padding, child: child),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bubble(double size, double opacity) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: opacity),
      ),
    );
  }
}
