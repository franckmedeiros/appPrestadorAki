/**
 * Assinatura mensal do prestador (Google Play Billing) — único gate pra
 * "virar prestador" de verdade: sem assinatura ativa, a conta nunca ganha
 * `providers/{uid}` nem aparece em `providerDirectory` (ver README/
 * DATA_MODEL.md, decisão combinada com o Franck — mesmo desenho já usado
 * no app Resenha pra "criar uma resenha").
 *
 * ESTE ARQUIVO é só o lado Google/Android — o app agora lança nos dois
 * (Franck: "vou lançar nos dois já"), então tem um arquivo irmão,
 * `subscriptionApple.ts`, com a mesma função pro iOS (App Store Server
 * API em vez de Play Developer API). Os dois terminam no mesmo lugar:
 * `aplicarEstadoNormalizado` (definida aqui embaixo, exportada pro outro
 * arquivo importar) — é ela quem de fato liga/desliga
 * `providers/{uid}.listingStatus` e a entrada em `providerDirectory`,
 * independente de qual loja confirmou a compra.
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
 * O lado Apple segue a MESMA filosofia (ver o comentário no topo de
 * `subscriptionApple.ts`).
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
    throw new HttpsError('unavailable', 'Configuração da service account inválida no servidor.');
  }
}

/** Só dígitos — mesma normalização usada em `phoneIndex`/`AuthController._normalizePhone` (lado do app, ver lib/core/text_normalize.dart normalizePhoneDigits). */
function normalizarTelefone(telefone: string): string {
  return telefone.replace(/[^0-9]/g, '');
}

/**
 * "Carga inicial" (pedido do Franck): antes do prestador ter conta própria,
 * ele já pode estar listado em `providerDirectory` com `claimed: false`
 * (importação em massa/curadoria manual — só nome + WhatsApp, feita ANTES
 * de convidar a pessoa pra assinar). Quando essa pessoa finalmente se
 * cadastra e a assinatura é confirmada pela primeira vez, o único dado em
 * comum entre o convite (nome + WhatsApp que o Franck já tinha) e a conta
 * nova é o TELEFONE — o nome pode vir digitado diferente no cadastro, mas
 * o WhatsApp é o mesmo. Por isso o casamento é feito por telefone, igual
 * ao mesmo truque já usado pra achar cliente existente
 * (CustomersRepository.findOrCreateForClient / phoneIndex).
 *
 * Só é chamada na criação do `providerDirectory/{uid}` pela primeira vez
 * (ver `aplicarEstadoDaAssinatura` abaixo) — depois disso o dono já é o
 * próprio uid, não tem mais o que "reivindicar". Quando acha uma entrada
 * não reivindicada com o mesmo telefone: migra a reputação que a
 * curadoria já tinha acumulado (bio + avaliações, com a subcoleção
 * `ratings` inteira) pra debaixo do novo doc (uid) e apaga a entrada
 * antiga — sem isso, ficariam DUAS entradas pra a mesma pessoa na busca
 * (a antiga órfã "não reivindicada" e a nova "reivindicada").
 *
 * Nota honesta: exige que a entrada da carga inicial tenha os campos
 * `claimed: false` (explícito — Firestore não casa `==` com campo
 * ausente) e `phoneNormalized` (só dígitos, mesma normalização acima).
 * Sem os dois, essa entrada nunca é encontrada aqui e fica órfã pra
 * sempre, precisando de limpeza manual. Se mais de uma entrada não
 * reivindicada tiver o mesmo telefone (duplicidade na carga inicial),
 * só a primeira é reivindicada — as demais ficam pra trás (logado como
 * aviso) e precisam de limpeza manual também.
 */
