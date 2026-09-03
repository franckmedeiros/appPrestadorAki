/**
 * Porta pra TypeScript de `lib/core/pix_payload.dart` — mesmo formato
 * ("Pix Copia e Cola" / BR Code, valor fixo), usada aqui pelo
 * `onJobStatusChanged` (ver jobs.ts) pra montar o QR Code do lado do
 * SERVIDOR quando um serviço entra em "aguardando_pagamento", e gravar
 * o resultado pronto no orçamento do cliente (`paymentPixPayload`) —
 * assim o cliente vê o QR Code em "Meus orçamentos" sem precisar ler o
 * perfil do prestador (que nem é público o suficiente pra isso: a
 * chave Pix mora em `providers/{uid}.pixKey`, um campo privado).
 *
 * Qualquer mudança aqui precisa ser espelhada em pix_payload.dart (e
 * vice-versa) — os dois implementam exatamente o mesmo padrão do Banco
 * Central, cada um do seu lado (app gera o QR de cobrança presencial em
 * "Serviços"; aqui gera o mesmo QR pro cliente à distância).
 */
export function buildPixPayload(options: {
  pixKey: string;
  amountCents: number;
  merchantName: string;
  merchantCity?: string;
  referenceLabel?: string;
}): string {
  const { pixKey, amountCents, merchantName } = options;
  const merchantCity = options.merchantCity ?? 'BRASIL';
  const referenceLabel = options.referenceLabel ?? '***';

  const amount = (amountCents / 100).toFixed(2);
  const name = sanitize(merchantName, 25, 'PRESTADOR');
  const city = sanitize(merchantCity, 15, 'BRASIL');
  const txid = sanitize(referenceLabel, 25, '***');

  const merchantAccountInfo = field('00', 'br.gov.bcb.pix') + field('01', pixKey.trim());
  const additionalData = field('05', txid);

  const payload =
    field('00', '01') + // Payload Format Indicator
    field('01', '11') + // Point of Initiation Method (estático)
    field('26', merchantAccountInfo) + // Merchant Account Info (Pix)
    field('52', '0000') + // Merchant Category Code
    field('53', '986') + // Transaction Currency (BRL)
    field('54', amount) + // Transaction Amount
    field('58', 'BR') + // Country Code
    field('59', name) + // Merchant Name
    field('60', city) + // Merchant City
    field('62', additionalData); // Additional Data Field Template

  // O CRC é calculado sobre o payload JÁ incluindo o id+tamanho do
  // próprio campo do CRC ("6304"), mas sem o valor (que ainda não
  // existe) — por isso concatena esse prefixo antes de calcular.
  const withCrcHeader = `${payload}6304`;
  const crc = crc16(withCrcHeader).toString(16).toUpperCase().padStart(4, '0');
  return `${withCrcHeader}${crc}`;
}

function field(id: string, value: string): string {
  const length = value.length.toString().padStart(2, '0');
  return `${id}${length}${value}`;
}

/** Remove acentos/caracteres fora do padrão aceito pelo Pix (só ASCII básico) e corta no tamanho máximo do campo. */
function sanitize(value: string, maxLength: number, fallback: string): string {
  const withAccents = 'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇáàâãäéèêëíìîïóòôõöúùûüçÑñ';
  const withoutAccents = 'AAAAAEEEEIIIIOOOOOUUUUCaaaaaeeeeiiiiooooouuuucNn';
  let buffer = '';
  for (const ch of value) {
    const accentIndex = withAccents.indexOf(ch);
    const code = ch.codePointAt(0) ?? 0;
    if (accentIndex !== -1) {
      buffer += withoutAccents[accentIndex];
    } else if (code >= 0x20 && code <= 0x7e) {
      buffer += ch;
    }
    // caracteres fora da faixa ASCII imprimível (emoji etc.) são simplesmente descartados.
  }
  const cleaned = buffer.trim().toUpperCase();
  const result = cleaned.length === 0 ? fallback : cleaned;
  return result.length > maxLength ? result.substring(0, maxLength) : result;
}

/** CRC-16/CCITT-FALSE (polinômio 0x1021, valor inicial 0xFFFF) — algoritmo exato exigido pelo Pix pro campo final (id 63). */
function crc16(data: string): number {
  const polynomial = 0x1021;
  let crc = 0xffff;
  for (let i = 0; i < data.length; i++) {
    const byte = data.charCodeAt(i);
    crc ^= byte << 8;
    for (let bit = 0; bit < 8; bit++) {
      crc = (crc & 0x8000) !== 0 ? ((crc << 1) ^ polynomial) & 0xffff : (crc << 1) & 0xffff;
    }
  }
  return crc;
}
