import 'package:flutter/material.dart';
import '../../../core/app_theme.dart';

/// Widget de classificação por estrelas — visual grande e proeminente
/// (pedido do Franck: "não é pra destaque, é classificação assim", com
/// referência a um selo de estrelas grandes e douradas). Cada estrela é
/// desenhada com preenchimento FRACIONÁRIO (ex.: 4.6 mostra a 5ª estrela
/// uns 60% dourada, não arredondada pra cheia nem vazia) usando um
/// `ClipRect` por cima do ícone cinza de base — mesma técnica clássica de
/// barra de estrelas, sem depender de nenhum pacote externo.
class StarRatingBar extends StatelessWidget {
  const StarRatingBar({
    super.key,
    required this.rating,
    required this.count,
    this.starSize = 22,
    this.showCount = true,
  });

  final double rating;
  final int count;
  final double starSize;
  final bool showCount;

  static const _gold = Color(0xFFF5A623);

  @override
  Widget build(BuildContext context) {
    if (count == 0) {
      return Text(
        'Ainda sem avaliações',
        style: TextStyle(color: AppColors.muted, fontSize: starSize * 0.6),
      );
    }
    final clamped = rating.clamp(0, 5).toDouble();
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (var i = 0; i < 5; i++) _Star(fill: (clamped - i).clamp(0, 1).toDouble(), size: starSize),
        SizedBox(width: starSize * 0.25),
        Text(
          rating.toStringAsFixed(1),
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: starSize * 0.72, color: AppColors.ink),
        ),
        if (showCount) ...[
          SizedBox(width: starSize * 0.2),
          Text(
            '($count)',
            style: TextStyle(color: AppColors.muted, fontSize: starSize * 0.58),
          ),
        ],
      ],
    );
  }
}

class _Star extends StatelessWidget {
  const _Star({required this.fill, required this.size});

  /// 0 = vazia, 1 = cheia, valores entre os dois = parcialmente
  /// preenchida (a fração da largura, da esquerda pra direita).
  final double fill;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          Icon(Icons.star_rounded, size: size, color: const Color(0xFFE0E0E0)),
          if (fill > 0)
            ClipRect(
              clipper: _FractionClipper(fill),
              child: Icon(Icons.star_rounded, size: size, color: StarRatingBar._gold),
            ),
        ],
      ),
    );
  }
}

class _FractionClipper extends CustomClipper<Rect> {
  _FractionClipper(this.fraction);

  final double fraction;

  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width * fraction, size.height);

  @override
  bool shouldReclip(_FractionClipper oldClipper) => oldClipper.fraction != fraction;
}
