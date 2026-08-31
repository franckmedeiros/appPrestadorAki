/**
 * Assinatura mensal do prestador (Google Play Billing) — único gate pra
 * "virar prestador" de verdade: sem assinatura ativa, a conta nunca ganha
 * `providers/{uid}` nem aparece em `providerDirectory` (ver README/
 * DATA_MODEL.md, decisão combinada com o Franck — mesmo desenho já usado
 * no app Resenha pra "criar uma resenha").
 *
 * Duas entradas, pelo mesmo caminho de verificação:
 * 1. `confirmarAssinaturaPrestador` (callable) — chamada pelo app logo
 *    depois de uma compra/restauração no Google Play, com o
 *    `purchaseToken` que o `in_app_purchase` devolveu.
 * 2. `processarNotificacaoPlay` (Pub/Sub) — Real-time Developer
 *    Notifications da própria Play Store, disparada sozinha quando o
 *    ESTADO de uma assinatura muda (renovou, atrasou, cancelou, expirou)
 *    — é isso que tira um prestador da busca automaticamente se ele
 *    parar de pagar, sem precisar que o app esteja aberto nem que
 *    ninguém mexa em nada na mão (ver runbook em RUNBOOK_ASSINATURA.md).
 *
 * As duas SEMPRE re-consultam o estado real na Google Play Developer API
 * (nunca confiam soltas no que o app ou a notificação dizem) — é a
 * mesma prática recomendada pela própria Google, porque o payload da
 * notificação avisa só "algo mudou", não qual é o estado atual de fato.
 *
 * A chave da service account NUNCA fica no código nem no repositório —
 * fica no Secret Manager do Firebase (`PLAY_SERVICE_ACCOUNT_KEY`), e essa
 * service account precisa ter sido convidada em Play Console > Usuários e
 * permissões, com "Ver dados financeiros..." e "Gerenciar pedidos e
 * assinaturas" (ver RUNBOOK_ASSINATURA.md pro passo a passo completo).
 */

import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { onMessagePublished } from 'firebase-functions/v2/pubsub';
import { defineSecret } from 'firebase-functions/params';
import { GoogleAuth } from 'google-auth-library';
import { FieldValue, Timestamp } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';
import { db } from './lib/admin';

const playServiceAccountKey = defineSecret('PLAY_SERVICE_ACCOUNT_KEY');

// Precisa bater exatamente com o applicationId de android/app/build.gradle.kts.
const PACKAGE_NAME = 'com.opoutsourcing.prestadoraki';

// Precisa bater com o ID do produto cadastrado em Monetizar > Assinaturas
// no Play Console (ver RUNBOOK_ASSINATURA.md).
const SUBSCRIPTION_PRODUCT_ID = 'prestadoraki_assinatura_mensal';

// Nome do tópico Pub/Sub configurado em Play Console > Configuração de
// monetização > Notificações em tempo real do desenvolvedor.
const RTDN_TOPIC = 'play-subscriptions';

// Estados em que a assinatura ainda conta como "ativa" pro app — inclui a
// carência (pagamento de renovação recusado, mas a Google ainda dá um
// tempo pra pessoa resolver antes de cortar de vez).
const ESTADOS_ATIVOS = new Set(['SUBSCRIPTION_STATE_ACTIVE', 'SUBSCRIPTION_STATE_IN_GRACE_PERIOD']);

interface PlaySubscriptionLineItem {
  productId?: string;
  expiryTime?: string;
}

interface PlaySubscriptionData {
  subscriptionState?: string;
  lineItems?: PlaySubscriptionLineItem[];
}

/** Consulta a Play Developer API (subscriptionsv2) pra saber o estado real da assinatura. */
async function buscarAssinaturaNaPlayStore(
  purchaseToken: string,
  credentials: Record<string, unknown>,
): Promise<PlaySubscriptionData> {
  const auth = new GoogleAuth({
    credentials,
    scopes: ['https://www.googleapis.com/auth/androidpublisher'],
  });
  const client = await auth.getClient();
  const url =
    'https://androidpublisher.googleapis.com/androidpublisher/v3' +
    `/applications/${PACKAGE_NAME}/purchases/subscriptionsv2/tokens/` +
    encodeURIComponent(purchaseToken);
  const resposta = await client.request({ url });
  return resposta.data as PlaySubscriptionData;
}

function lerCredenciais(): Record<string, unknown> {
  try {
    return JSON.parse(playServiceAccountKey.value());
  } catch (e) {
    logger.error('PLAY_SERVICE_ACCOUNT_KEY inválida/ausente', e);
    throw new HttpsError('internal', 'Configuração da service account inválida no servidor.');
  }
}

