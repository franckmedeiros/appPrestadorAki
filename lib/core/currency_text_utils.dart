/// Formatação/leitura de valores em reais — mesmo padrão usado em vários
/// lugares do app (ex.: IncomingRequestsScreen: `double.tryParse` trocando
/// vírgula por ponto), só que centralizado aqui porque o módulo de
/// Orçamentos precisa formatar em vários pontos (cada item, subtotal,
/// desconto, total) no formato brasileiro de verdade (vírgula decimal),
/// não só `toStringAsFixed` cru (que sempre usa ponto).
library;

/// `1050` -> `'R$ 10,50'`. `123456` -> `'R$ 1.234,56'`.
String formatCentsBRL(int cents) {
  final negative = cents < 0;
  final abs = cents.abs();
  final reais = abs ~/ 100;
  final centavos = (abs % 100).toString().padLeft(2, '0');
  return '${negative ? '-' : ''}R\$ ${_withThousandsSeparator(reais)},$centavos';
}

String _withThousandsSeparator(int value) {
  final text = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    if (i > 0 && (text.length - i) % 3 == 0) buffer.write('.');
    buffer.write(text[i]);
  }
  return buffer.toString();
}

/// Lê um texto digitado (vírgula ou ponto como separador decimal) e
/// devolve o valor em centavos — `null` se não for um número válido.
/// Mesma tolerância já usada em IncomingRequestsScreen._respondWithQuote.
int? tryParseCentsFromText(String text) {
  final value = double.tryParse(text.trim().replaceAll(',', '.'));
  if (value == null) return null;
  return (value * 100).round();
}