async function reivindicarListagemPorTelefone(
  uid: string,
  whatsapp: string | undefined,
): Promise<{ bio?: string; ratingAverage?: number; ratingCount?: number } | null> {
  if (!whatsapp) return null;
  const normalizado = normalizarTelefone(whatsapp);
  if (!normalizado) return null;

  const query = await db
    .collection('providerDirectory')
    .where('claimed', '==', false)
    .where('phoneNormalized', '==', normalizado)
    .get();
  if (query.empty) return null;
  if (query.size > 1) {
    logger.warn(
      `reivindicarListagemPorTelefone: ${query.size} entradas não reivindicadas com o telefone ${normalizado} — reivindicando só a primeira (${query.docs[0].id}), as demais precisam de limpeza manual.`,
    );
  }

  const antigaRef = query.docs[0].ref;
  const antigaData = query.docs[0].data();
  logger.info(
    `Reivindicando listagem ${antigaRef.id} (carga inicial) pro novo prestador ${uid}, casados pelo telefone ${normalizado}.`,
  );

  // Migra as avaliações já feitas na entrada antiga — mesmo id de doc
  // (chaveado pelo uid de quem avaliou), pra preservar "já avaliei esse
  // prestador" e não deixar ninguém avaliar duas vezes.
  const avaliacoesSnap = await antigaRef.collection('ratings').get();
  const novaRef = db.collection('providerDirectory').doc(uid);
  const batch = db.batch();
  for (const avaliacaoDoc of avaliacoesSnap.docs) {
    batch.set(novaRef.collection('ratings').doc(avaliacaoDoc.id), avaliacaoDoc.data());
    batch.delete(avaliacaoDoc.ref);
  }
  batch.delete(antigaRef);
  await batch.commit();

  return {
    bio: typeof antigaData.bio === 'string' ? antigaData.bio : undefined,
    ratingAverage: typeof antigaData.ratingAverage === 'number' ? antigaData.ratingAverage : undefined,
    ratingCount: typeof antigaData.ratingCount === 'number' ? antigaData.ratingCount : undefined,
  };
}

export interface EstadoNormalizado {
  ativa: boolean;
  expiraEm: Timestamp | null;
  /**
   * Texto cru do estado, só pra guardar em `providers/{uid}.subscriptionState`
   * e pra depuração/suporte — cada loja tem o próprio vocabulário (ver
   * `ESTADOS_ATIVOS` aqui pro do Google e `APPLE_ESTADOS_ATIVOS` em
   * `subscriptionApple.ts` pro da Apple).
   */
  rawState: string;
  /** Qual loja gerou esse estado — grava em `providers/{uid}.subscriptionStore`, útil pra suporte saber onde olhar (Play Console x App Store Connect) sem precisar perguntar pro prestador. */
  loja: 'google' | 'apple';
}

/**
 * Aplica um estado de assinatura JÁ normalizado e já consultado na loja de
 * verdade (Play Developer API ou App Store Server API — ver
 * `aplicarEstadoDaAssinatura` abaixo pro adaptador do Google e
 * `subscriptionApple.ts` pro da Apple): liga/desliga
 * `providers/{uid}.listingStatus` e a visibilidade da entrada em
 * `providerDirectory/{uid}`. Compartilhado pelas duas lojas — pra nunca
 * ter duas cópias deste pedaço (criação de `providers/{uid}`, reivindicação
 * por telefone, sincronização do diretório) divergindo uma da outra com o
 * tempo.
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
 * confirmação de compra, vinda de `confirmarAssinaturaPrestador`/
 * `confirmarAssinaturaPrestadorApple`); a notificação de renovação/mudança
 * de estado (RTDN do Google ou Server Notifications V2 da Apple) nunca
 * manda esses campos, então nunca cria nada do zero — só atualiza quem já
 * existe.
 */
