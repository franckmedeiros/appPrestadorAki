import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import 'marca_app.dart';

/// Qual lado do app a pessoa está usando agora.
///
/// O PrestadorAki é dois aplicativos no mesmo pacote: quem contrata e
/// quem atende. As telas se parecem, e sem um aviso constante a pessoa
/// se perde — principalmente o prestador, que também usa o lado de
/// cliente pra procurar colegas. Daí a etiqueta no alto de toda tela.
enum AreaDoApp {
  cliente('ÁREA DO CLIENTE'),
  prestador('ÁREA DO PRESTADOR');

  const AreaDoApp(this.rotulo);

  final String rotulo;
}

/// O topo padrão das telas internas, conforme a entrega do Figma
/// (out/2026):
///
/// ```
/// PrestadorAki        ÁREA DO PRESTADOR   🔔
/// Gerenciamento
/// ▬▬
/// ```
///
/// Três decisões do desenho que vale explicar, porque não são óbvias e
/// quem mexer depois vai querer "arrumar":
///
///  - A barrinha laranja embaixo do título encosta na BORDA ESQUERDA da
///    tela, não na margem de 24 do conteúdo. É de propósito: ela amarra
///    o título à borda e faz as vezes da faixa colorida que o app tinha
///    antes, gastando seis pixels em vez da tela toda.
///  - Não é uma `AppBar`. `AppBar` tem altura fixa, centraliza, e não
///    deixa o título ser de 36 — tudo o que este desenho não quer. É um
///    bloco comum no começo do corpo da tela, e rola junto com ele.
///  - A etiqueta da área fica em caixa alta e pequena. Ela precisa estar
///    sempre visível, mas nunca competir com o título.
class CabecalhoDeTela extends StatelessWidget {
  const CabecalhoDeTela({
    super.key,
    required this.titulo,
    required this.area,
    this.aoVoltar,
    this.acao,
    this.umaLinha = false,
  });

  /// O nome da tela, em letra grande ("Gerenciamento", "Orçamentos").
  final String titulo;

  /// Trava o título em uma linha só. Usado por `barraDeTela`, que tem
  /// altura fixa — ali um título de duas linhas seria cortado.
  final bool umaLinha;

  final AreaDoApp area;

  /// Quando esta tela foi aberta por cima de outra, a seta de voltar
  /// toma o lugar da marca — quem está no meio de um fluxo precisa da
  /// saída mais do que de ver o nome do app de novo.
  final VoidCallback? aoVoltar;

  /// Botão opcional no canto direito (o sino de notificações, o ícone de
  /// compartilhar). Fica DEPOIS da etiqueta da área.
  final Widget? acao;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 44,
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(left: AppMetrics.margemLateral),
                child: aoVoltar != null
                    ? IconButton(
                        onPressed: aoVoltar,
                        icon: const Icon(Icons.arrow_back, size: 20),
                        color: AppColors.ink,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 40,
                          minHeight: 40,
                        ),
                        tooltip: 'Voltar',
                      )
                    : const MarcaEscrita(),
              ),
              const Spacer(),
              Text(
                area.rotulo,
                style: const TextStyle(
                  fontSize: 9,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
              SizedBox(
                // Mesmo sem ação, reserva o espaço dela: senão a etiqueta
                // da área dança de lugar entre uma tela com sino e uma
                // sem, e a troca de abas fica tremida.
                width: AppMetrics.margemLateral + (acao != null ? 36 : 0),
                child: acao == null
                    ? null
                    : Align(alignment: Alignment.centerRight, child: acao),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppMetrics.margemLateral,
          ),
          child: Text(
            titulo,
            maxLines: umaLinha ? 1 : 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 32,
              height: 1.06,
              letterSpacing: -0.6,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
        ),
        const SizedBox(height: 14),
        // A barrinha encostada na borda esquerda — ver o comentário da
        // classe.
        Container(width: 62, height: 5, color: AppColors.primary),
        const SizedBox(height: 18),
      ],
    );
  }
}

/// Título de um bloco dentro da tela ("Compromissos de hoje", "Atalhos"),
/// com um link opcional à direita ("Ver agenda").
class TituloDeBloco extends StatelessWidget {
  const TituloDeBloco(
    this.texto, {
    super.key,
    this.rotuloDaAcao,
    this.aoTocarNaAcao,
  });

  final String texto;
  final String? rotuloDaAcao;
  final VoidCallback? aoTocarNaAcao;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          texto,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
        if (rotuloDaAcao != null)
          GestureDetector(
            onTap: aoTocarNaAcao,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
              child: Text(
                rotuloDaAcao!,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Cartão branco padrão: canto 12, sem sombra, com uma borda fininha.
///
/// A borda existe porque o fundo das telas é creme e o cartão é branco —
/// a diferença entre os dois é pequena demais pra separar sozinha. Era
/// isso ou sombra, e sombra em cima de creme fica suja.
class CartaoDoApp extends StatelessWidget {
  const CartaoDoApp({
    super.key,
    required this.child,
    this.aoTocar,
    this.padding = const EdgeInsets.all(AppMetrics.paddingDeCartao),
  });

  final Widget child;
  final VoidCallback? aoTocar;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final conteudo = Padding(padding: padding, child: child);
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppMetrics.raioDeCartao),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppMetrics.raioDeCartao),
        onTap: aoTocar,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppMetrics.raioDeCartao),
            border: Border.all(color: AppColors.borda),
          ),
          child: conteudo,
        ),
      ),
    );
  }
}

/// A altura do `CabecalhoDeTela` com o título em uma linha.
///
/// 44 da linha da marca + 6 + 34 do título + 14 + 5 da barrinha + 18 de
/// respiro. Está escrito aqui e não espalhado porque é o número que
/// `barraDeTela` precisa declarar ANTES de desenhar.
const double kAlturaDaBarraDeTela = 121;

/// O cabeçalho do app embrulhado como `appBar:` de um `Scaffold`.
///
/// Serve pras telas cujo corpo é uma árvore grande e já fechada — trocar
/// `appBar: AppBar(...)` por isto é uma linha, enquanto mover o corpo
/// inteiro pra dentro de uma `Column` mexeria em dezenas de linhas por
/// tela sem nenhum ganho.
///
/// A altura soma a faixa do sistema (relógio, bateria) à mão em vez de
/// confiar no `Scaffold`: ele só acrescenta essa folga sozinho pra uma
/// `AppBar` de verdade, e um cabeçalho com altura declarada a menos
/// aparece cortado em cima.
PreferredSizeWidget barraDeTela(
  BuildContext context, {
  required String titulo,
  required AreaDoApp area,
  VoidCallback? aoVoltar,
  Widget? acao,
}) {
  final faixaDoSistema = MediaQuery.of(context).padding.top;
  return PreferredSize(
    preferredSize: Size.fromHeight(kAlturaDaBarraDeTela + faixaDoSistema),
    child: Material(
      color: AppColors.background,
      child: Padding(
        padding: EdgeInsets.only(top: faixaDoSistema),
        child: CabecalhoDeTela(
          titulo: titulo,
          area: area,
          aoVoltar: aoVoltar,
          acao: acao,
          umaLinha: true,
        ),
      ),
    ),
  );
}
