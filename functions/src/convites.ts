/**
 * PRÉ-CADASTRO COM CONSENTIMENTO (decisão do Franck, 14/10).
 *
 * Problema: abordar prestador pedindo "baixe o app" não converte. O que
 * converte é "tem cliente pedindo o seu serviço". Então:
 *
 *  1. O Franck pergunta no WhatsApp (à mão) se pode incluir a empresa no
 *     PrestadorAki. Quem diz SIM é registrado por
 *     scripts/registrar_convites.js: entrada em `providerDirectory`
 *     (`claimed: false`, `aceitaPedidos: true`, visível na busca, SEM
 *     telefone público) + `convitesPrestador/{listingId}` (privado, só
 *     Admin SDK) com o WhatsApp e a data do consentimento.
 *
 *  2. Um cliente pede orçamento pra essa entrada → o app grava em
 *     `pedidosSemConta/{id}` (ver firestore.rules) → `onPedidoSemContaCriado`
 *     manda um modelo do WhatsApp oficial (mesmo número do EstiloAki) pro
 *     prestador: serviço + bairro/cidade + CÓDIGO. Nunca manda nome nem
 *     telefone do cliente — o contato é o que a assinatura libera.
 *
 *  3. O prestador baixa o app, cria a conta e digita o código
 *     (`reivindicarPerfilPrestador`). O código prova que ele é o dono do
 *     WhatsApp que recebeu o aviso — casar só pelo telefone digitado no
 *     cadastro deixaria qualquer um "tomar" o perfil de outra pessoa.
 *     Nasce `providers/{uid}` (ainda `pending`, sem assinatura) e os
 *     pedidos esperando viram orçamentos `pendente` dele. Ele cai na tela
 *     de assinatura, que mostra os pedidos esperando (sem dados do cliente).
 *
 *  4. Assinou → `aplicarEstadoNormalizado` (subscription.ts) já casa a
 *     entrada antiga pelo `phoneNormalized` e a substitui pela dele, com a
 *     reputação. Nada novo aqui.
 *
 * Segredos (mesmos valores do projeto do EstiloAki — mesmo número):
 *   firebase functions:secrets:set WHATSAPP_TOKEN
 *   firebase functions:secrets:set WHATSAPP_PHONE_ID
 *
 * Modelo a aprovar no WhatsApp Manager (categoria UTILIDADE, pt_BR), nome
 * `prestadoraki_novo_pedido` — texto em scripts/modelo_mensagem_convite.md.
 * O código aparece no aviso como "Número do pedido": com a palavra "código" a
 * Meta classifica o modelo como Autenticação e recusa como Utilidade.
 */
import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { defineSecret } from 'firebase-functions/params';
import { logger } from 'firebase-functions';
import { FieldValue, Timestamp } from 'firebase-admin/firestore';
import { db } from './lib/admin';
import { CATEGORIAS } from './categorias';

const WHATSAPP_TOKEN = defineSecret('WHATSAPP_TOKEN');
const WHATSAPP_PHONE_ID = defineSecret('WHATSAPP_PHONE_ID');

const MODELO_NOVO_PEDIDO = 'prestadoraki_novo_pedido';
const IDIOMA = 'pt_BR';

/**
 * No máximo 1 aviso por prestador a cada 6 h. Vários pedidos seguidos pro
 * mesmo profissional viram um só aviso — economiza (cada modelo é cobrado)
 * e não irrita quem ainda nem conhece o app. O pedido nunca se perde: ele
 * fica guardado e entra junto quando o prestador digitar o código.
 */
const INTERVALO_AVISOS_MS = 6 * 60 * 60 * 1000;

/** "(48) 99999-9999" → "5548999999999". */
function numeroWhatsapp(telefone: unknown): string | null {
  let d = String(telefone ?? '').replace(/\D/g, '');
  if (!d) return null;
  if (!d.startsWith('55') || d.length <= 11) d = '55' + d;
  return d.length >= 12 ? d : null;
}

function rotuloCategoria(id: unknown): string {
  const c = CATEGORIAS.find((x) => x.id === id);
  return c ? c.label : String(id ?? 'serviço');
}

async function enviarModelo(para: string, parametros: string[]): Promise<string | undefined> {
  const url = `https://graph.facebook.com/v25.0/${WHATSAPP_PHONE_ID.value()}/messages`;
  const resp = await fetch(url, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${WHATSAPP_TOKEN.value()}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      messaging_product: 'whatsapp',
      to: para,
      type: 'template',
      template: {
        name: MODELO_NOVO_PEDIDO,
        language: { code: IDIOMA },
        components: [{ type: 'body', parameters: parametros.map((t) => ({ type: 'text', text: t })) }],
      },
    }),
  });
  const corpo = (await resp.json().catch(() => ({}))) as { messages?: { id: string }[]; error?: unknown };
  if (!resp.ok) throw new Error(`WhatsApp ${resp.status}: ${JSON.stringify(corpo.error ?? corpo)}`);
  return corpo.messages?.[0]?.id;
}

