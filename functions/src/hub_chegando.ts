/**
 * HUB · "Chegando": os pré-cadastros com consentimento (ver convites.ts).
 *
 * São as entradas do `providerDirectory` com `claimed: false` e
 * `aceitaPedidos: true`, criadas pelo scripts/registrar_convites.js a partir
 * de quem disse SIM no WhatsApp. O app mostra "Este profissional está
 * chegando ao PrestadorAki" no perfil delas. Aqui o Franck ajusta esse
 * cadastro pelo hub em vez de editar CSV e rodar o script de novo.
 *
 *   hubChegando        — lista, com o convite (privado) e os pedidos esperando
 *   hubSalvarChegando  — salva nome, categorias, cidades, descrição, Instagram,
 *                        WhatsApp do convite e se aparece na busca
 *   hubLogoChegando    — sobe (ou tira) a logo
 *   hubJuntarChegando  — junta com a conta do prestador que já existe
 *                        (mesma empresa já assinante — ver juntar_pre_cadastro.ts)
 *
 * Só atende o dono do hub (exigirAdmin, ver hub_core.ts). Entradas já
 * reivindicadas (`claimed: true`) não são editadas por aqui: a partir daí
 * quem mantém o perfil é o próprio prestador, pelo app.
 *
 * INSTAGRAM NUNCA VAI PRO DIRETÓRIO PÚBLICO enquanto o prestador está
 * chegando (decisão do Franck, 17/10): seria um jeito de o cliente falar
 * direto com ele por fora, e o contato é o que a assinatura libera. Fica só
 * no convite (privado) e passa pra `providers/{uid}` quando ele assume o
 * perfil pelo código (ver reivindicarPerfilPrestador em convites.ts) — aí
 * ele mesmo publica ao salvar o perfil no app.
 */
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { FieldValue, Timestamp } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import { getAuth } from 'firebase-admin/auth';
import { randomUUID } from 'crypto';
import { db } from './lib/admin';
import { exigirAdmin } from './hub_core';
import { CATEGORIAS } from './categorias';
import { juntarPreCadastro, telefoneSemDdi } from './juntar_pre_cadastro';

const texto = (v: unknown, max = 300) => String(v ?? '').trim().slice(0, max);

/** Mesma normalização da busca (normalizeForSearch no app). */
function normalizar(valor: string): string {
  return valor.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').trim();
}

/** Só dígitos, sem 55 — mesmo formato do `phoneNormalized` do app. */
function telefoneNormalizado(bruto: unknown): string | null {
  let d = String(bruto ?? '').replace(/\D/g, '');
  if (d.startsWith('55') && d.length >= 12) d = d.slice(2);
  if (d.startsWith('0')) d = d.slice(1);
  return d.length === 10 || d.length === 11 ? d : null;
}

