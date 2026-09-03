import 'package:flutter/material.dart';

/// Selo "Aditivo nº N" — usado em qualquer lugar que mostra um item ou
/// orçamento marcado como acrescentado por um aditivo (ver
/// `BudgetItem.aditivoNumber`/`Budget.revisionNumber`) — pedido do
/// Franck: o aditivo aparece como um item A MAIS no orçamento, marcado
/// como tal, sem nunca esconder os itens originais. Widget único
/// compartilhado (em vez de repetir o mesmo Container/decoration em
/// cada tela) pra nunca divergir visualmente entre BudgetFormScreen
/// (lado do prestador) e MyRequestsScreen (lado do cliente).
class AditivoBadge extends StatelessWidget {
  const AditivoBadge({super.key, required this.number, this.compact = false});

  final int number;

  /// Menor, pra caber ao lado do título de cada linha de item — o
  /// tamanho padrão (não compacto) é o do cabeçalho do orçamento como
  /// um todo.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: compact ? 3 : 5),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'Aditivo nº $number',
        style: TextStyle(
          color: Colors.orange,
          fontWeight: FontWeight.w700,
          fontSize: compact ? 11 : 12,
        ),
      ),
    );
  }
}
