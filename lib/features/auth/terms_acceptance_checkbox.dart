import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import 'terms_screen.dart';

/// Caixa "Li e aceito os Termos de Uso", com link pro texto.
///
/// Um widget só, usado nas TRÊS telas onde se cria conta (RegisterScreen,
/// ClientAuthGate e GuestProfilePanel). Isso é de propósito: se cada tela
/// tivesse a sua cópia, bastaria alguém mexer em uma pra as outras
/// divergirem em silêncio — e o caminho de cadastro que ficasse sem o
/// aceite é justamente o que a revisão da Apple encontraria.
///
/// A caixa vem DESMARCADA. Aceite pré-marcado não é aceite: a pessoa
/// precisa fazer o gesto pra que se possa dizer que ela concordou.
///
/// O link pros Termos é um botão SEPARADO, embaixo, em vez de um trecho
/// clicável dentro da frase. Dois motivos: um `TapGestureRecognizer` criado
/// no `build` precisa ser descartado à mão (senão vaza a cada rebuild), e
/// num toque de dedo a diferença entre "marcar a caixa" e "abrir os termos"
/// dentro da mesma linha de texto é pequena demais pra acertar sempre.
///
/// Quem usa é responsável por bloquear o botão de cadastro enquanto
/// [value] for falso — ver os três chamadores.
class TermsAcceptanceCheckbox extends StatelessWidget {
  const TermsAcceptanceCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => onChanged(!value),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 26,
                  height: 26,
                  child: Checkbox(
                    value: value,
                    onChanged: (v) => onChanged(v ?? false),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(top: 3),
                    child: Text(
                      'Li e aceito os Termos de Uso, e entendo que conteúdo '
                      'ofensivo não é tolerado e pode levar ao encerramento '
                      'da conta.',
                      style: TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.muted),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 36),
          child: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const TermsScreen()),
            ),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              alignment: Alignment.centerLeft,
            ),
            child: const Text(
              'Ler os Termos de Uso',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }
}
