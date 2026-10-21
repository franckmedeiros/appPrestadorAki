/**
 * Junta um pré-cadastro (entrada `providerDirectory` com `claimed: false`,
 * da carga inicial ou do convite pelo WhatsApp) com a conta de verdade do
 * prestador (`providerDirectory/{uid}`).
 *
 * Por que existe (caso Alluvetro, 20/10): a troca automática na assinatura
 * só acontecia se o prestador AINDA NÃO tinha `providerDirectory/{uid}`.
 * Quem já tinha publicado o perfil antes (teste grátis, salvar o perfil no
 * app) assinava e o pré-cadastro continuava lá — duas entradas da mesma
 * empresa na busca, uma "chegando" e outra assinante.
 *
 * Usado em dois lugares:
 *  - subscription.ts (`aplicarEstadoNormalizado`): toda vez que a
 *    assinatura está ativa, procura e junta — não só na primeira vez;
 *  - hub_chegando.ts (`hubJuntarChegando`): o botão "Juntar com a conta".
 */
import { FieldValue } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';
import { db } from './lib/admin';
import { migrarPedido } from './convites';

/** Só dígitos, sem 55 e sem 0 na frente — o formato do `phoneNormalized` dos pré-cadastros. */
export function telefoneSemDdi(bruto: unknown): string | null {
  let d = String(bruto ?? '').replace(/\D/g, '');
  if (d.startsWith('55') && d.length >= 12) d = d.slice(2);
  if (d.startsWith('0')) d = d.slice(1);
  return d.length === 10 || d.length === 11 ? d : null;
}

/**
 * Acha o pré-cadastro desta conta, nesta ordem:
 *  1. o que ela assumiu pelo código (`providers/{uid}.perfilReivindicado`);
 *  2. o convite já ligado a este uid (`convitesPrestador.uid`);
 *  3. o mesmo telefone (`phoneNormalized`).
 * Só devolve entradas ainda não reivindicadas (`claimed: false`).
 */
export async function acharPreCadastroDaConta(
  uid: string,
  provider: { whatsapp?: unknown; perfilReivindicado?: unknown },
): Promise<string | null> {
  const livre = async (id: string) => {
    if (!id || id === uid) return false;
    const s = await db.collection('providerDirectory').doc(id).get();
    return s.exists && s.data()?.claimed !== true;
  };

  const peloCodigo = String(provider.perfilReivindicado ?? '');
  if (await livre(peloCodigo)) return peloCodigo;

  const convites = await db.collection('convitesPrestador').where('uid', '==', uid).limit(5).get();
  for (const c of convites.docs) if (await livre(c.id)) return c.id;

  const tel = telefoneSemDdi(provider.whatsapp);
  if (tel) {
    const q = await db
      .collection('providerDirectory')
      .where('claimed', '==', false)
      .where('phoneNormalized', '==', tel)
      .limit(5)
      .get();
    const doc = q.docs.find((d) => d.id !== uid);
    if (q.size > 1) {
      logger.warn(`acharPreCadastroDaConta: ${q.size} pré-cadastros com o telefone ${tel}; juntando ${doc?.id}.`);
    }
    if (doc) return doc.id;
  }
  return null;
}

export interface ResultadoJuntar {
  juntou: boolean;
  motivo?: string;
  avaliacoesMovidas?: number;
  pedidosMigrados?: number;
}

/**
 * Move avaliações, logo/descrição (se a conta não tiver) e pedidos
 * esperando do pré-cadastro pra conta, liga o convite ao uid e apaga o
 * pré-cadastro. A conta precisa já ter `providerDirectory/{uid}`.
 */
