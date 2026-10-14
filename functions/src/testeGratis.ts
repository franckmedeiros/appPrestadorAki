/**
 * TESTE GRÁTIS DE 7 DIAS do prestador (decisão do Franck, 13/10).
 *
 * Quem vira prestador ganha 7 dias de área de prestador liberada (aparece
 * na busca, usa agenda/orçamentos etc.) SEM passar pela loja — sem cartão,
 * pra não afastar quem chega pelo Instagram. Depois dos 7 dias, cai na
 * tela de assinatura normal (Google Play / App Store), igual a quem parou
 * de pagar.
 *
 * Como funciona: o teste é só mais um "estado de assinatura" aplicado pelo
 * MESMO `aplicarEstadoNormalizado` de subscription.ts, com
 * `subscriptionStore: 'teste'` e `subscriptionExpiresAt` = fim do teste.
 * Então o app não precisa de lógica nova pra liberar/travar: continua
 * olhando só `providers/{uid}.listingStatus` (ver
 * `AuthController.providerAccessLocked`). Quem decide que o teste acabou é
 * o servidor (`expirarTestesGratis`, de hora em hora) — nunca o relógio do
 * celular.
 *
 * Uma vez por pessoa: o uso fica registrado em `testesGratis/{uid}` (com o
 * telefone, pra quem apagar a conta e criar outra com o mesmo WhatsApp não
 * ganhar de novo). O HUB pode estender ou encerrar o teste de qualquer um
 * (ver `ajustarTesteGratis`, chamado por hub.ts).
 *
 * Se a pessoa assinar na loja durante o teste, `confirmarAssinaturaPrestador`
 * grava `subscriptionStore: 'google'|'apple'` por cima — o teste some
 * sozinho e a cobrança passa a valer.
 */

import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { logger } from 'firebase-functions';
import { FieldValue, Timestamp } from 'firebase-admin/firestore';
import { db } from './lib/admin';
import { aplicarEstadoNormalizado } from './subscription';

export const DIAS_TESTE_GRATIS = 7;
const DIA_MS = 24 * 60 * 60 * 1000;

/** Valor gravado em `providers/{uid}.subscriptionStore` durante o teste. */
export const LOJA_TESTE = 'teste';

function soDigitos(v: unknown): string {
  return String(v ?? '').replace(/[^0-9]/g, '');
}

/** Telefone da conta (providers ou clients), só dígitos — pra travar "1 teste por pessoa". */
async function telefoneDaConta(uid: string): Promise<string> {
  const [p, c] = await Promise.all([
    db.collection('providers').doc(uid).get(),
    db.collection('clients').doc(uid).get(),
  ]);
  return soDigitos(p.data()?.whatsapp ?? c.data()?.whatsapp);
}

/** Motivo pelo qual a conta NÃO pode ganhar o teste automático, ou null se pode. */
async function motivoInelegivel(uid: string): Promise<string | null> {
  if ((await db.collection('testesGratis').doc(uid).get()).exists) {
    return 'Você já usou o teste grátis.';
  }
  const tel = await telefoneDaConta(uid);
  if (tel) {
    const mesmoTelefone = await db.collection('testesGratis').where('telefone', '==', tel).limit(1).get();
    if (!mesmoTelefone.empty) return 'Esse WhatsApp já usou o teste grátis.';
  }
  const comprou = await db.collection('assinaturasVerificadas').where('uid', '==', uid).limit(1).get();
  if (!comprou.empty) return 'Essa conta já teve assinatura — o teste grátis é só pra quem está começando.';
  return null;
}

/**
 * Liga (ou estende) o teste até `ate`. Usado pelo app (início automático)
 * e pelo hub (estender). Não mexe em quem está com assinatura de loja
 * ativa — esse já está pagando.
 */
async function aplicarTeste(
  uid: string,
  ate: Date,
  origem: string,
  dadosNovoProvider?: { category: string; city: string; state?: string },
): Promise<void> {
  await aplicarEstadoNormalizado(
    uid,
    { ativa: true, expiraEm: Timestamp.fromDate(ate), rawState: 'TESTE_GRATIS', loja: LOJA_TESTE },
    dadosNovoProvider,
  );
  const tel = await telefoneDaConta(uid);
  const ref = db.collection('testesGratis').doc(uid);
  const existe = (await ref.get()).exists;
  await ref.set(
    {
      ...(existe ? {} : { iniciadoEm: FieldValue.serverTimestamp(), origem }),
      ...(tel ? { telefone: tel } : {}),
      ate: Timestamp.fromDate(ate),
      atualizadoEm: FieldValue.serverTimestamp(),
      ultimaAcao: origem,
    },
    { merge: true },
  );
}

async function encerrarTeste(uid: string, rawState: string): Promise<void> {
  await aplicarEstadoNormalizado(uid, {
    ativa: false,
    expiraEm: Timestamp.now(),
    rawState,
    loja: LOJA_TESTE,
  });
  await db
    .collection('testesGratis')
    .doc(uid)
    .set({ ate: Timestamp.now(), encerradoEm: FieldValue.serverTimestamp(), ultimaAcao: rawState }, { merge: true });
}

