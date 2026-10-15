/**
 * Instalações e aviso de nova versão.
 *
 * 1. `registrarAbertura` (callable, NÃO exige login) — o app chama ao abrir
 *    e de novo quando a pessoa entra numa conta. Grava `instalacoes/{id}`
 *    com um identificador ANÔNIMO do aparelho (hash, sem nome/e-mail/
 *    telefone), plataforma, versão, primeira/última abertura e — depois do
 *    login — o uid. Assim dá pra contar "abriu o app e não se cadastrou".
 *    Os dados só são gravados aqui pelo servidor (as regras do Firestore
 *    não deixam o app escrever direto nessa coleção).
 *
 * 2. `painelInstalacoes` (callable, só admin) — o que o hub mostra:
 *    totais, abriu-sem-cadastro, por plataforma, série dos últimos 30 dias
 *    e a lista das instalações recentes que ainda não viraram conta.
 *    Só atende o dono do hub (mesma verificação das outras hub*: conta
 *    Google de HUB_ADMINS, ver hub_core.ts). Aparece no hub em
 *    PrestadorAki → Instalações (hubApps/lib/screens/instalacoes_screen.dart).
 *
 * 3. `verificarNovaVersao` (agendada, de hora em hora) — confere a versão
 *    publicada nas duas lojas. Quando aparece uma versão nova, grava em
 *    `meta/versaoPublicada` (que o app lê pra mostrar "Atualização
 *    disponível") e manda push pros tópicos `atualizacao_android` /
 *    `atualizacao_ios`. Na primeira execução só registra, sem push.
 *    - iOS: API pública de busca da App Store (sem chave).
 *    - Android: Play Developer API, faixa de produção, só releases com
 *      status `completed` (rollout gradual ainda em andamento NÃO avisa,
 *      pra não mandar a pessoa atualizar algo que a loja ainda não libera
 *      pra ela). Usa a mesma service account da assinatura
 *      (PLAY_SERVICE_ACCOUNT_KEY).
 */

import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { GoogleAuth } from 'google-auth-library';
import { FieldValue, Timestamp } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';
import { logger } from 'firebase-functions';
import { db } from './lib/admin';
import { playServiceAccountKey } from './subscription';
import { exigirAdmin } from './hub_core';

const PACKAGE_NAME = 'com.opoutsourcing.prestadoraki';
const BUNDLE_ID = 'com.opoutsourcing.prestadoraki';
const PLAY_URL = `https://play.google.com/store/apps/details?id=${PACKAGE_NAME}`;
const FUSO = 'America/Sao_Paulo';

type Plataforma = 'android' | 'ios';

// ---------------------------------------------------------------------------
// 1. registrarAbertura
// ---------------------------------------------------------------------------

const RE_INSTALL_ID = /^[A-Za-z0-9_-]{16,128}$/;
const RE_VERSAO = /^[0-9A-Za-z.+_-]{1,32}$/;

export interface DadosAbertura {
  installId: string;
  plataforma: Plataforma;
  versao: string;
  evento: 'abertura' | 'login';
}

/** Valida o que veio do app. Exportada pra teste. */
export function validarAbertura(data: unknown): DadosAbertura {
  const d = (data ?? {}) as Record<string, unknown>;
  const installId = typeof d.installId === 'string' ? d.installId : '';
  const plataforma = d.plataforma;
  const versao = typeof d.versao === 'string' ? d.versao : '';
  const evento = d.evento === 'login' ? 'login' : 'abertura';
  if (!RE_INSTALL_ID.test(installId)) throw new HttpsError('invalid-argument', 'installId inválido.');
  if (plataforma !== 'android' && plataforma !== 'ios') throw new HttpsError('invalid-argument', 'plataforma inválida.');
  if (!RE_VERSAO.test(versao)) throw new HttpsError('invalid-argument', 'versao inválida.');
  return { installId, plataforma, versao, evento };
}

export const registrarAbertura = onCall(async (request) => {
  const dados = validarAbertura(request.data);
  const uid = request.auth?.uid ?? null;
  const ref = db.collection('instalacoes').doc(dados.installId);
  const agora = FieldValue.serverTimestamp();

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) {
      tx.set(ref, {
        plataforma: dados.plataforma,
        versao: dados.versao,
        primeiraAbertura: agora,
        ultimaAbertura: agora,
        aberturas: 1,
        uid,
        uids: uid ? [uid] : [],
        cadastradoEm: uid ? agora : null,
      });
      return;
    }
    const atual = snap.data() ?? {};
    const update: Record<string, unknown> = {
      versao: dados.versao,
      ultimaAbertura: agora,
    };
    if (dados.evento === 'abertura') update.aberturas = FieldValue.increment(1);
    if (uid) {
      update.uids = FieldValue.arrayUnion(uid);
      if (!atual.uid) {
        update.uid = uid;
        update.cadastradoEm = agora;
      }
    }
    tx.update(ref, update);
  });

  return { ok: true };
});

