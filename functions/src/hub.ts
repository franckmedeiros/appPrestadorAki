/**
 * HUB OP Outsourcing — configuração do PrestadorAki.
 * Assinatura mensal (prestadoraki_assinatura_mensal) via Google Play / App
 * Store, mantida por subscription.ts / subscriptionApple.ts em
 * providers/{uid} (listingStatus, subscriptionState, subscriptionStore,
 * subscriptionExpiresAt).
 */
import { Timestamp } from 'firebase-admin/firestore';
import { criarHub, ms, contar, Assinante } from './hub_core';

const ESTADOS_ATIVOS = new Set([
  'SUBSCRIPTION_STATE_ACTIVE',
  'SUBSCRIPTION_STATE_IN_GRACE_PERIOD',
  'ACTIVE',
  'IN_GRACE_PERIOD',
]);

const hub = criarHub({
  app: 'prestadoraki',
  region: 'us-central1',
  perfis: [
    { colecao: 'clients', nome: 'name', telefone: 'whatsapp', email: 'email' },
    { colecao: 'providers', nome: 'name', telefone: 'whatsapp', email: 'email' },
  ],

  assinantes: async (db) => {
    const [snap, verificadas] = await Promise.all([
      db.collection('providers').get(),
      db.collection('assinaturasVerificadas').get(),
    ]);
    const idPorUid = new Map<string, string>();
    verificadas.forEach((v) => {
      const uid = v.data().uid;
      if (uid) idPorUid.set(uid, v.id);
    });
    const agora = Date.now();
    const lista: Assinante[] = [];
    snap.forEach((d) => {
      const x: any = d.data();
      if (!x.subscriptionState && !x.subscriptionExpiresAt) return; // nunca assinou
      const validoAte = ms(x.subscriptionExpiresAt);
      const ativa =
        x.listingStatus === 'active' &&
        (ESTADOS_ATIVOS.has(String(x.subscriptionState)) || (validoAte != null && validoAte > agora));
      const loja = String(x.subscriptionStore ?? '').toLowerCase();
      lista.push({
        uid: d.id,
        nome: x.name ?? x.tradeName ?? '',
        email: x.email ?? '',
        telefone: x.whatsapp ?? '',
        ativa,
        status: x.subscriptionState ?? null,
        loja: loja.includes('apple') || loja.includes('ios') ? 'apple' : loja ? 'google' : null,
        plano: 'Mensal',
        idAssinatura: idPorUid.has(d.id)
          ? `PA-${String(idPorUid.get(d.id)).startsWith('apple:') ? 'AS' : 'GP'}-` +
            String(idPorUid.get(d.id)).replace(/[^A-Za-z0-9]/g, '').slice(-6).toUpperCase()
          : null,
        validoAte,
        categoria: x.category ?? null,
        cidade: x.city ?? null,
      });
    });
    return lista;
  },

  metricas: async (db) => {
    const trinta = Timestamp.fromMillis(Date.now() - 30 * 24 * 3600 * 1000);
    return [
      { chave: 'clientes', rotulo: 'Contas de cliente', valor: await contar(db.collection('clients')) },
      { chave: 'prestadores', rotulo: 'Prestadores (contas)', valor: await contar(db.collection('providers')) },
      {
        chave: 'diretorio',
        rotulo: 'Prestadores visíveis no diretório',
        valor: await contar(db.collection('providerDirectory').where('visible', '==', true)),
      },
      { chave: 'orcamentos', rotulo: 'Orçamentos (total)', valor: await contar(db.collectionGroup('budgets')) },
      {
        chave: 'orcamentos30d',
        rotulo: 'Orçamentos (30 dias)',
        valor: await contar(db.collectionGroup('budgets').where('createdAt', '>=', trinta)),
      },
      { chave: 'servicos', rotulo: 'Serviços/jobs (total)', valor: await contar(db.collectionGroup('jobs')) },
    ];
  },

  // Bloqueado some do diretório público; liberado volta (se a assinatura
  // estiver ativa — quem decide isso continua sendo subscription.ts).
  aoBloquear: async (db, uid, bloqueado) => {
    const ref = db.collection('providerDirectory').doc(uid);
    const s = await ref.get();
    if (!s.exists) return;
    if (bloqueado) {
      await ref.set({ visible: false, ocultoPeloHub: true }, { merge: true });
    } else if (s.data()?.ocultoPeloHub) {
      const p = (await db.collection('providers').doc(uid).get()).data() ?? {};
      await ref.set({ visible: p.listingStatus === 'active', ocultoPeloHub: false }, { merge: true });
    }
  },
});

export const { hubResumo, hubUsuarios, hubUsuario, hubAtualizarUsuario, hubAssinantes } = hub;
