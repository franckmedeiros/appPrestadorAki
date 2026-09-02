/// Monta o payload "Pix Copia e Cola" (BR Code / EMV QR estático, valor
/// fixo) a partir da chave Pix do prestador — usado na tela de Serviços
/// quando um job entra em "aguardando pagamento" (pedido do Franck:
/// "chega a hora de gerar o Qrcode e enviar para o cliente"). Sem
/// dependência de pacote externo — é um formato estável, publicado pelo
/// Banco Central (Manual de Padrões para Iniciação do Pix), então vale a
/// pena montar na mão em vez de puxar mais uma dependência de terceiro
/// só pra isso.
///
/// Cada campo do payload é TLV (Tag-Length-Value): 2 dígitos de id + 2
/// dígitos de tamanho (em bytes) + o valor. No final entra o CRC16 do
/// payload inteiro (ver `_crc16`).
class PixPayload {
  /// [pixKey] é a chave Pix cadastrada pelo prestador (CPF/CNPJ, e-mail,
  /// telefone ou chave aleatória — qualquer uma serve, o formato do
  /// payload é o mesmo). [amountCents] é o valor total do orçamento
  /// (ver `Job.totalCents`). [merchantName]/[merchantCity] identificam
  /// quem está recebendo — aparecem pro cliente ao escanear, no app do
  /// banco dele.
  static String build({
    required String pixKey,
    required int amountCents,
    required String merchantName,
    String merchantCity = 'BRASIL',
    String? referenceLabel,
  }) {
    final amount = (amountCents / 100).toStringAsFixed(2);
    final name = _sanitize(merchantName, maxLength: 25, fallback: 'PRESTADOR');
    final city = _sanitize(merchantCity, maxLength: 15, fallback: 'BRASIL');
    final txid = _sanitize(referenceLabel ?? '***', maxLength: 25, fallback: '***');

    final merchantAccountInfo = _field('00', 'br.gov.bcb.pix') + _field('01', pixKey.trim());
    final additionalData = _field('05', txid);

    final payload = StringBuffer()
      ..write(_field('00', '01')) // Payload Format Indicator
      ..write(_field('01', '11')) // Point of Initiation Method (estático)
      ..write(_field('26', merchantAccountInfo)) // Merchant Account Info (Pix)
      ..write(_field('52', '0000')) // Merchant Category Code
      ..write(_field('53', '986')) // Transaction Currency (BRL)
      ..write(_field('54', amount)) // Transaction Amount
      ..write(_field('58', 'BR')) // Country Code
      ..write(_field('59', name)) // Merchant Name
      ..write(_field('60', city)) // Merchant City
      ..write(_field('62', additionalData)); // Additional Data Field Template

    // O CRC é calculado sobre o payload JÁ incluindo o id+tamanho do
    // próprio campo do CRC ("6304"), mas sem o valor (que ainda não
    // existe) — por isso concatena esse prefixo antes de calcular.
    final withCrcHeader = '${payload.toString()}6304';
    final crc = _crc16(withCrcHeader).toRadixString(16).toUpperCase().padLeft(4, '0');
    return '$withCrcHeader$crc';
  }

  static String _field(String id, String value) {
    final length = value.length.toString().padLeft(2, '0');
    return '$id$length$value';
  }

  /// Remove acentos/caracteres fora do padrão aceito pelo Pix (só ASCII
  /// básico) e corta no tamanho máximo do campo.
  static String _sanitize(String value, {required int maxLength, required String fallback}) {
    const withAccents = 'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇáàâãäéèêëíìîïóòôõöúùûüçÑñ';
    const withoutAccents = 'AAAAAEEEEIIIIOOOOOUUUUCaaaaaeeeeiiiiooooouuuucNn';
    final buffer = StringBuffer();
    for (final char in value.runes) {
      final ch = String.fromCharCode(char);
      final accentIndex = withAccents.indexOf(ch);
      if (accentIndex != -1) {
        buffer.write(withoutAccents[accentIndex]);
      } else if (char >= 0x20 && char <= 0x7E) {
        buffer.write(ch);
      }
      // caracteres fora da faixa ASCII imprimível (emoji etc.) são
      // simplesmente descartados.
    }
    final cleaned = buffer.toString().trim().toUpperCase();
    final result = cleaned.isEmpty ? fallback : cleaned;
    return result.length > maxLength ? result.substring(0, maxLength) : result;
  }

  /// CRC-16/CCITT-FALSE (polinômio 0x1021, valor inicial 0xFFFF) — o
  /// algoritmo exato exigido pelo padrão do Pix pro campo final (id 63)
  /// do payload.
  static int _crc16(String data) {
    const polynomial = 0x1021;
    var crc = 0xFFFF;
    for (final byte in data.codeUnits) {
      crc ^= (byte << 8);
      for (var i = 0; i < 8; i++) {
        crc = (crc & 0x8000) != 0 ? ((crc << 1) ^ polynomial) : (crc << 1);
        crc &= 0xFFFF;
      }
    }
    return crc;
  }
}