// ---------------------------------------------------------------------------
// 2. painelInstalacoes
// ---------------------------------------------------------------------------

const formatoDia = new Intl.DateTimeFormat('en-CA', { timeZone: FUSO, year: 'numeric', month: '2-digit', day: '2-digit' });

/** "2026-10-14" no fuso de Brasília. */
export function diaLocal(data: Date): string {
  return formatoDia.format(data);
}

export interface InstalacaoResumo {
  id: string;
  plataforma: string;
  versao: string;
  primeiraAbertura: Date | null;
  ultimaAbertura: Date | null;
  aberturas: number;
  uid: string | null;
}

/** Monta a série diária (últimos `dias` dias, incluindo hoje). Exportada pra teste. */
export function montarSerie(instalacoes: InstalacaoResumo[], hoje: Date, dias = 30) {
  const serie: { dia: string; novas: number; comCadastro: number; android: number; ios: number }[] = [];
  const indice = new Map<string, (typeof serie)[number]>();
  for (let i = dias - 1; i >= 0; i--) {
    const dia = diaLocal(new Date(hoje.getTime() - i * 86_400_000));
    if (indice.has(dia)) continue;
    const item = { dia, novas: 0, comCadastro: 0, android: 0, ios: 0 };
    indice.set(dia, item);
    serie.push(item);
  }
  for (const inst of instalacoes) {
    if (!inst.primeiraAbertura) continue;
    const item = indice.get(diaLocal(inst.primeiraAbertura));
    if (!item) continue;
    item.novas++;
    if (inst.uid) item.comCadastro++;
    if (inst.plataforma === 'android') item.android++;
    else if (inst.plataforma === 'ios') item.ios++;
  }
  return serie;
}

function paraData(v: unknown): Date | null {
  return v instanceof Timestamp ? v.toDate() : null;
}

export const painelInstalacoes = onCall(async (request) => {
  exigirAdmin(request);

  const col = db.collection('instalacoes');
  const [total, semCadastro, android, ios] = await Promise.all([
    col.count().get(),
    col.where('uid', '==', null).count().get(),
    col.where('plataforma', '==', 'android').count().get(),
    col.where('plataforma', '==', 'ios').count().get(),
  ]);

  // Últimos 90 dias (filtro de um campo só — não precisa de índice composto).
  const desde = Timestamp.fromMillis(Date.now() - 90 * 86_400_000);
  const recentesSnap = await col.where('primeiraAbertura', '>=', desde).get();
  const recentes: InstalacaoResumo[] = recentesSnap.docs.map((doc) => {
    const d = doc.data();
    return {
      id: doc.id,
      plataforma: String(d.plataforma ?? ''),
      versao: String(d.versao ?? ''),
      primeiraAbertura: paraData(d.primeiraAbertura),
      ultimaAbertura: paraData(d.ultimaAbertura),
      aberturas: typeof d.aberturas === 'number' ? d.aberturas : 0,
      uid: typeof d.uid === 'string' ? d.uid : null,
    };
  });

  const semConta = recentes
    .filter((i) => !i.uid)
    .sort((a, b) => (b.ultimaAbertura?.getTime() ?? 0) - (a.ultimaAbertura?.getTime() ?? 0))
    .slice(0, 200)
    .map((i) => ({
      id: i.id.slice(0, 8),
      plataforma: i.plataforma,
      versao: i.versao,
      primeiraAbertura: i.primeiraAbertura?.toISOString() ?? null,
      ultimaAbertura: i.ultimaAbertura?.toISOString() ?? null,
      aberturas: i.aberturas,
    }));

  const versao = (await db.doc('meta/versaoPublicada').get()).data() ?? {};

  return {
    total: total.data().count,
    semCadastro: semCadastro.data().count,
    comCadastro: total.data().count - semCadastro.data().count,
    android: android.data().count,
    ios: ios.data().count,
    serie: montarSerie(recentes, new Date(), 30),
    semConta,
    versaoPublicada: {
      android: versao.android ? { nome: versao.android.nome ?? null, versionCode: versao.android.versionCode ?? null } : null,
      ios: versao.ios ? { versao: versao.ios.versao ?? null } : null,
    },
    geradoEm: new Date().toISOString(),
  };
});

// ---------------------------------------------------------------------------
// 3. verificarNovaVersao
// ---------------------------------------------------------------------------

/** Compara "1.2.10" com "1.2.9" → 1. Ignora sufixos não numéricos. Exportada pra teste. */
export function compararVersoes(a: string, b: string): number {
  const pa = a.split(/[.+]/).map((p) => parseInt(p, 10) || 0);
  const pb = b.split(/[.+]/).map((p) => parseInt(p, 10) || 0);
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    const diff = (pa[i] ?? 0) - (pb[i] ?? 0);
    if (diff !== 0) return diff > 0 ? 1 : -1;
  }
  return 0;
}

interface VersaoIos {
  versao: string;
  notas: string | null;
  url: string | null;
}

