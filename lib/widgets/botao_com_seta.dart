import 'package:flutter/material.dart';

import '../core/app_theme.dart';

/// Botão largo com uma caixinha de seta encostada na direita — o desenho
/// de botão das telas de entrada.
///
/// A seta não é enfeite: ela diz que o botão LEVA a algum lugar, e é o
/// que diferencia "Entrar" (vai pra outra tela) de um botão que confirma
/// algo e fica onde está. Por isso ela vem no mesmo widget do rótulo, e
/// não como um ícone que cada tela decide colocar ou não.
///
/// Dois tipos, os dois com a mesma altura e o mesmo canto:
///  - `preenchido`: fundo laranja, caixa da seta num laranja mais fechado;
///  - `contornado`: cartão branco com borda, caixa da seta no creme do
///    fundo. É o segundo botão de uma dupla — o que a pessoa escolhe
///    quando NÃO é o caminho principal.
class BotaoComSeta extends StatelessWidget {
  const BotaoComSeta({
    super.key,
    required this.rotulo,
    required this.aoTocar,
    this.preenchido = true,
    this.carregando = false,
    this.icone = Icons.arrow_forward,
    this.comCaixa = true,
  });

  final String rotulo;
  final VoidCallback? aoTocar;
  final bool preenchido;
  final bool carregando;
  final IconData icone;

  /// A caixinha atrás do ícone. Ela existe pra seta de "isto te leva pra
  /// outra tela". Num botão que CRIA alguma coisa ("Novo orçamento", com
  /// um "+"), a caixa sugere uma segunda ação dentro do botão — aí o
  /// ícone vai solto.
  final bool comCaixa;

  @override
  Widget build(BuildContext context) {
    final desligado = aoTocar == null || carregando;

    final corDoFundo = preenchido ? AppColors.primary : AppColors.surface;
    final corDoTexto = preenchido ? Colors.white : AppColors.ink;
    final corDaCaixa = preenchido ? AppColors.primaryProfundo : AppColors.background;
    final corDaSeta = preenchido ? Colors.white : AppColors.primary;

    return Opacity(
      opacity: desligado ? 0.55 : 1,
      child: Material(
        color: corDoFundo,
        borderRadius: BorderRadius.circular(AppMetrics.raioDeControle),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppMetrics.raioDeControle),
          onTap: desligado ? null : aoTocar,
          child: Container(
            height: AppMetrics.alturaDeControle,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppMetrics.raioDeControle),
              border: preenchido ? null : Border.all(color: AppColors.borda),
            ),
            child: Row(
              children: [
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    rotulo,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.3,
                      fontWeight: FontWeight.w700,
                      color: corDoTexto,
                    ),
                  ),
                ),
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: comCaixa ? corDaCaixa : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: carregando
                      ? Padding(
                          padding: const EdgeInsets.all(11),
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            valueColor: AlwaysStoppedAnimation(corDaSeta),
                          ),
                        )
                      : Icon(icone, size: 18, color: corDaSeta),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
