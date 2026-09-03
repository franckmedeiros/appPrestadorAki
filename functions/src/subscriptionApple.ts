/**
 * Assinatura mensal do prestador — lado Apple/iOS (StoreKit2 + App Store
 * Server API). Mesmo papel que `subscription.ts` já cumpre pro Google Play
 * (ver o comentário no topo de lá) — o app agora lança nos dois ao mesmo
 * tempo (Franck: "vou lançar nos dois já, na real estou testando no
 * android e ios"), então precisa da mesma proteção nos dois lados: sem
 * assinatura ativa confirmada pela própria Apple, a conta nunca ganha
 * `providers/{uid}` nem aparece em `providerDirectory`.
 *
 * Duas entradas, pelo mesmo caminho de verificação do lado Google:
 * 1. `confirmarAssinaturaPrestadorApple` (callable) — chamada pelo app
 *    logo depois de uma compra/restauração no App Store, com o JWS da
 *    transação que o `in_app_purchase` devolveu (StoreKit2).
 * 2. `processarNotificacaoApple` (HTTPS) — App Store Server Notifications
 *    V2, disparada sozinha pela própria Apple quando o ESTADO de uma
 *    assinatura muda (renovou, atrasou, cancelou, expirou) — mesmo papel
 *    da RTDN do Google, só que chega como POST direto nessa URL (não
 *    Pub/Sub) — ver RUNBOOK_ASSINATURA_APPLE.md pra configurar a URL no
 *    App Store Connect.
 *
 * As duas SEMPRE re-consultam o estado real na App Store Server API
 * (nunca confiam soltas no que o app ou a notificação dizem) — mesma
 * prática já usada do lado Google.
 *
 * Nota honesta sobre verificação de assinatura JWS: pra verificar
 * CRIPTOGRAFICAMENTE que um JWS (transação ou notificação) veio mesmo da
 * Apple, a biblioteca oficial (`@apple/app-store-server-library`, classe
 * `SignedDataVerifier`) pede os certificados-raiz da Apple (baixados de
 * https://www.apple.com/certificateauthority/) como entrada, embutidos no
 * deploy. O ambiente onde este arquivo foi escrito não tinha acesso de
 * rede pra apple.com pra baixar esses certificados — então, por enquanto,
 * `decodificarPayloadJws` abaixo só faz um base64url-decode do "meio" do
 * JWS, SEM checar a assinatura, e usa isso só pra extrair o
 * `transactionId`/`originalTransactionId` (ou seja: só pra saber QUAL
 * assinatura ir perguntar pra Apple). A fonte de verdade de fato continua
 * sendo a resposta da própria App Store Server API, chamada com um JWT
 * assinado por NÓS (`AppStoreServerAPIClient`, autenticado com a chave do
 * secret abaixo) por HTTPS — exatamente a mesma decisão de design já
 * usada pro Google (a Play Developer API também não tem a resposta
 * verificada por assinatura extra, só HTTPS + autenticação da nossa
 * service account). Mesmo que alguém forje o corpo de uma
 * notificação/transação com o transactionId de outra pessoa, tudo que
 * isso consegue é fazer a gente reconsultar pra própria Apple qual é o
 * estado VERDADEIRO daquele transactionId (e, se não achar o uid dono
 * dele em `assinaturasVerificadas`, a notificação é ignorada — mesma
 * "lacuna consciente" do lado Google) — nunca força um estado "ativo"
 * falso. Se um dia quiser fechar essa lacuna de verdade, baixe os
 * certificados-raiz e passe pra um `SignedDataVerifier`.
 *
 * A chave da App Store Connect NUNCA fica no código nem no repositório —
 * fica no Secret Manager do Firebase (`APPLE_APP_STORE_CONNECT_KEY`, um
 * JSON com `issuerId`/`keyId`/`privateKey` — ver
 * RUNBOOK_ASSINATURA_APPLE.md pro passo a passo completo de como gerar
 * essa chave no App Store Connect).
 */

