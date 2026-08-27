import 'package:flutter/services.dart';

/// Máscara de texto minimalista (sem depender de nenhum pacote externo —
/// menos uma dependência do Gradle pra dar problema, ver o histórico de
/// build do compileSdk). `#` no padrão vira "próximo dígito digitado";
/// qualquer outro caractere do padrão (espaço, parênteses, traço, barra,
/// dois-pontos) é inserido literalmente. Usada em telefone, CEP e agora
/// data/hora digitadas (ver AppointmentFormScreen).
///
/// Extraída de `EditProfileScreen` (onde já existia, privada) pra virar
/// compartilhada — o formulário de cliente (`CustomerFormScreen`) também
/// precisava de máscara de telefone e não fazia sentido duplicar a classe.
class MaskTextInputFormatter extends TextInputFormatter {
  MaskTextInputFormatter(this.mask);

  final String mask;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    final buffer = StringBuffer();
    var digitIndex = 0;
    for (var i = 0; i < mask.length && digitIndex < digits.length; i++) {
      if (mask[i] == '#') {
        buffer.write(digits[digitIndex]);
        digitIndex++;
      } else {
        buffer.write(mask[i]);
      }
    }
    final text = buffer.toString();
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}