/**
 * Chamada pelo app logo que a conta vira prestador (cadastro como
 * prestador ou "Virar prestador" no perfil). Se a conta ainda não tem
 * `providers/{uid}`, precisa de categoria/cidade pra criar — igual à
 * primeira confirmação de assinatura.
 *
 * Erros: `already-exists` (já usou o teste — o app segue pra tela de
 * assinatura), `invalid-argument` (faltou categoria/cidade).
 */
export const iniciarTesteGratisPrestador = onCall(async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Faça login primeiro.');
  const uid = request.auth.uid;
  const { category, city, state } = (request.data ?? {}) as {
    category?: string;
    city?: string;
    state?: string;
  };

  const motivo = await motivoInelegivel(uid);
  if (motivo) throw new HttpsError('already-exists', motivo);

  const provider = await db.collection('providers').doc(uid).get();
  if (provider.exists && provider.data()?.listingStatus === 'active') {
    // Já ativo por outro caminho (assinatura/conta antiga) — nada a fazer.
    return { ativo: true, ate: null };
  }
  if (!provider.exists && (!category || !city)) {
    throw new HttpsError('invalid-argument', 'Faltam categoria/cidade pra criar o cadastro de prestador.');
  }

  const ate = new Date(Date.now() + DIAS_TESTE_GRATIS * DIA_MS);
  await aplicarTeste(uid, ate, 'app', provider.exists ? undefined : { category: category!, city: city!, state });
  logger.info(`Teste grátis iniciado para ${uid} até ${ate.toISOString()}.`);
  return { ativo: true, ate: ate.getTime() };
});

/**
 * Hub: `dias > 0` → libera/estende o teste por mais `dias` (a partir do
 * fim atual, se ainda não acabou; senão a partir de agora). `dias === 0`
 * → encerra o teste agora (a pessoa cai na tela de assinatura).
 * Não exige elegibilidade: é decisão sua.
 */
export async function ajustarTesteGratis(uid: string, dias: number, admin: string): Promise<void> {
  const ref = db.collection('providers').doc(uid);
  const p = (await ref.get()).data();
  if (!p) {
    throw new HttpsError(
      'failed-precondition',
      'Essa conta ainda não é prestador. Peça pra ela tocar em "Virar prestador" no app (o teste começa sozinho).',
    );
  }
  const loja = String(p.subscriptionStore ?? '');
  const expira: number | null = p.subscriptionExpiresAt?.toMillis?.() ?? null;
  const pagando = (loja === 'google' || loja === 'apple') && p.listingStatus === 'active';

  if (dias <= 0) {
    if (loja !== LOJA_TESTE) {
      throw new HttpsError('failed-precondition', 'Essa conta não está em teste grátis.');
    }
    await encerrarTeste(uid, 'TESTE_ENCERRADO_HUB');
    logger.info(`Teste grátis de ${uid} encerrado pelo hub (${admin}).`);
    return;
  }
  if (pagando) {
    throw new HttpsError('failed-precondition', 'Essa conta já tem assinatura ativa na loja.');
  }
  const base = loja === LOJA_TESTE && expira && expira > Date.now() ? expira : Date.now();
  const ate = new Date(base + Math.min(dias, 365) * DIA_MS);
  await aplicarTeste(uid, ate, `hub:${admin}`);
  logger.info(`Teste grátis de ${uid} liberado até ${ate.toISOString()} pelo hub (${admin}).`);
}

/** Situação do teste pra mostrar no hub. */
export async function lerTesteGratis(uid: string): Promise<Record<string, unknown>> {
  const [t, p] = await Promise.all([
    db.collection('testesGratis').doc(uid).get(),
    db.collection('providers').doc(uid).get(),
  ]);
  const prov = p.data() ?? {};
  const emTeste = prov.subscriptionStore === LOJA_TESTE && prov.listingStatus === 'active';
  return {
    disponivel: p.exists,
    usado: t.exists,
    emTeste,
    ate: emTeste ? prov.subscriptionExpiresAt?.toMillis?.() ?? null : t.data()?.ate?.toMillis?.() ?? null,
    iniciadoEm: t.data()?.iniciadoEm?.toMillis?.() ?? null,
  };
}

/**
 * De hora em hora: quem está em teste e já passou da data cai pra
 * `pending` (some da busca e o app manda pra tela de assinatura, sozinho,
 * pela escuta de providers/{uid}).
 */
export const expirarTestesGratis = onSchedule(
  { schedule: '5 * * * *', timeZone: 'America/Sao_Paulo', timeoutSeconds: 300 },
  async () => {
    const snap = await db
      .collection('providers')
      .where('subscriptionStore', '==', LOJA_TESTE)
      .where('listingStatus', '==', 'active')
      .get();
    const agora = Date.now();
    let expirados = 0;
    for (const doc of snap.docs) {
      const fim: number | null = doc.data().subscriptionExpiresAt?.toMillis?.() ?? null;
      if (fim != null && fim > agora) continue;
      try {
        await encerrarTeste(doc.id, 'TESTE_EXPIRADO');
        expirados += 1;
      } catch (e) {
        logger.error(`Falha ao expirar o teste grátis de ${doc.id}`, e);
      }
    }
    if (expirados) logger.info(`expirarTestesGratis: ${expirados} teste(s) encerrado(s).`);
  },
);