async function buscarVersaoIos(): Promise<VersaoIos | null> {
  const url = `https://itunes.apple.com/lookup?bundleId=${BUNDLE_ID}&country=br&t=${Date.now()}`;
  const resp = await fetch(url);
  if (!resp.ok) throw new Error(`App Store lookup HTTP ${resp.status}`);
  const json = (await resp.json()) as { resultCount?: number; results?: Record<string, unknown>[] };
  const app = json.results?.[0];
  if (!app || typeof app.version !== 'string') return null; // ainda não está na loja do Brasil
  return {
    versao: app.version,
    notas: typeof app.releaseNotes === 'string' ? app.releaseNotes : null,
    url: typeof app.trackViewUrl === 'string' ? app.trackViewUrl : null,
  };
}

interface ReleasePlay {
  name?: string;
  status?: string;
  versionCodes?: string[];
}

/** Escolhe a maior versão TOTALMENTE publicada (status completed). Exportada pra teste. */
export function escolherReleaseAndroid(releases: ReleasePlay[]): { versionCode: number; nome: string | null } | null {
  let melhor: { versionCode: number; nome: string | null } | null = null;
  for (const r of releases) {
    if (r.status !== 'completed') continue;
    for (const vc of r.versionCodes ?? []) {
      const n = parseInt(vc, 10);
      if (!Number.isFinite(n)) continue;
      if (!melhor || n > melhor.versionCode) melhor = { versionCode: n, nome: r.name ?? null };
    }
  }
  return melhor;
}

async function buscarVersaoAndroid(): Promise<{ versionCode: number; nome: string | null } | null> {
  const credentials = JSON.parse(playServiceAccountKey.value());
  const auth = new GoogleAuth({ credentials, scopes: ['https://www.googleapis.com/auth/androidpublisher'] });
  const client = await auth.getClient();
  const base = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${PACKAGE_NAME}/edits`;
  // Ler a faixa exige abrir um "edit" temporário; ele é descartado no fim
  // (nada é publicado nem alterado).
  const edit = await client.request<{ id: string }>({ url: base, method: 'POST' });
  const editId = edit.data.id;
  try {
    const track = await client.request<{ releases?: ReleasePlay[] }>({ url: `${base}/${editId}/tracks/production` });
    return escolherReleaseAndroid(track.data.releases ?? []);
  } finally {
    await client.request({ url: `${base}/${editId}`, method: 'DELETE' }).catch(() => undefined);
  }
}

async function enviarPushAtualizacao(plataforma: Plataforma, versaoTexto: string, url: string) {
  await getMessaging().send({
    topic: `atualizacao_${plataforma}`,
    notification: {
      title: 'Nova versão do PrestadorAki',
      body: `A versão ${versaoTexto} já está disponível. Toque para atualizar.`,
    },
    data: { tipo: 'atualizacao', plataforma, versao: versaoTexto, url },
    android: { priority: 'high' },
    apns: { payload: { aps: { sound: 'default' } } },
  });
}

export const verificarNovaVersao = onSchedule(
  { schedule: '7 * * * *', timeZone: FUSO, secrets: [playServiceAccountKey] },
  async () => {
    const ref = db.doc('meta/versaoPublicada');
    const atual = (await ref.get()).data() ?? {};
    const primeiraVez = !atual.android && !atual.ios;

    // iOS
    try {
      const ios = await buscarVersaoIos();
      if (ios) {
        const anterior: string | undefined = atual.ios?.versao;
        if (!anterior || compararVersoes(ios.versao, anterior) > 0) {
          await ref.set(
            { ios: { versao: ios.versao, notas: ios.notas, url: ios.url, detectadoEm: FieldValue.serverTimestamp() } },
            { merge: true },
          );
          if (anterior && !primeiraVez) {
            await enviarPushAtualizacao('ios', ios.versao, ios.url ?? '');
            await ref.set({ ios: { notificadoEm: FieldValue.serverTimestamp() } }, { merge: true });
          }
          logger.info(`Versão iOS ${anterior ?? '(nenhuma)'} -> ${ios.versao}`);
        }
      }
    } catch (e) {
      logger.error('Falha ao verificar versão iOS', e);
    }

    // Android
    try {
      const android = await buscarVersaoAndroid();
      if (android) {
        const anterior: number | undefined = atual.android?.versionCode;
        if (anterior === undefined || android.versionCode > anterior) {
          await ref.set(
            {
              android: {
                versionCode: android.versionCode,
                nome: android.nome,
                url: PLAY_URL,
                detectadoEm: FieldValue.serverTimestamp(),
              },
            },
            { merge: true },
          );
          if (anterior !== undefined && !primeiraVez) {
            await enviarPushAtualizacao('android', android.nome ?? String(android.versionCode), PLAY_URL);
            await ref.set({ android: { notificadoEm: FieldValue.serverTimestamp() } }, { merge: true });
          }
          logger.info(`Versão Android ${anterior ?? '(nenhuma)'} -> ${android.versionCode}`);
        }
      }
    } catch (e) {
      logger.error('Falha ao verificar versão Android (Play Developer API)', e);
    }
  },
);