import { onCall, onRequest, HttpsError } from 'firebase-functions/v2/https';
import { defineSecret } from 'firebase-functions/params';
import { logger } from 'firebase-functions';
import { Timestamp } from 'firebase-admin/firestore';
import {
  AppStoreServerAPIClient,
  APIException,
  APIError,
  Environment,
  Status,
  StatusResponse,
} from '@apple/app-store-server-library';
import { db } from './lib/admin';
import { aplicarEstadoNormalizado, EstadoNormalizado } from './subscription';

const appleAppStoreConnectKey = defineSecret('APPLE_APP_STORE_CONNECT_KEY');

// Precisa bater exatamente com o bundle identifier do app no Xcode/App
// Store Connect (mesmo valor usado em `iosBundleId` de
// lib/firebase_options.dart e no `PACKAGE_NAME` do lado Google).
const APPLE_BUNDLE_ID = 'com.opoutsourcing.prestadoraki';

// Precisa bater com o ID do produto cadastrado em Monetização > Assinaturas
// no App Store Connect (ver RUNBOOK_ASSINATURA_APPLE.md) — mesmo ID já
// usado do lado Google (`SubscriptionService.assinaturaMensalId` no app),
// só que cada loja tem seu próprio catálogo de produtos, então não há
// conflito em reaproveitar o mesmo texto.
const APPLE_SUBSCRIPTION_PRODUCT_ID = 'prestadoraki_assinatura_mensal';

// Estados em que a assinatura ainda conta como "ativa" pro app — mesma
// política já usada do lado Google (ESTADOS_ATIVOS em subscription.ts):
// paga em dia OU em carência (BILLING_GRACE_PERIOD) contam; em nova
// tentativa de cobrança (BILLING_RETRY, sem carência concedida ainda) não.
const APPLE_ESTADOS_ATIVOS = new Set<Status>([Status.ACTIVE, Status.BILLING_GRACE_PERIOD]);

interface CredenciaisAppStoreConnect {
  issuerId: string;
  keyId: string;
  privateKey: string;
}

function lerCredenciaisApple(): CredenciaisAppStoreConnect {
  try {
    const dados = JSON.parse(appleAppStoreConnectKey.value());
    if (!dados.issuerId || !dados.keyId || !dados.privateKey) {
      throw new Error('faltam issuerId/keyId/privateKey no secret');
    }
    return dados as CredenciaisAppStoreConnect;
  } catch (e) {
    logger.error('APPLE_APP_STORE_CONNECT_KEY inválida/ausente', e);
    throw new HttpsError('internal', 'Configuração da App Store Connect inválida no servidor.');
  }
}

function criarCliente(
  credenciais: CredenciaisAppStoreConnect,
  environment: Environment,
): AppStoreServerAPIClient {
  return new AppStoreServerAPIClient(
    credenciais.privateKey,
    credenciais.keyId,
    credenciais.issuerId,
    APPLE_BUNDLE_ID,
    environment,
  );
}

/**
 * Decodifica (SEM verificar assinatura — ver nota honesta no topo do
 * arquivo) o "payload" (parte do meio) de um JWS de 3 partes
 * (header.payload.assinatura) — formato usado tanto pelas transações
 * (`JWSTransaction`) quanto pelo `signedPayload` das notificações da
 * Apple.
 */
function decodificarPayloadJws(jws: string): any {
  const partes = jws.split('.');
  if (partes.length !== 3) {
    throw new Error('JWS mal formado (esperava 3 partes separadas por ".")');
  }
  const json = Buffer.from(partes[1], 'base64url').toString('utf-8');
  return JSON.parse(json);
}

/**
 * Consulta "Get All Subscription Statuses" — tenta primeiro em Produção;
 * se a Apple responder "transação não encontrada" (sinal de que o
 * transactionId foi gerado no Sandbox), tenta de novo em Sandbox. Esse
 * fallback é a prática recomendada pela própria Apple pra suportar
 * "testar em produção" (compra feita com conta de sandbox/TestFlight) sem
 * precisar saber de antemão em qual ambiente aquela transação foi feita —
 * mesmo modelo do runbook do Google (testadores de licença/teste interno
 * usam o MESMO fluxo de produção).
 */
