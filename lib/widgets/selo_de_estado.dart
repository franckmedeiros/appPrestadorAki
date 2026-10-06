import 'package:flutter/material.dart';

import '../core/app_theme.dart';

/// As cores de um selo de estado, sempre em PAR: a cor do texto e a cor
/// do fundo onde ele é escrito.
///
/// Vêm em par porque foi assim que o guia do Figma entregou, e porque é
/// o que impede o erro clássico de selo — verde escrito sobre verde,
/// legível no monitor do designer e invisível no celular do prestador
/// no sol. Escolher só "a cor do estado" e derivar o fundo com
/// transparência era o que o app fazia antes, e o resultado variava de
/// um estado pro outro.
enum TomDoSelo {
  /// Precisa de você agora, ou é o estado normal de trabalho.
  marca(AppColors.primary, AppColors.primarySuave),

  /// Esperando outra pessoa — o cliente, o pagamento, uma confirmação.
  espera(AppColors.warning, AppColors.warningSuave),

  /// Deu certo, está fechado.
  positivo(AppColors.success, AppColors.successSuave),

  /// Não vai acontecer: recusado, cancelado, falhou.
  negativo(AppColors.danger, AppColors.dangerSuave),

  /// Sem carga nenhuma — rascunho, arquivado, informação neutra.
  neutro(AppColors.muted, AppColors.background);

  const TomDoSelo(this.texto, this.fundo);

  final Color texto;
  final Color fundo;
}

/// Selo de estado: uma tarja clara com o texto na cor do estado.
///
/// Cantos de 8, iguais aos dos botões e campos — e não a cápsula de
/// cantos redondos que o app usava. Cápsula pede largura: com um rótulo
/// como "Aditivo enviado — aguardando aprovação" ela vira um comprimido
/// de três centímetros e empurra o resto do card. Com canto de 8 o selo
/// é só um retângulo de texto, e pode quebrar em duas linhas sem ficar
/// estranho.
class SeloDeEstado extends StatelessWidget {
  const SeloDeEstado(this.texto, {super.key, required this.tom});

  final String texto;
  final TomDoSelo tom;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: tom.fundo,
        borderRadius: BorderRadius.circular(AppMetrics.raioDeControle),
      ),
      child: Text(
        texto,
        style: TextStyle(
          color: tom.texto,
          fontSize: 12,
          height: 1.25,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