/** Código de 6 dígitos que ainda não está em uso por outro convite. */
async function novoCodigo(): Promise<string> {
  for (let i = 0; i < 10; i++) {
    const codigo = String(Math.floor(100000 + Math.random() * 900000));
    const usado = await db.collection('convitesPrestador').where('codigo', '==', codigo).limit(1).get();
    if (usado.empty) return codigo;
  }
  throw new Error('Não foi possível gerar um código livre.');
}

/** Pedido guardado → orçamento `pendente` na subcoleção do prestador. */
async function migrarPedido(
  pedido: FirebaseFirestore.QueryDocumentSnapshot | FirebaseFirestore.DocumentSnapshot,
  uid: string,
): Promise<void> {
  const p = pedido.data() ?? {};
  const budgetRef = db.collection('providers').doc(uid).collection('budgets').doc();
  const agora = FieldValue.serverTimestamp();
  // Mesmos campos de BudgetRequestsRepository.create (app) — o resto do
  // fluxo (push via onBudgetRequestCreated, telas, regras) não sabe que
  // este pedido nasceu antes da conta existir.
  await budgetRef.set({
    customerName: p.clientName ?? 'Cliente',
    date: p.createdAt ?? Timestamp.now(),
    items: [],
    discountCents: 0,
    clientUid: p.clientUid,
    ...(p.clientPhone ? { clientPhone: p.clientPhone } : {}),
    providerUid: uid,
    providerDirectoryId: uid,
    providerName: p.providerName ?? '',
    category: p.category ?? null,
    requestDescription: p.description ?? '',
    addressText: p.addressText ?? '',
    ...(p.preferredDate ? { preferredDate: p.preferredDate } : {}),
    status: 'pendente',
    origemPedidoSemConta: pedido.id,
    createdAt: p.createdAt ?? agora,
    updatedAt: agora,
  });
  await pedido.ref.update({ status: 'migrado', providerUid: uid, budgetId: budgetRef.id, migradoEm: agora });
}

export const onPedidoSemContaCriado = onDocumentCreated(
  { document: 'pedidosSemConta/{pedidoId}', secrets: [WHATSAPP_TOKEN, WHATSAPP_PHONE_ID] },
  async (event) => {
    const snap = event.data;
    const pedido = snap?.data();
    if (!snap || !pedido) return;

    const listingId = String(pedido.listingId ?? '');
    const conviteRef = db.collection('convitesPrestador').doc(listingId);
    const convite = (await conviteRef.get()).data();
    if (!convite) {
      // As regras só deixam criar pra entrada com `aceitaPedidos`, então
      // isto é dado fora do lugar (convite apagado depois). Fica registrado.
      await snap.ref.update({ status: 'sem_convite' });
      logger.warn(`Pedido ${snap.id} pra ${listingId} sem convite registrado.`);
      return;
    }
    if (convite.optout === true) {
      await snap.ref.update({ status: 'prestador_saiu' });
      return;
    }

    // Já reivindicado (conta criada, talvez ainda sem assinatura): vira
    // orçamento dele na hora — o push do app avisa (onBudgetRequestCreated).
    if (convite.uid) {
      await migrarPedido(snap, String(convite.uid));
    }

    const ultimo: number = convite.ultimoAvisoEm?.toMillis?.() ?? 0;
    if (Date.now() - ultimo < INTERVALO_AVISOS_MS) {
      logger.info(`Pedido ${snap.id}: aviso pro ${listingId} segurado (último há menos de 6 h).`);
      return;
    }

    const para = numeroWhatsapp(convite.whatsapp);
    if (!para) {
      logger.warn(`Convite ${listingId} sem WhatsApp válido.`);
      return;
    }
    const codigo = convite.codigo ? String(convite.codigo) : await novoCodigo();

    // Só o que desperta interesse: serviço e região. Nada do cliente.
    const nome = String(convite.nome ?? '').trim().split(/\s+/)[0] || 'tudo bem';
    const servico = rotuloCategoria(pedido.category).toLowerCase();
    // Bairro/cidade vêm do cadastro do cliente (só o nome do bairro, nunca
    // a rua) — se ele não preencheu, cai pra cidade do prestador.
    const cliente = pedido.clientUid
      ? (await db.collection('clients').doc(String(pedido.clientUid)).get()).data() ?? {}
      : {};
    const bairro = String(cliente.addressNeighborhood ?? '').trim();
    const cidade = String(cliente.addressCity ?? convite.cidade ?? '').trim();
    const local = [bairro, cidade].filter(Boolean).join(', ') || 'sua região';

    try {
      const msgId = await enviarModelo(para, [nome, servico, local, codigo]);
      await conviteRef.update({
        codigo,
        ultimoAvisoEm: FieldValue.serverTimestamp(),
        avisosEnviados: FieldValue.increment(1),
      });
      await snap.ref.update({ avisadoEm: FieldValue.serverTimestamp(), whatsappMsgId: msgId ?? null });
    } catch (e) {
      // Guarda o código mesmo assim, pra reenviar à mão se precisar.
      await conviteRef.update({ codigo, ultimoErroAviso: String(e) });
      logger.error(`Falha ao avisar ${listingId} pelo WhatsApp`, e);
    }
  },
);

