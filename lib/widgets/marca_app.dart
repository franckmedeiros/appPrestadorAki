import 'package:flutter/material.dart';

import '../core/app_theme.dart';

/// O nome do app escrito, com "Aki" na cor da marca — o jeito como ele
/// aparece no topo das telas de entrada (Boas-vindas, Login, Cadastro).
///
/// É um widget e não um `Text` solto em cada tela porque a divisão da
/// palavra ("Prestador" + "Aki") e o peso 800 são a assinatura visual:
/// escrito à mão em três lugares, uma hora um deles sai com peso 700 e
/// ninguém percebe.
class MarcaEscrita extends StatelessWidget {
  const MarcaEscrita({super.key, this.fontSize = 21});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.8,
      height: 1,
    );
    return RichText(
      text: TextSpan(
        style: base.copyWith(color: AppColors.ink),
        children: [
          const TextSpan(text: 'Prestador'),
          TextSpan(text: 'Aki', style: base.copyWith(color: AppColors.primary)),
        ],
      ),
    );
  }
}

/// O logo dentro de um disco bege — o "medalhão" que ocupa o meio das
/// telas de entrada.
///
/// O disco não é enfeite: o logo é um pino cobre com degradê, e sobre o
/// creme do fundo ele fica sem assentamento nenhum, parecendo colado.
/// O bege dá a ele uma base.
class MedalhaoDaMarca extends StatelessWidget {
  const MedalhaoDaMarca({super.key, this.diametro = 210});

  final double diametro;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: diametro,
      height: diametro,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.medalhao,
      ),
      padding: EdgeInsets.all(diametro * 0.18),
      child: Image.asset(
        'assets/brand/marca_prestadoraki.png',
        fit: BoxFit.contain,
        // Se o asset faltar (um `flutter clean` mal resolvido, por
        // exemplo), a tela inteira quebraria num quadrado cinza de erro.
        // Melhor cair no desenho vetorial da marca, que não depende de
        // arquivo nenhum.
        errorBuilder: (contexto, erro, pilha) => FittedBox(
          child: PrestadorAkiMarkFallback(size: diametro * 0.6),
        ),
      ),
    );
  }
}

/// Atalho pro desenho vetorial da marca, usado só como plano B do
/// medalhão (ver acima). Fica aqui pra `MedalhaoDaMarca` não precisar
/// importar o arquivo do desenho e arrastar junto as cores antigas.
class PrestadorAkiMarkFallback extends StatelessWidget {
  const PrestadorAkiMarkFallback({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Icon(Icons.place, size: size, color: AppColors.primary);
  }
}

/// Título grande das telas de entrada, com o ponto final na cor da marca
/// ("Tudo em um só lugar.", "Bem-vindo de volta.").
///
/// O ponto colorido é o único respingo de cor na metade de cima da tela
/// — é ele que impede o bloco de texto de parecer um documento.
class TituloDeEntrada extends StatelessWidget {
  const TituloDeEntrada(this.texto, {super.key});

  final String texto;

  @override
  Widget build(BuildContext context) {
    const estilo = TextStyle(
      fontSize: 36,
      height: 1.06,
      letterSpacing: -0.5,
      fontWeight: FontWeight.w800,
      color: AppColors.ink,
    );
    return RichText(
      text: TextSpan(
        style: estilo,
        children: [
          TextSpan(text: texto),
          const TextSpan(text: '.', style: TextStyle(color: AppColors.primary)),
        ],
      ),
    );
  }
}

/// Linha do topo das telas de entrada: a marca à esquerda e uma etiqueta
/// curta à direita ("Bem-vindo!", "LOGIN", "CADASTRO").
class TopoDeEntrada extends StatelessWidget {
  const TopoDeEntrada({super.key, required this.etiqueta, this.aoVoltar});

  final String etiqueta;

  /// Quando esta tela foi aberta por cima de outra, a seta de voltar
  /// substitui a marca — a pessoa precisa de uma saída mais do que
  /// precisa ver o nome do app duas vezes.
  final VoidCallback? aoVoltar;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Com seta de voltar, a marca NÃO sai: as duas ficam lado a lado.
        // Era assim no desenho de "Criar conta", e faz sentido — o nome
        // do app no alto é o que diz em que aplicativo você está depois
        // de três telas empilhadas.
        if (aoVoltar != null) ...[
          IconButton(
            onPressed: aoVoltar,
            icon: const Icon(Icons.arrow_back, size: 20),
            color: AppColors.ink,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 44),
            tooltip: 'Voltar',
          ),
          const SizedBox(width: 6),
        ],
        const MarcaEscrita(),
        const Spacer(),
        Text(
          etiqueta,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.primary,
          ),
        ),
      ],
    );
  }
}
