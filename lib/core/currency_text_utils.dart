/// Formatação/leitura de valores em reais — mesmo padrão usado em vários
/// lugares do app (`double.tryParse` trocando
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
/// Mesma tolerância usada em outros formulários com valor em reais.
///
/// BUG REAL corrigido aqui (visto pelo Franck no primeiro aditivo com
/// item acima de R$ 1.000): os campos de preço/desconto são
/// PRÉ-PREENCHIDOS com `formatCentsBRL(cents).replaceAll('R\$ ', '')`
/// (ver `_ItemRowControllers`/`_discountController` em
/// BudgetFormScreen) — pra qualquer valor >= R\$ 1.000 isso já vem com
/// PONTO como separador de milhar (ex.: "1.500,00"). Sem tratar isso, o
/// `replaceAll(',', '.')' de antes virava "1.500.00" (dois pontos),
/// `double.tryParse` devolvia `null`, e o preço salvava como 0 SEM
/// avisar nada — só reaparecia quebrado depois (ex.: registrar um
/// aditivo sem retocar um campo de preço que já vinha preenchido).
/// Regra: se tem vírgula, ela É o separador decimal (convenção BR usada
/// em todo o app) — qualquer ponto antes dela só pode ser separador de
/// milhar, então remove os pontos ANTES de trocar a vírgula por ponto.
/// Sem vírgula (texto digitado direto, ex.: "10.50"), o ponto continua
/// tratado como decimal, igual sempre foi.
int? tryParseCentsFromText(String text) {
  var normalized = text.trim();
  if (normalized.contains(',')) {
    normalized = normalized.replaceAll('.', '');
  }
  final value = double.tryParse(normalized.replaceAll(',', '.'));
  if (value == null) return null;
  return (value * 100).round();
}