async function buscarStatusNaAppStore(
  transactionId: string,
  credenciais: CredenciaisAppStoreConnect,
): Promise<StatusResponse> {
  try {
    return await criarCliente(credenciais, Environment.PRODUCTION).getAllSubscriptionStatuses(
      transactionId,
    );
  } catch (e) {
    const ambienteErrado =
      e instanceof APIException &&
      (e.apiError === APIError.TRANSACTION_ID_NOT_FOUND ||
        e.apiError === APIError.ORIGINAL_TRANSACTION_ID_NOT_FOUND);
    if (!ambienteErrado) throw e;
    return criarCliente(credenciais, Environment.SANDBOX).getAllSubscriptionStatuses(transactionId);
  }
}

/**
 * Reduz uma `StatusResponse` (pode trazer vários grupos/transações — uma
 * conta só devia ter uma assinatura ativa do nosso produto, mas a API é
 * genérica pra qualquer app) à transação mais recente do produto que
 * interessa aqui.
 */
function extrairUltimaTransacao(
  statusResponse: StatusResponse,
  productId: string,
): { status?: Status | number; transacao: any } | null {
  for (const grupo of statusResponse.data ?? []) {
    for (const item of grupo.lastTransactions ?? []) {
      if (!item.signedTransactionInfo) continue;
      const transacao = decodificarPayloadJws(item.signedTransactionInfo);
      if (transacao.productId === productId) {
        return { status: item.status, transacao };
      }
    }
  }
  return null;
}

function paraEstadoNormalizado(item: { status?: Status | number; transacao: any } | null): EstadoNormalizado {
  if (!item) {
    return { ativa: false, expiraEm: null, rawState: 'SEM_TRANSACAO', loja: 'apple' };
  }
  const ativa = APPLE_ESTADOS_ATIVOS.has(item.status as Status);
  const expiraEm =
    typeof item.transacao?.expiresDate === 'number'
      ? Timestamp.fromMillis(item.transacao.expiresDate)
      : null;
  const rawState = typeof item.status === 'number' ? Status[item.status] ?? String(item.status) : 'DESCONHECIDO';
  return { ativa, expiraEm, rawState, loja: 'apple' };
}

export const confirmarAssinaturaPrestadorApple = onCall(
  { secrets: [appleAppStoreConnectKey] },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Faça login primeiro.');
    }

    const { signedTransactionInfo, productId, category, city, state } = (request.data ?? {}) as {
      signedTransactionInfo?: string;
      productId?: string;
      category?: string;
      city?: string;
      state?: string;
    };
    if (!signedTransactionInfo || typeof signedTransactionInfo !== 'string' || !productId) {
      throw new HttpsError(
        'invalid-argument',
        'Faltam dados da compra (signedTransactionInfo/productId).',
      );
    }
    if (productId !== APPLE_SUBSCRIPTION_PRODUCT_ID) {
      throw new HttpsError('invalid-argument', 'Produto de assinatura desconhecido.');
    }

    const uid = request.auth.uid;
    const providerJaExiste = (await db.collection('providers').doc(uid).get()).exists;
    if (!providerJaExiste && (!category || !city)) {
      throw new HttpsError(
        'invalid-argument',
        'Faltam categoria/cidade pra criar o cadastro de prestador.',
      );
    }

    let transactionId: string | undefined;
    try {
      const decodificado = decodificarPayloadJws(signedTransactionInfo);
      transactionId = decodificado.originalTransactionId ?? decodificado.transactionId;
    } catch (e) {
      logger.error('signedTransactionInfo mal formado', e);
    }
    if (!transactionId) {
      throw new HttpsError('invalid-argument', 'Dados da compra inválidos.');
    }

    // Impede reaproveitar a transação de outra conta — mesmo cuidado já
    // tomado do lado Google com `assinaturasVerificadas` (prefixo `apple:`
    // só pra nunca colidir com um purchaseToken do Google no mesmo id).
    const tokenRef = db.collection('assinaturasVerificadas').doc(`apple:${transactionId}`);
    const tokenSnap = await tokenRef.get();
    if (tokenSnap.exists && tokenSnap.data()?.uid !== uid) {
      throw new HttpsError('permission-denied', 'Essa compra já está associada a outra conta.');
    }

    const credenciais = lerCredenciaisApple();
    let statusResponse: StatusResponse;
    try {
      statusResponse = await buscarStatusNaAppStore(transactionId, credenciais);
    } catch (e) {
      logger.error('Falha ao consultar a App Store Server API', e);
      throw new HttpsError('internal', 'Não foi possível confirmar a compra junto à App Store.');
    }

    const estado = paraEstadoNormalizado(extrairUltimaTransacao(statusResponse, productId));

    await tokenRef.set(
      { uid, productId, subscriptionState: estado.rawState, atualizadoEm: Timestamp.now() },
      { merge: true },
    );

    const ativa = await aplicarEstadoNormalizado(
      uid,
      estado,
      providerJaExiste ? undefined : { category: category!, city: city!, state },
    );

    if (!ativa) {
      throw new HttpsError('failed-precondition', `Assinatura não está ativa (status: ${estado.rawState}).`);
    }

    return { ativa: true };
  },
);