export async function aplicarEstadoNormalizado(
  uid: string,
  estado: EstadoNormalizado,
  dadosNovoProvider?: { category: string; city: string; state?: string },
): Promise<boolean> {
  const { ativa, expiraEm } = estado;

  const providerRef = db.collection('providers').doc(uid);
  const providerSnap = await providerRef.get();

  if (!providerSnap.exists && !dadosNovoProvider) {
    // Notificação/confirmação pra um uid que ainda não tem
    // providers/{uid} e não veio junto com os dados pra criar um novo —
    // não deveria acontecer no fluxo normal (só a primeira confirmação
    // cria, com dadosNovoProvider preenchido), mas não há o que atualizar.
    logger.warn(`aplicarEstadoNormalizado: providers/${uid} não existe e sem dados pra criar.`);
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
            categories: [dadosNovoProvider.category],
            city: dadosNovoProvider.city,
            ...(dadosNovoProvider.state ? { state: dadosNovoProvider.state } : {}),
            nextBudgetNumber: 1,
            createdAt: now,
          }
        : {}),
      listingStatus: ativa ? 'active' : 'pending',
      subscriptionState: estado.rawState,
      subscriptionStore: estado.loja,
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
      // Só tenta "reivindicar" uma entrada da carga inicial na PRIMEIRA
      // vez que este prestador ganha um `providerDirectory/{uid}` — uma
      // renovação de assinatura (este mesmo bloco roda a cada notificação
      // da Play Store) já encontra o doc existente, não tem mais o que
      // procurar (ver reivindicarListagemPorTelefone acima).
      const reivindicada = directorySnap.exists
        ? null
        : await reivindicarListagemPorTelefone(uid, provider.whatsapp);
      // `categories` (lista) é o formato novo — pedido do Franck:
      // prestador pode atuar em 2+ categorias. Cai pro `category`
      // singular antigo quando o documento ainda não tem o campo novo
      // (nunca editou o perfil desde essa mudança) — sem esse fallback,
      // uma renovação de assinatura (este mesmo bloco roda a cada
      // notificação da Play Store, não só na primeira confirmação)
      // "resetaria" um prestador multi-categoria de volta pra só a
      // principal, porque este bloco é quem por fim decide o que fica
      // gravado no diretório público.
      const categories: string[] = Array.isArray(provider.categories) && provider.categories.length > 0
        ? provider.categories
        : [provider.category];
      await directoryRef.set(
        {
          name: provider.name,
          categories,
          category: categories[0],
          city: provider.city,
          ...(provider.state ? { state: provider.state } : {}),
          // So mostra o WhatsApp de verdade no card do prestador (ver
          // ProviderListingCard/lib) enquanto a assinatura estiver ativa -
          // pedido do Franck. Guardado no proprio doc publico (em vez de
          // so no app) pra ficar certo mesmo lido direto do Firestore.
          // `phoneNormalized` junto (só dígitos) é o que permite achar
          // essa entrada de novo por telefone no futuro (ver
          // reivindicarListagemPorTelefone).
          ...(provider.whatsapp
            ? { whatsapp: provider.whatsapp, phoneNormalized: normalizarTelefone(String(provider.whatsapp)) }
            : { whatsapp: FieldValue.delete(), phoneNormalized: FieldValue.delete() }),
          // Reputação herdada da entrada da carga inicial reivindicada
          // agora (bio/avaliações que a curadoria já tinha acumulado) —
          // só entra se achou uma pra reivindicar; do contrário este
          // prestador começa do zero, como sempre foi.
          ...(reivindicada?.bio ? { bio: reivindicada.bio } : {}),
          ...(reivindicada?.ratingAverage != null ? { ratingAverage: reivindicada.ratingAverage } : {}),
          ...(reivindicada?.ratingCount != null ? { ratingCount: reivindicada.ratingCount } : {}),
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
    await directoryRef.set(
      { visible: false, whatsapp: FieldValue.delete(), updatedAt: now },
      { merge: true },
    );
  }

  return ativa;
}

/**
 * Adaptador do Google: transforma o que a Play Developer API devolve no
 * formato normalizado que `aplicarEstadoNormalizado` (acima) entende, e
 * delega pra lá. Mantido com o mesmo nome de antes pra não mudar as duas
 * chamadas abaixo (`confirmarAssinaturaPrestador`/`processarNotificacaoPlay`).
 */
async function aplicarEstadoDaAssinatura(
  uid: string,
  dadosAssinatura: PlaySubscriptionData,
  dadosNovoProvider?: { category: string; city: string; state?: string },
): Promise<boolean> {
  const linha = (dadosAssinatura.lineItems || [])[0];
  const estado: EstadoNormalizado = {
    ativa: ESTADOS_ATIVOS.has(dadosAssinatura.subscriptionState ?? ''),
    expiraEm: linha?.expiryTime ? Timestamp.fromDate(new Date(linha.expiryTime)) : null,
    rawState: dadosAssinatura.subscriptionState ?? 'DESCONHECIDO',
    loja: 'google',
  };
  return aplicarEstadoNormalizado(uid, estado, dadosNovoProvider);
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
      throw new HttpsError('unavailable', 'Não foi possível confirmar a compra junto à Play Store.');
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
