/**
 * Núcleo do HUB (painel único OP Outsourcing) — versão TypeScript da mesma
 * API usada no Resenha e no EstiloAki (lá: functions/hub_core.js).
 *
 *   hubResumo, hubUsuarios, hubUsuario, hubAtualizarUsuario, hubAssinantes
 *
 * Só atende o dono do hub (HUB_ADMINS, e-mail Google confirmado).
 */
import { onCall, HttpsError, CallableRequest } from 'firebase-functions/v2/https';
import { getAuth, UserRecord } from 'firebase-admin/auth';
import { Firestore, Query, Timestamp, FieldValue } from 'firebase-admin/firestore';
import { db as dbAdmin } from './lib/admin';

export const HUB_ADMINS = ['opoutsourcingbr@gmail.com'];

export function exigirAdmin(req: CallableRequest<any>): string {
  const t: any = req.auth?.token;
  if (!t) throw new HttpsError('unauthenticated', 'Faça login no hub.');
  const email = String(t.email ?? '').toLowerCase();
  if (!HUB_ADMINS.includes(email) || t.email_verified !== true) {
    throw new HttpsError('permission-denied', 'Acesso restrito ao administrador do hub.');
  }
  return email;
}

export function ms(v: any): number | null {
  if (v == null) return null;
  if (typeof v === 'number') return v;
  if (typeof v.toMillis === 'function') return v.toMillis();
  if (v instanceof Date) return v.getTime();
  const d = Date.parse(v);
  return isNaN(d) ? null : d;
}

export function serializar(v: any, nivel = 0): any {
  if (v == null || nivel > 4) return v == null ? null : String(v);
  if (typeof v.toMillis === 'function') return v.toMillis();
  if (v instanceof Date) return v.getTime();
  if (Array.isArray(v)) return v.slice(0, 50).map((x) => serializar(x, nivel + 1));
  if (typeof v === 'object') {
    const nome = v.constructor?.name;
    if (nome === 'DocumentReference') return v.path;
    if (nome === 'GeoPoint') return { lat: v.latitude, lng: v.longitude };
    const o: Record<string, any> = {};
    for (const [k, x] of Object.entries(v)) o[k] = serializar(x, nivel + 1);
    return o;
  }
  return v;
}

export interface UsuarioHub {
  uid: string;
  email: string;
  nome: string;
  telefone: string;
  bloqueado: boolean;
  emailVerificado: boolean;
  criadoEm: number | null;
  ultimoAcesso: number | null;
  provedores: string[];
  [k: string]: any;
}

function deAuth(u: UserRecord): UsuarioHub {
  const m: any = u.metadata ?? {};
  return {
    uid: u.uid,
    email: u.email ?? '',
    nome: u.displayName ?? '',
    telefone: u.phoneNumber ?? '',
    bloqueado: Boolean(u.disabled),
    emailVerificado: Boolean(u.emailVerified),
    criadoEm: ms(m.creationTime),
    ultimoAcesso: ms(m.lastRefreshTime) ?? ms(m.lastSignInTime),
    provedores: (u.providerData ?? []).map((p) => p.providerId),
  };
}

async function todosUsuariosAuth(): Promise<UsuarioHub[]> {
  const lista: UsuarioHub[] = [];
  let token: string | undefined;
  do {
    const r = await getAuth().listUsers(1000, token);
    for (const u of r.users) {
      if (HUB_ADMINS.includes(String(u.email ?? '').toLowerCase())) continue;
      lista.push(deAuth(u));
    }
    token = r.pageToken;
  } while (token);
  return lista;
}

export async function contar(query: Query): Promise<number | null> {
  try {
    const s = await query.count().get();
    return s.data().count;
  } catch {
    return null;
  }
}

function inicioMes(d: Date, mesesAtras: number): number {
  return new Date(d.getFullYear(), d.getMonth() - mesesAtras, 1).getTime();
}

export interface Assinante {
  uid: string;
  nome: string;
  email: string;
  telefone?: string;
  ativa: boolean;
  status: string | null;
  loja: string | null;
  plano: string | null;
  validoAte: number | null;
  [k: string]: any;
}

export interface PerfilCfg {
  colecao: string;
  nome?: string;
  telefone?: string;
  email?: string;
}

export interface HubCfg {
  app: string;
  region?: string;
  perfis: PerfilCfg[];
  assinantes: (db: Firestore) => Promise<Assinante[]>;
  metricas: (db: Firestore) => Promise<{ chave: string; rotulo: string; valor: number | null }[]>;
  aoBloquear?: (db: Firestore, uid: string, bloqueado: boolean) => Promise<void>;
  emailInterno?: RegExp;
}

