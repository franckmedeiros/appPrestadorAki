/**
 * Verificação criptográfica dos JWS da Apple.
 *
 * Fecha a "lacuna consciente" documentada no topo de `subscriptionApple.ts`:
 * até agora o `signedPayload` das notificações e o `signedTransactionInfo`
 * das compras eram só base64url-decodificados, sem conferir que vieram
 * mesmo da Apple. O desenho continuava seguro porque a fonte de verdade é
 * a re-consulta à App Store Server API — mas sobrava uma fresta no
 * callable: um `originalTransactionId` válido e ainda não reivindicado
 * podia ser associado à conta errada. Com a assinatura verificada, só
 * quem tem o JWS emitido pela Apple consegue reivindicar a transação.
 *
 * A `SignedDataVerifier` da biblioteca oficial precisa dos
 * certificados-raiz da Apple como entrada. Eles NÃO vêm no pacote npm e
 * precisam ser baixados uma vez e commitados em `functions/certs/apple/`:
 *
 *   https://www.apple.com/certificateauthority/AppleRootCA-G3.cer
 *   https://www.apple.com/appleca/AppleIncRootCertificate.cer
 *
 * Se a pasta estiver vazia ou ilegível, este módulo NÃO derruba o deploy:
 * ele registra um erro e devolve `null` como verificador, e quem chama cai
 * de volta no decode sem verificação — o mesmo comportamento de antes,
 * que continua seguro pelo motivo acima. Assim, esquecer os certificados
 * degrada a segurança de volta ao patamar anterior em vez de quebrar a
 * produção. Os logs avisam, em toda chamada, que isso está acontecendo.
 */

import { readdirSync, readFileSync } from 'fs';
import { join } from 'path';
import { logger } from 'firebase-functions';
import { Environment, SignedDataVerifier } from '@apple/app-store-server-library';

// Mesmo bundle identifier usado em subscriptionApple.ts.
const APPLE_BUNDLE_ID = 'com.opoutsourcing.prestadoraki';

// Apple ID numérico do app (App Store Connect > Informações do app >
// "Apple ID"). A SignedDataVerifier EXIGE esse número no ambiente de
// produção — é parte do que ela confere no payload.
const APPLE_APP_APPLE_ID = 6806624870;

// Checagem de revogação dos certificados pela rede (OCSP), direto com a
// Apple. Recomendado pela Apple em produção. Se algum dia o ambiente do
// Cloud Functions não alcançar os servidores de OCSP, as verificações vão
// começar a falhar e cair no fallback — nesse caso ponha `false` aqui;
// a cadeia de certificados continua sendo validada, só a consulta de
// revogação deixa de acontecer.
const CHECAGEM_ONLINE = true;

// Depois do build do TypeScript este arquivo roda a partir de
// `functions/lib/`, então `../certs/apple` aponta pra `functions/certs/apple`.
const PASTA_CERTIFICADOS = join(__dirname, '..', 'certs', 'apple');

let cacheRaizes: Buffer[] | null = null;
let jaAvisouQueFaltam = false;

function carregarRaizes(): Buffer[] {
  if (cacheRaizes) return cacheRaizes;
  try {
    const arquivos = readdirSync(PASTA_CERTIFICADOS).filter((n) => n.toLowerCase().endsWith('.cer'));
    cacheRaizes = arquivos.map((n) => readFileSync(join(PASTA_CERTIFICADOS, n)));
  } catch (e) {
    if (!jaAvisouQueFaltam) {
      logger.error(
        `Certificados-raiz da Apple não encontrados em ${PASTA_CERTIFICADOS} — ` +
          'as assinaturas JWS NÃO serão verificadas (fallback para decode simples). ' +
          'Baixe AppleRootCA-G3.cer e AppleIncRootCertificate.cer para essa pasta.',
        e,
      );
      jaAvisouQueFaltam = true;
    }
    cacheRaizes = [];
  }
  if (cacheRaizes.length === 0 && !jaAvisouQueFaltam) {
    logger.error(`Nenhum .cer em ${PASTA_CERTIFICADOS} — assinaturas JWS não serão verificadas.`);
    jaAvisouQueFaltam = true;
  }
  return cacheRaizes;
}