/** "@fulano", link do perfil ou "fulano" → "fulano" (mesma regra de lib/core/instagram.dart). */
function instagramNormalizado(bruto: unknown): string | null {
  let t = String(bruto ?? '').trim();
  if (!t) return null;
  const url = /instagram\.com\/([^/?#\s]+)/i.exec(t);
  if (url) t = url[1];
  t = t.replace(/^@+/, '').trim();
  if (!t) return null;
  if (!/^[A-Za-z0-9._]{1,30}$/.test(t)) {
    throw new HttpsError('invalid-argument', 'Instagram: use só o nome de usuário, ex.: @seuperfil');
  }
  return t.toLowerCase();
}

const ms = (v: unknown): number | null => (v instanceof Timestamp ? v.toMillis() : null);

async function entradaEditavel(id: string) {
  if (!/^[A-Za-z0-9_\-]{1,120}$/.test(id)) throw new HttpsError('invalid-argument', 'id inválido.');
  const ref = db.collection('providerDirectory').doc(id);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError('not-found', 'Pré-cadastro não encontrado.');
  if (snap.data()?.claimed === true) {
    throw new HttpsError('failed-precondition', 'Esse perfil já foi assumido pelo prestador; ele edita pelo app.');
  }
  return { ref, snap };
}

// ---------------------------------------------------------------------------

export const hubChegando = onCall({ timeoutSeconds: 120 }, async (req) => {
  exigirAdmin(req);

  const [entradas, pedidos, contas] = await Promise.all([
    db.collection('providerDirectory').where('claimed', '==', false).where('aceitaPedidos', '==', true).get(),
    db.collection('pedidosSemConta').get(),
    db.collection('providerDirectory').where('claimed', '==', true).get(),
  ]);

  // Contas de prestador (perfil publicado) por telefone e por uid — pra
  // avisar quando um pré-cadastro é da mesma empresa de uma conta que já
  // existe (aí é só juntar).
  const contaPorTelefone = new Map<string, { uid: string; nome: string; visivel: boolean }>();
  const contaPorUid = new Map<string, { uid: string; nome: string; visivel: boolean }>();
  for (const c of contas.docs) {
    const x = c.data();
    const info = { uid: c.id, nome: String(x.name ?? ''), visivel: x.visible !== false };
    contaPorUid.set(c.id, info);
    const tel = telefoneSemDdi(x.phoneNormalized ?? x.whatsapp);
    if (tel && !contaPorTelefone.has(tel)) contaPorTelefone.set(tel, info);
  }

  // Pedidos por pré-cadastro: total e os que ainda esperam o prestador.
  const contagem = new Map<string, { total: number; esperando: number }>();
  for (const p of pedidos.docs) {
    const d = p.data();
    const id = String(d.listingId ?? '');
    if (!id) continue;
    const c = contagem.get(id) ?? { total: 0, esperando: 0 };
    c.total++;
    if (d.status === 'aguardando') c.esperando++;
    contagem.set(id, c);
  }

  const convites = entradas.empty
    ? []
    : await db.getAll(...entradas.docs.map((e) => db.collection('convitesPrestador').doc(e.id)));
  const convitePorId = new Map(convites.map((c) => [c.id, c.data() ?? null]));

  const itens = entradas.docs.map((e) => {
    const d = e.data();
    const c = convitePorId.get(e.id) ?? {};
    const n = contagem.get(e.id) ?? { total: 0, esperando: 0 };
    return {
      id: e.id,
      nome: d.name ?? '',
      categorias: Array.isArray(d.categories) && d.categories.length ? d.categories : d.category ? [d.category] : [],
      cidade: d.city ?? '',
      uf: d.state ?? '',
      cidadesAtendidas: Array.isArray(d.cidadesAtendidas) ? d.cidadesAtendidas : [],
      bio: d.bio ?? '',
      instagram: c.instagram ?? '',
      logoUrl: d.logoUrl ?? '',
      visivel: d.visible !== false,
      criadoEm: ms(d.createdAt),
      atualizadoEm: ms(d.updatedAt),
      // Do convite (privado — nunca vai pro diretório público).
      whatsapp: c.whatsapp ?? d.phoneNormalized ?? '',
      consentimentoEm: ms(c.consentimentoEm),
      codigo: c.codigo ?? null,
      ultimoAvisoEm: ms(c.ultimoAvisoEm),
      ultimoErroAviso: c.ultimoErroAviso ?? null,
      optout: c.optout === true,
      reivindicadoPor: c.uid ?? null,
      semConvite: !convitePorId.get(e.id),
      // Conta do app que parece ser a mesma empresa: a que assumiu pelo
      // código, ou a que tem o mesmo telefone.
      contaEncontrada:
        (c.uid ? contaPorUid.get(String(c.uid)) : undefined) ??
        contaPorTelefone.get(telefoneSemDdi(c.whatsapp ?? d.phoneNormalized) ?? '') ??
        null,
      pedidos: n.total,
      pedidosEsperando: n.esperando,
    };
  });
  itens.sort((a, b) => String(a.nome).localeCompare(String(b.nome), 'pt-BR'));

  return {
    itens,
    categorias: CATEGORIAS,
  };
});

// ---------------------------------------------------------------------------

export const hubSalvarChegando = onCall(async (req) => {
  exigirAdmin(req);
  const d = (req.data ?? {}) as Record<string, unknown>;
  const id = texto(d.id, 120);
  const { ref } = await entradaEditavel(id);

  const nome = texto(d.nome, 120);
  if (!nome) throw new HttpsError('invalid-argument', 'Informe o nome.');

  const validas = new Set(CATEGORIAS.map((c) => c.id));
  const categorias = [...new Set((Array.isArray(d.categorias) ? d.categorias : []).map((c) => texto(c, 60)))]
    .filter((c) => validas.has(c))
    .slice(0, 5);
  if (!categorias.length) throw new HttpsError('invalid-argument', 'Escolha ao menos uma categoria.');

  const cidade = texto(d.cidade, 80);
  if (!cidade) throw new HttpsError('invalid-argument', 'Informe a cidade.');
  const uf = texto(d.uf, 2).toUpperCase();
  if (uf && !/^[A-Z]{2}$/.test(uf)) throw new HttpsError('invalid-argument', 'UF inválida.');

  const principal = uf ? `${cidade}/${uf}` : cidade;
  const outras = (Array.isArray(d.cidadesAtendidas) ? d.cidadesAtendidas : [])
    .map((c) => texto(c, 100))
    .filter((c) => c && normalizar(c.split('/')[0]) !== normalizar(cidade));
  const cidadesAtendidas = [principal, ...new Set(outras)].slice(0, 30);
  const cidadesNormalizadas = [...new Set(cidadesAtendidas.map((c) => normalizar(c.split('/')[0])))];

  const bio = texto(d.bio, 400);
  const instagram = instagramNormalizado(d.instagram);

  const whatsapp = texto(d.whatsapp, 30);
  const tel = whatsapp ? telefoneNormalizado(whatsapp) : null;
  if (whatsapp && !tel) throw new HttpsError('invalid-argument', 'WhatsApp inválido (precisa de DDD).');

  const visivel = d.visivel !== false;
  const agora = FieldValue.serverTimestamp();

  await ref.set(
    {
      name: nome,
      nameNormalized: normalizar(nome),
      category: categorias[0],
      categories: categorias,
      city: cidade,
      cityNormalized: normalizar(cidade),
      state: uf || FieldValue.delete(),
      cidadesAtendidas,
      cidadesNormalizadas,
      bio: bio || FieldValue.delete(),
      // Nunca público aqui (ver o topo do arquivo); limpa se já estava.
      instagram: FieldValue.delete(),
      // Só os dígitos: é por ele que a assinatura casa esta entrada com a
      // conta do prestador. O WhatsApp em si nunca vira campo público.
      ...(tel ? { phoneNormalized: tel } : {}),
      visible: visivel,
      editadoPeloHubEm: agora,
      updatedAt: agora,
    },
    { merge: true },
  );

  await db.collection('convitesPrestador').doc(id).set(
    {
      nome,
      categoria: categorias[0],
      cidade,
      instagram: instagram || FieldValue.delete(),
      ...(tel ? { whatsapp: tel } : {}),
      atualizadoEm: agora,
    },
    { merge: true },
  );

  // Autocomplete da busca (meta/cidades).
  await db.collection('meta').doc('cidades').set(
    { cidades: FieldValue.arrayUnion(...cidadesAtendidas.map((c) => c.split('/')[0].trim())) },
    { merge: true },
  );

  return { ok: true };
});

// ---------------------------------------------------------------------------

const LIMITE_LOGO = 5 * 1024 * 1024;

export const hubLogoChegando = onCall({ timeoutSeconds: 60 }, async (req) => {
  exigirAdmin(req);
  const d = (req.data ?? {}) as Record<string, unknown>;
  const id = texto(d.id, 120);
  const { ref } = await entradaEditavel(id);

  // Sem imagem = tirar a logo.
  if (d.base64 == null || d.base64 === '') {
    await ref.set({ logoUrl: FieldValue.delete(), updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    return { logoUrl: null };
  }

  const bytes = Buffer.from(String(d.base64), 'base64');
  if (bytes.length < 100) throw new HttpsError('invalid-argument', 'Imagem vazia.');
  if (bytes.length > LIMITE_LOGO) throw new HttpsError('invalid-argument', 'Imagem maior que 5 MB.');

  const png = bytes[0] === 0x89 && bytes[1] === 0x50;
  const jpg = bytes[0] === 0xff && bytes[1] === 0xd8;
  const webp = bytes.slice(0, 4).toString() === 'RIFF' && bytes.slice(8, 12).toString() === 'WEBP';
  if (!png && !jpg && !webp) throw new HttpsError('invalid-argument', 'Use JPG, PNG ou WEBP.');

  // Mesmo caminho do scripts/registrar_convites.js e do app.
  const caminho = `providers/${id}/logo.jpg`;
  const token = randomUUID();
  const bucket = getStorage().bucket();
  await bucket.file(caminho).save(bytes, {
    resumable: false,
    metadata: {
      contentType: png ? 'image/png' : webp ? 'image/webp' : 'image/jpeg',
      cacheControl: 'public, max-age=86400',
      metadata: { firebaseStorageDownloadTokens: token },
    },
  });
  // `cb` muda a URL a cada troca, pra nenhum cache mostrar a logo antiga.
  const logoUrl =
    `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(caminho)}` +
    `?alt=media&token=${token}&cb=${Date.now()}`;
  await ref.set({ logoUrl, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
  return { logoUrl };
});

// ---------------------------------------------------------------------------

/**
 * Junta o pré-cadastro com a conta do prestador que já existe (por `uid`
 * ou pelo `email` da conta): avaliações, logo/descrição se faltarem,
 * pedidos esperando viram orçamentos dele, e o pré-cadastro some da busca.
 */
export const hubJuntarChegando = onCall({ timeoutSeconds: 120 }, async (req) => {
  exigirAdmin(req);
  const d = (req.data ?? {}) as Record<string, unknown>;
  const id = texto(d.id, 120);
  await entradaEditavel(id);

  let uid = texto(d.uid, 128);
  const email = texto(d.email, 200).toLowerCase();
  if (!uid && email) {
    try {
      uid = (await getAuth().getUserByEmail(email)).uid;
    } catch {
      throw new HttpsError('not-found', `Nenhuma conta com o e-mail ${email}.`);
    }
  }
  if (!uid) throw new HttpsError('invalid-argument', 'Informe a conta (uid ou e-mail).');

  const r = await juntarPreCadastro(id, uid);
  if (!r.juntou) throw new HttpsError('failed-precondition', `Não deu pra juntar: ${r.motivo}.`);
  return r;
});