export function criarHub(cfg: HubCfg) {
  const opcoes = { region: cfg.region ?? 'us-central1', timeoutSeconds: 120, memory: '512MiB' as const, maxInstances: 1 };
  const db = dbAdmin;

  async function assinantesSeguro(): Promise<Assinante[]> {
    try {
      return (await cfg.assinantes(db)) ?? [];
    } catch {
      return [];
    }
  }

  const hubResumo = onCall(opcoes, async (req) => {
    exigirAdmin(req);
    const agora = Date.now();
    const dia = 24 * 3600 * 1000;
    const usuarios = await todosUsuariosAuth();
    const assinantes = await assinantesSeguro();
    const ativos = assinantes.filter((a) => a.ativa);
    const hoje = new Date();
    const meses: { mes: string; cadastros: number }[] = [];
    for (let i = 5; i >= 0; i--) {
      const ini = inicioMes(hoje, i);
      const fim = inicioMes(hoje, i - 1);
      const d = new Date(ini);
      meses.push({
        mes: `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`,
        cadastros: usuarios.filter((u) => (u.criadoEm ?? 0) >= ini && (u.criadoEm ?? 0) < fim).length,
      });
    }
    const porLoja: Record<string, number> = {};
    for (const a of ativos) {
      const l = a.loja ?? 'desconhecida';
      porLoja[l] = (porLoja[l] ?? 0) + 1;
    }
    let extras: any[] = [];
    try {
      extras = (await cfg.metricas(db)) ?? [];
    } catch {
      extras = [];
    }
    return {
      app: cfg.app,
      geradoEm: agora,
      totalUsuarios: usuarios.length,
      bloqueados: usuarios.filter((u) => u.bloqueado).length,
      novos7d: usuarios.filter((u) => (u.criadoEm ?? 0) >= agora - 7 * dia).length,
      novos30d: usuarios.filter((u) => (u.criadoEm ?? 0) >= agora - 30 * dia).length,
      ativos30d: usuarios.filter((u) => (u.ultimoAcesso ?? 0) >= agora - 30 * dia).length,
      assinantesAtivos: ativos.length,
      vencem7d: ativos.filter(
        (a) => a.validoAte != null && a.validoAte - agora <= 7 * dia && a.validoAte >= agora,
      ).length,
      emCarencia: assinantes.filter((a) => /GRACE|CARENCIA|ATRASADA/i.test(String(a.status ?? ''))).length,
      assinantesTotal: assinantes.length,
      assinantesPorLoja: porLoja,
      cadastrosPorMes: meses,
      extras,
    };
  });

  const hubUsuarios = onCall(opcoes, async (req) => {
    exigirAdmin(req);
    const d: any = req.data ?? {};
    const busca = String(d.busca ?? '').trim().toLowerCase();
    const filtro = d.filtro ?? 'todos';
    const pagina = Math.max(0, Number(d.pagina) || 0);
    const tamanho = Math.min(200, Math.max(10, Number(d.tamanho) || 50));

    const assinantes = await assinantesSeguro();
    const mapa = new Map(assinantes.map((a) => [a.uid, a]));
    let lista: UsuarioHub[] = (await todosUsuariosAuth()).map((u) => {
      const a = mapa.get(u.uid);
      return { ...u, assinante: Boolean(a?.ativa), statusAssinatura: a ? a.status : null };
    });
    if (busca) {
      const dig = busca.replace(/\D/g, '');
      lista = lista.filter(
        (u) =>
          u.uid.toLowerCase() === busca ||
          u.email.toLowerCase().includes(busca) ||
          u.nome.toLowerCase().includes(busca) ||
          (dig.length >= 4 && u.telefone.replace(/\D/g, '').includes(dig)),
      );
    }
    if (filtro === 'bloqueados') lista = lista.filter((u) => u.bloqueado);
    if (filtro === 'assinantes') lista = lista.filter((u) => u.assinante);
    lista.sort((a, b) => (b.criadoEm ?? 0) - (a.criadoEm ?? 0));
    const total = lista.length;
    const itens = lista.slice(pagina * tamanho, (pagina + 1) * tamanho);
    await Promise.all(
      itens.map(async (u) => {
        if (u.nome && u.telefone) return;
        for (const p of cfg.perfis) {
          const s = await db.collection(p.colecao).doc(u.uid).get();
          if (!s.exists) continue;
          const x: any = s.data();
          if (!u.nome && p.nome && x[p.nome]) u.nome = String(x[p.nome]);
          if (!u.telefone && p.telefone && x[p.telefone]) u.telefone = String(x[p.telefone]);
          if (!u.email && p.email && x[p.email]) u.email = String(x[p.email]);
        }
      }),
    );
    return { total, pagina, tamanho, itens };
  });

  const hubUsuario = onCall(opcoes, async (req) => {
    exigirAdmin(req);
    const uid = String((req.data as any)?.uid ?? '');
    if (!uid) throw new HttpsError('invalid-argument', 'Informe o uid.');
    let u: UsuarioHub;
    try {
      u = deAuth(await getAuth().getUser(uid));
    } catch {
      throw new HttpsError('not-found', 'Usuário não encontrado.');
    }
    const perfis: Record<string, any> = {};
    for (const p of cfg.perfis) {
      const s = await db.collection(p.colecao).doc(uid).get();
      if (s.exists) perfis[p.colecao] = serializar(s.data());
    }
    const assinantes = await assinantesSeguro();
    return { ...u, perfis, assinatura: assinantes.find((a) => a.uid === uid) ?? null };
  });

  const hubAtualizarUsuario = onCall(opcoes, async (req) => {
    const admin = exigirAdmin(req);
    const d: any = req.data ?? {};
    const uid = String(d.uid ?? '');
    if (!uid) throw new HttpsError('invalid-argument', 'Informe o uid.');
    const atual = await getAuth().getUser(uid).catch(() => null);
    if (!atual) throw new HttpsError('not-found', 'Usuário não encontrado.');
    if (HUB_ADMINS.includes(String(atual.email ?? '').toLowerCase())) {
      throw new HttpsError('failed-precondition', 'Não é possível alterar a conta do administrador do hub.');
    }
    const authUpd: Record<string, any> = {};
    if (typeof d.nome === 'string') authUpd.displayName = d.nome.trim() || null;
    const interno = cfg.emailInterno?.test(atual.email ?? '') ?? false;
    if (
      typeof d.email === 'string' &&
      d.email.trim() &&
      !interno &&
      d.email.trim().toLowerCase() !== String(atual.email ?? '').toLowerCase()
    ) {
      authUpd.email = d.email.trim().toLowerCase();
    }
    if (typeof d.telefone === 'string') {
      let t = d.telefone.replace(/\D/g, '');
      if (t && !t.startsWith('55')) t = '55' + t;
      const e164 = t ? '+' + t : null;
      // Só mexe no telefone de LOGIN (SMS) de quem já entra por telefone.
      if (atual.phoneNumber && e164 && e164 !== atual.phoneNumber) authUpd.phoneNumber = e164;
    }
    if (typeof d.bloqueado === 'boolean') authUpd.disabled = d.bloqueado;
    try {
      if (Object.keys(authUpd).length) await getAuth().updateUser(uid, authUpd);
    } catch (e: any) {
      throw new HttpsError('invalid-argument', `Não foi possível atualizar o login: ${e.message}`);
    }
    if (d.bloqueado === true) await getAuth().revokeRefreshTokens(uid);

    for (const p of cfg.perfis) {
      const ref = db.collection(p.colecao).doc(uid);
      const s = await ref.get();
      if (!s.exists) continue;
      const upd: Record<string, any> = {};
      if (typeof d.nome === 'string' && p.nome) upd[p.nome] = d.nome.trim();
      if (typeof d.telefone === 'string' && p.telefone) upd[p.telefone] = d.telefone.trim();
      if (authUpd.email && p.email) upd[p.email] = authUpd.email;
      if (typeof d.bloqueado === 'boolean') {
        upd.bloqueadoHub = d.bloqueado;
        upd.bloqueadoHubEm = d.bloqueado ? Timestamp.now() : FieldValue.delete();
      }
      if (Object.keys(upd).length) await ref.set(upd, { merge: true });
    }
    if (typeof d.bloqueado === 'boolean' && cfg.aoBloquear) {
      await cfg.aoBloquear(db, uid, d.bloqueado);
    }
    await db.collection('hubAuditoria').add({
      acao: 'atualizarUsuario',
      uid,
      por: admin,
      dados: serializar({ ...d, uid: null }),
      em: Timestamp.now(),
    });
    return { ok: true };
  });

  const hubAssinantes = onCall(opcoes, async (req) => {
    exigirAdmin(req);
    const lista = await assinantesSeguro();
    lista.sort((a, b) => Number(b.ativa) - Number(a.ativa) || (a.validoAte ?? 0) - (b.validoAte ?? 0));
    return { itens: lista.map((a) => serializar(a)) };
  });

  return { hubResumo, hubUsuarios, hubUsuario, hubAtualizarUsuario, hubAssinantes };
}