/**
 * Chamada pelo app: o prestador recém-cadastrado digita o código que
 * recebeu no WhatsApp. Cria `providers/{uid}` (pending — a assinatura
 * continua sendo o que libera a área de prestador) e traz os pedidos que
 * estavam esperando.
 */
export const reivindicarPerfilPrestador = onCall(async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Faça login primeiro.');
  const uid = request.auth.uid;
  const codigo = String((request.data as { codigo?: string } | undefined)?.codigo ?? '').replace(/\D/g, '');
  if (codigo.length !== 6) throw new HttpsError('invalid-argument', 'O número do pedido tem 6 dígitos.');

  const achados = await db.collection('convitesPrestador').where('codigo', '==', codigo).limit(1).get();
  if (achados.empty) throw new HttpsError('not-found', 'Número não encontrado. Confira a mensagem do WhatsApp.');
  const conviteDoc = achados.docs[0];
  const convite = conviteDoc.data();
  if (convite.uid && convite.uid !== uid) {
    throw new HttpsError('already-exists', 'Esse perfil já foi ativado por outra conta. Fale com o suporte.');
  }

  const listingId = conviteDoc.id;
  const listing = (await db.collection('providerDirectory').doc(listingId).get()).data() ?? {};
  const providerRef = db.collection('providers').doc(uid);
  const providerSnap = await providerRef.get();
  const agora = FieldValue.serverTimestamp();

  if (!providerSnap.exists) {
    const cliente = (await db.collection('clients').doc(uid).get()).data() ?? {};
    const categoria = String(listing.category ?? convite.categoria ?? 'outro');
    await providerRef.set({
      name: cliente.name ?? convite.nome ?? listing.name ?? '',
      email: request.auth.token.email ?? cliente.email ?? '',
      companyName: listing.name ?? convite.nome ?? null,
      // O WhatsApp do convite (o que recebeu o código) — é por ele que
      // aplicarEstadoNormalizado acha e substitui a entrada antiga quando
      // a assinatura for confirmada.
      whatsapp: convite.whatsapp,
      category: categoria,
      categories: Array.isArray(listing.categories) && listing.categories.length ? listing.categories : [categoria],
      city: listing.city ?? convite.cidade ?? '',
      ...(listing.state ? { state: listing.state } : {}),
      // Instagram guardado no convite pelo hub (nunca público antes daqui).
      ...(convite.instagram ? { instagram: convite.instagram } : {}),
      listingStatus: 'pending',
      nextBudgetNumber: 1,
      perfilReivindicado: listingId,
      createdAt: agora,
      updatedAt: agora,
    });
  } else {
    await providerRef.set(
      {
        whatsapp: convite.whatsapp,
        // Não sobrescreve um Instagram que a conta já tenha.
        ...(convite.instagram && !providerSnap.data()?.instagram ? { instagram: convite.instagram } : {}),
        perfilReivindicado: listingId,
        updatedAt: agora,
      },
      { merge: true },
    );
  }

  await conviteDoc.ref.update({ uid, reivindicadoEm: agora });

  const esperando = await db
    .collection('pedidosSemConta')
    .where('listingId', '==', listingId)
    .where('status', '==', 'aguardando')
    .get();
  for (const pedido of esperando.docs) {
    await migrarPedido(pedido, uid);
  }

  logger.info(`Perfil ${listingId} reivindicado por ${uid} (${esperando.size} pedido(s) migrado(s)).`);
  return { pedidos: esperando.size, nome: listing.name ?? convite.nome ?? '' };
});