export const processarNotificacaoApple = onRequest(
  { secrets: [appleAppStoreConnectKey] },
  async (req, res) => {
    const signedPayload = (req.body ?? {}).signedPayload;
    if (typeof signedPayload !== 'string') {
      // Provavelmente a "chamada de teste" que o App Store Connect faz ao
      // salvar a URL pela primeira vez, ou uma requisição fora do formato
      // esperado — nada a processar.
      logger.info('Notificação da Apple sem signedPayload — ignorando.');
      res.status(200).send('ok');
      return;
    }

    let payload: any;
    try {
      payload = decodificarPayloadJws(signedPayload);
    } catch (e) {
      logger.error('Notificação da Apple mal formada', e);
      res.status(400).send('payload inválido');
      return;
    }

    const signedTransactionInfo = payload?.data?.signedTransactionInfo;
    if (typeof signedTransactionInfo !== 'string') {
      // Notificações sem transação (ex.: TEST, EXTERNAL_PURCHASE_TOKEN,
      // RESCIND_CONSENT) — nada a atualizar aqui.
      logger.info(
        `Notificação da Apple (${payload?.notificationType ?? '?'}) sem signedTransactionInfo — ignorando.`,
      );
      res.status(200).send('ok');
      return;
    }

    let transactionId: string | undefined;
    try {
      const transacao = decodificarPayloadJws(signedTransactionInfo);
      transactionId = transacao.originalTransactionId ?? transacao.transactionId;
    } catch (e) {
      logger.error('signedTransactionInfo da notificação mal formado', e);
      res.status(400).send('transação inválida');
      return;
    }
    if (!transactionId) {
      res.status(200).send('ok');
      return;
    }

    const tokenRef = db.collection('assinaturasVerificadas').doc(`apple:${transactionId}`);
    const tokenSnap = await tokenRef.get();
    if (!tokenSnap.exists) {
      // Mesma "lacuna consciente" do lado Google (ver subscription.ts):
      // se a notificação chegar antes da primeira confirmação pra essa
      // transação, ainda não sabemos de qual uid é — a própria
      // confirmação, quando chegar, já busca o estado atual na hora.
      logger.warn('Notificação da Apple pra uma transação ainda não conhecida — ignorando.');
      res.status(200).send('ok');
      return;
    }
    const uid = tokenSnap.data()!.uid as string;

    const credenciais = lerCredenciaisApple();
    let statusResponse: StatusResponse;
    try {
      statusResponse = await buscarStatusNaAppStore(transactionId, credenciais);
    } catch (e) {
      logger.error('Falha ao consultar a App Store Server API a partir da notificação', e);
      res.status(500).send('erro ao consultar a App Store');
      return;
    }

    const estado = paraEstadoNormalizado(
      extrairUltimaTransacao(statusResponse, APPLE_SUBSCRIPTION_PRODUCT_ID),
    );

    await tokenRef.set(
      { subscriptionState: estado.rawState, atualizadoEm: Timestamp.now() },
      { merge: true },
    );
    await aplicarEstadoNormalizado(uid, estado);

    res.status(200).send('ok');
  },
);