/**
 * Aplica o estado já consultado na Play Developer API: liga/desliga
 * `providers/{uid}.listingStatus` e a visibilidade da entrada em
 * `providerDirectory/{uid}`.
 *
 * Decisão consciente: quando a assinatura para de valer, a entrada do
 * diretório NÃO é apagada — só marcada `visible: false` (ver
 * ProviderDirectoryRepository.search, que filtra isso na busca). Apagar
 * perderia `ratingAverage`/`ratingCount` (agregados no próprio documento,
 * não na subcoleção de avaliações) — se a pessoa assinar de novo depois,
 * a reputação dela deveria continuar de onde parou, não voltar a zero.
 *
 * Só CRIA `providers/{uid}`/`providerDirectory/{uid}` pela primeira vez
 * quando `category`/`city` chegam junto (só acontece na primeira
 * confirmação de compra, vinda de `confirmarAssinaturaPrestador` — ver
 * abaixo); a notificação do Pub/Sub nunca manda esses campos, então
 * nunca cria nada do zero — só atualiza quem já existe.
 */
async function aplicarEstadoDaAssinatura(
  uid: string,
  dadosAssinatura: PlaySubscriptionData,
  dadosNovoProvider?: { category: string; city: string; state?: string },
): Promise<boolean> {
  const linha = (dadosAssinatura.lineItems || [])[0];
  const ativa = ESTADOS_ATIVOS.has(dadosAssinatura.subscriptionState ?? '');
  const expiraEm = linha?.expiryTime ? Timestamp.fromDate(new Date(linha.expiryTime)) : null;

  const providerRef = db.collection('providers').doc(uid);
  const providerSnap = await providerRef.get();

  if (!providerSnap.exists && !dadosNovoProvider) {
    // Notificação/confirmação pra um uid que ainda não tem
    // providers/{uid} e não veio junto com os dados pra criar um novo —
    // não deveria acontecer no fluxo normal (só a primeira confirmação
    // cria, com dadosNovoProvider preenchido), mas não há o que atualizar.
    logger.warn(`aplicarEstadoDaAssinatura: providers/${uid} não existe e sem dados pra criar.`);
    return ativa;
  }

  const now = FieldValue.serverTimestamp();
  // Ao criar providers/{uid} pela primeira vez, copia os dados
  // "pessoais" já preenchidos em clients/{uid} — nome, e-mail, WhatsApp,
  // endereço, chave Pix, logo. Sem isso, esses campos ficavam pra trás:
  // updateOwnProfile/fetchOwnProfileData passam a ler/gravar em
  // providers/{uid} assim que a conta vira prestador, e esse documento
  // novo nascia só com category/city/state, fazendo o resto sumir da
  // tela (mesmo bug que o Franck notou no caminho de teste via
  // AuthController.becomeProvider, corrigido lá do mesmo jeito).
  const dadosDoCliente =
    dadosNovoProvider && !providerSnap.exists
      ? (await db.collection('clients').doc(uid).get()).data() ?? {}
      : {};
  const camposPessoais = [
    'name',
    'email',
    'whatsapp',
    'addressZipCode',
    'addressStreet',
    'addressNeighborhood',
    'addressCity',
    'addressState',
    'pixKey',
    'logoUrl',
  ] as const;
  const copiaDoCliente: Record<string, unknown> = {};
  for (const campo of camposPessoais) {
    if (dadosDoCliente[campo] != null) copiaDoCliente[campo] = dadosDoCliente[campo];
  }
  await providerRef.set(
    {
      ...(dadosNovoProvider && !providerSnap.exists
        ? {
            ...copiaDoCliente,
            category: dadosNovoProvider.category,
            city: dadosNovoProvider.city,
            ...(dadosNovoProvider.state ? { state: dadosNovoProvider.state } : {}),
            nextBudgetNumber: 1,
            createdAt: now,
          }
        : {}),
      listingStatus: ativa ? 'active' : 'pending',
      subscriptionState: dadosAssinatura.subscriptionState ?? null,
      subscriptionExpiresAt: expiraEm,
      updatedAt: now,
    },
    { merge: true },
  );

  const directoryRef = db.collection('providerDirectory').doc(uid);
  if (ativa) {
    const provider = (await providerRef.get()).data() ?? {};
    if (provider.category && provider.city) {
      const directorySnap = await directoryRef.get();
      await directoryRef.set(
        {
          name: provider.name,
          category: provider.category,
          city: provider.city,
          ...(provider.state ? { state: provider.state } : {}),
          claimed: true,
          providerUid: uid,
          visible: true,
          updatedAt: now,
          ...(directorySnap.exists ? {} : { createdAt: now }),
        },
        { merge: true },
      );
    }
  } else {
    await directoryRef.set({ visible: false, updatedAt: now }, { merge: true });
  }

  return ativa;
}