const cacheVerificadores = new Map<Environment, SignedDataVerifier | null>();

function obterVerificador(ambiente: Environment): SignedDataVerifier | null {
  if (cacheVerificadores.has(ambiente)) return cacheVerificadores.get(ambiente)!;
  const raizes = carregarRaizes();
  let verificador: SignedDataVerifier | null = null;
  if (raizes.length > 0) {
    try {
      verificador = new SignedDataVerifier(
        raizes,
        CHECAGEM_ONLINE,
        ambiente,
        APPLE_BUNDLE_ID,
        APPLE_APP_APPLE_ID,
      );
    } catch (e) {
      logger.error(`Não foi possível criar a SignedDataVerifier (${ambiente})`, e);
    }
  }
  cacheVerificadores.set(ambiente, verificador);
  return verificador;
}

/** true quando os certificados estão no lugar e a verificação real está ligada. */
export function verificacaoDisponivel(): boolean {
  return carregarRaizes().length > 0;
}

/**
 * Decodifica o "miolo" de um JWS SEM verificar a assinatura.
 *
 * Continua sendo o caminho certo para os JWS que vêm DENTRO da resposta da
 * App Store Server API (`extrairUltimaTransacao`): aquele corpo já chegou
 * por HTTPS autenticado com a nossa chave, direto da Apple — a assinatura
 * ali não acrescenta nada. Para o que chega DE FORA (notificação HTTP ou
 * dado mandado pelo app), use as funções verificadas abaixo.
 */
export function decodificarPayloadJws(jws: string): any {
  const partes = jws.split('.');
  if (partes.length !== 3) {
    throw new Error('JWS mal formado (esperava 3 partes separadas por ".")');
  }
  return JSON.parse(Buffer.from(partes[1], 'base64url').toString('utf-8'));
}

/**
 * Tenta verificar em Produção e, se falhar, em Sandbox — mesmo motivo do
 * fallback de ambiente em `buscarStatusNaAppStore`: uma compra feita por
 * conta de sandbox/TestFlight chega no mesmo endpoint, e não dá pra saber
 * o ambiente antes de abrir o payload.
 *
 * Devolve `{ payload, verificado }`. `verificado: false` significa que a
 * assinatura não pôde ser conferida (certificados ausentes) e o payload
 * veio de decode simples — quem chama decide o que fazer com isso.
 */
async function verificar<T>(
  jws: string,
  executar: (v: SignedDataVerifier, jws: string) => Promise<T>,
  rotulo: string,
): Promise<{ payload: any; verificado: boolean }> {
  if (!verificacaoDisponivel()) {
    return { payload: decodificarPayloadJws(jws), verificado: false };
  }

  const erros: unknown[] = [];
  for (const ambiente of [Environment.PRODUCTION, Environment.SANDBOX]) {
    const verificador = obterVerificador(ambiente);
    if (!verificador) continue;
    try {
      const payload = await executar(verificador, jws);
      return { payload, verificado: true };
    } catch (e) {
      erros.push(e);
    }
  }

  // Assinatura inválida nos dois ambientes: isso é uma falha real, não um
  // detalhe de configuração. Não caímos pro decode aqui — quem chama
  // precisa rejeitar.
  const detalhe = erros.map((e) => (e instanceof Error ? e.message : String(e))).join(' | ');
  throw new Error(`Assinatura ${rotulo} inválida (produção e sandbox): ${detalhe}`);
}

/** Notificação App Store Server V2 (`signedPayload` do corpo do POST). */
export function verificarNotificacao(signedPayload: string) {
  return verificar(
    signedPayload,
    (v, jws) => v.verifyAndDecodeNotification(jws) as Promise<any>,
    'da notificação',
  );
}

/** Transação StoreKit2 mandada pelo app (`signedTransactionInfo`). */
export function verificarTransacao(signedTransactionInfo: string) {
  return verificar(
    signedTransactionInfo,
    (v, jws) => v.verifyAndDecodeTransaction(jws) as Promise<any>,
    'da transação',
  );
}