export async function juntarPreCadastro(listingId: string, uid: string): Promise<ResultadoJuntar> {
  if (!listingId || !uid || listingId === uid) return { juntou: false, motivo: 'mesmo registro' };
  const dir = db.collection('providerDirectory');
  const antigaRef = dir.doc(listingId);
  const novaRef = dir.doc(uid);
  const [antiga, nova] = await Promise.all([antigaRef.get(), novaRef.get()]);
  if (!antiga.exists) return { juntou: false, motivo: 'pré-cadastro não existe mais' };
  if (antiga.data()?.claimed === true) return { juntou: false, motivo: 'pré-cadastro já é de outra conta' };
  if (!nova.exists) return { juntou: false, motivo: 'a conta ainda não tem perfil publicado no app' };

  const a = antiga.data() ?? {};
  const n = nova.data() ?? {};

  // Avaliações: mesmo id (uid de quem avaliou), pra ninguém avaliar duas vezes.
  const [avAntigas, avNovas] = await Promise.all([
    antigaRef.collection('ratings').get(),
    novaRef.collection('ratings').get(),
  ]);
  const jaTem = new Set(avNovas.docs.map((d) => d.id));
  const notas: number[] = avNovas.docs.map((d) => Number(d.data().stars)).filter((x) => x > 0);
  const batch = db.batch();
  let movidas = 0;
  for (const av of avAntigas.docs) {
    if (!jaTem.has(av.id)) {
      batch.set(novaRef.collection('ratings').doc(av.id), av.data());
      const s = Number(av.data().stars);
      if (s > 0) notas.push(s);
      movidas++;
    }
    batch.delete(av.ref);
  }

  const agora = FieldValue.serverTimestamp();
  batch.set(
    novaRef,
    {
      // Recalculado das avaliações juntas. Pré-cadastro da carga inicial
      // pode ter só a média (sem os documentos de avaliação): aí herda a
      // média dele se a conta ainda não tem nenhuma.
      ...(movidas > 0 && notas.length
        ? {
            ratingCount: notas.length,
            ratingAverage: Math.round((notas.reduce((s, x) => s + x, 0) / notas.length) * 100) / 100,
          }
        : !avAntigas.size && Number(a.ratingCount) > 0 && !(Number(n.ratingCount) > 0)
          ? { ratingCount: a.ratingCount, ratingAverage: a.ratingAverage ?? 0 }
          : {}),
      ...(!n.logoUrl && a.logoUrl ? { logoUrl: a.logoUrl } : {}),
      ...(!n.bio && a.bio ? { bio: a.bio } : {}),
      preCadastroJuntado: listingId,
      updatedAt: agora,
    },
    { merge: true },
  );
  batch.delete(antigaRef);
  await batch.commit();

  // Convite: liga ao uid (o aviso de pedido deixa de ir pro WhatsApp).
  const conviteRef = db.collection('convitesPrestador').doc(listingId);
  const convite = await conviteRef.get();
  if (convite.exists) {
    await conviteRef.set(
      { uid, ...(convite.data()?.reivindicadoEm ? {} : { reivindicadoEm: agora }), juntadoEm: agora },
      { merge: true },
    );
  }

  // Pedidos de clientes que esperavam o prestador viram orçamentos dele.
  const pedidos = await db
    .collection('pedidosSemConta')
    .where('listingId', '==', listingId)
    .where('status', '==', 'aguardando')
    .get();
  for (const p of pedidos.docs) await migrarPedido(p, uid);

  // Conta: lembra de onde veio e herda o Instagram guardado no convite.
  const providerRef = db.collection('providers').doc(uid);
  const prov = (await providerRef.get()).data() ?? {};
  await providerRef.set(
    {
      ...(prov.perfilReivindicado ? {} : { perfilReivindicado: listingId }),
      ...(!prov.instagram && convite.data()?.instagram ? { instagram: convite.data()?.instagram } : {}),
      updatedAt: agora,
    },
    { merge: true },
  );

  logger.info(`Pré-cadastro ${listingId} juntado à conta ${uid}`, { movidas, pedidos: pedidos.size });
  return { juntou: true, avaliacoesMovidas: movidas, pedidosMigrados: pedidos.size };
}