export const confirmarAssinaturaPrestador = onCall(
  { secrets: [playServiceAccountKey] },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Faça login primeiro.');
    }

    const { purchaseToken, productId, category, city, state } = (request.data ?? {}) as {
      purchaseToken?: string;
      productId?: string;
      category?: string;
      city?: string;
      state?: string;
    };
    if (!purchaseToken || typeof purchaseToken !== 'string' || !productId) {
      throw new HttpsError('invalid-argument', 'Faltam dados da compra (purchaseToken/productId).');
    }
    if (productId !== SUBSCRIPTION_PRODUCT_ID) {
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

    // Impede reaproveitar o token de compra de outra conta (ex.: alguém
    // copiando o token de outra pessoa pra tentar ganhar a assinatura de
    // graça).
    const tokenRef = db.collection('assinaturasVerificadas').doc(purchaseToken);
    const tokenSnap = await tokenRef.get();
    if (tokenSnap.exists && tokenSnap.data()?.uid !== uid) {
      throw new HttpsError('permission-denied', 'Essa compra já está associada a outra conta.');
    }

    const credentials = lerCredenciais();

    let dadosAssinatura: PlaySubscriptionData;
    try {
      dadosAssinatura = await buscarAssinaturaNaPlayStore(purchaseToken, credentials);
    } catch (e) {
      logger.error('Falha ao consultar a Play Developer API', e);
      throw new HttpsError('internal', 'Não foi possível confirmar a compra junto à Play Store.');
    }

    await tokenRef.set(
      { uid, productId, subscriptionState: dadosAssinatura.subscriptionState ?? null, atualizadoEm: Timestamp.now() },
      { merge: true },
    );

    const ativa = await aplicarEstadoDaAssinatura(
      uid,
      dadosAssinatura,
      providerJaExiste ? undefined : { category: category!, city: city!, state },
    );

    if (!ativa) {
      throw new HttpsError(
        'failed-precondition',
        `Assinatura não está ativa (status: ${dadosAssinatura.subscriptionState}).`,
      );
    }

    return { ativa: true };
  },
);

export const processarNotificacaoPlay = onMessagePublished(
  { topic: RTDN_TOPIC, secrets: [playServiceAccountKey] },
  async (event) => {
    const dataBase64 = event.data.message.data;
    if (!dataBase64) return;

    const payload = JSON.parse(Buffer.from(dataBase64, 'base64').toString('utf-8'));
    const notification = payload?.subscriptionNotification;
    if (!notification?.purchaseToken) {
      // Notificações de teste ("health check") ou de outro tipo (ex.:
      // voucher) não têm subscriptionNotification — nada a fazer aqui.
      logger.info('Notificação da Play sem subscriptionNotification — ignorando.', payload);
      return;
    }

    const tokenRef = db.collection('assinaturasVerificadas').doc(notification.purchaseToken);
    const tokenSnap = await tokenRef.get();
    if (!tokenSnap.exists) {
      // Lacuna consciente (mesma do app Resenha): se essa notificação
      // chegar ANTES do app ter chamado confirmarAssinaturaPrestador pela
      // primeira vez pra esse token, ainda não sabemos de qual uid é —
      // não tem o que atualizar ainda. A própria confirmação, quando
      // chegar, já busca o estado atual na API na hora.
      logger.warn('Notificação da Play pra um purchaseToken ainda não conhecido — ignorando.');
      return;
    }
    const uid = tokenSnap.data()!.uid as string;

    const credentials = lerCredenciais();

    let dadosAssinatura: PlaySubscriptionData;
    try {
      dadosAssinatura = await buscarAssinaturaNaPlayStore(notification.purchaseToken, credentials);
    } catch (e) {
      logger.error('Falha ao consultar a Play Developer API a partir da notificação', e);
      return;
    }

    await tokenRef.set(
      { subscriptionState: dadosAssinatura.subscriptionState ?? null, atualizadoEm: Timestamp.now() },
      { merge: true },
    );
    await aplicarEstadoDaAssinatura(uid, dadosAssinatura);
  },
);
