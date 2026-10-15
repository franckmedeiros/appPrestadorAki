/**
 * Restaura um prestador que sumiu de `providers` e/ou do `providerDirectory`.
 *
 * Caso de uso (15/10/2026): a conta existe no Authentication, mas
 * `providers/{uid}` não existe mais, e o anúncio `providerDirectory/{uid}`
 * foi tirado pela limpeza da vitrine (limpar-diretorio.js), que guardou
 * uma cópia num backup-diretorio-*.json.
 *
 * O que ele faz:
 *   1. Confere se o uid existe no Authentication (se não existir, para:
 *      use recriar-usuario-auth.js antes).
 *   2. Se `providers/{uid}` NÃO existe, cria com os dados do anúncio do
 *      backup + os dados pessoais de `clients/{uid}` (mesmo jeito que o
 *      servidor faz na assinatura), `listingStatus: 'active'` e
 *      `nextBudgetNumber: 1`. Sem `subscriptionStore`: fica como conta de
 *      cortesia (a reconciliação diária só lista, não corta).
 *      Se já existe, não mexe.
 *   3. Se `providerDirectory/{uid}` NÃO existe, restaura do backup, com as
 *      avaliações. Se já existe, não mexe.
 *
 * Credenciais: as mesmas dos outros scripts.
 *   gcloud auth application-default login
 * ou, no PowerShell, a chave de serviço que está na raiz do projeto:
 *   $env:GOOGLE_APPLICATION_CREDENTIALS="..\prestadoraki-firebase-adminsdk-fbsvc-849dd5061d.json"
 *
 * Rode dentro da pasta `functions`:
 *   node restaurar-prestador.js <uid>             -> SÓ MOSTRA o que faria
 *   node restaurar-prestador.js <uid> --aplicar   -> grava
 *
 * Por padrão procura o uid em todos os backup-diretorio-*.json desta pasta
 * (o mais recente primeiro). Para usar outro arquivo: --backup=arquivo.json
 */

const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');

const args = process.argv.slice(2);
const uid = args.find((a) => !a.startsWith('--'));
const APLICAR = args.includes('--aplicar');
const backupArg = (args.find((a) => a.startsWith('--backup=')) || '').slice('--backup='.length);

if (!uid) {
  console.error('Uso: node restaurar-prestador.js <uid> [--aplicar] [--backup=arquivo.json]');
  process.exit(1);
}

admin.initializeApp({ projectId: 'prestadoraki' });
const db = admin.firestore();
const { Timestamp, GeoPoint, FieldValue } = admin.firestore;

/** Desfaz o paraJson do limpar-diretorio.js. */
function deJson(v) {
  if (v === null || v === undefined) return v;
  if (Array.isArray(v)) return v.map(deJson);
  if (typeof v === 'object') {
    if (typeof v._timestamp === 'string') return Timestamp.fromDate(new Date(v._timestamp));
    if (Array.isArray(v._geo)) return new GeoPoint(v._geo[0], v._geo[1]);
    if (typeof v._ref === 'string') return db.doc(v._ref);
    if (typeof v._bytes === 'string') return Buffer.from(v._bytes, 'base64');
    const out = {};
    for (const [k, x] of Object.entries(v)) out[k] = deJson(x);
    return out;
  }
  return v;
}

function acharNoBackup() {
  const arquivos = backupArg
    ? [backupArg]
    : fs
        .readdirSync(__dirname)
        .filter((f) => /^backup-diretorio-.*\.json$/.test(f))
        .sort()
        .reverse();
  for (const arq of arquivos) {
    const lista = JSON.parse(fs.readFileSync(path.resolve(__dirname, arq), 'utf8'));
    const item = lista.find((x) => x.path === `providerDirectory/${uid}`);
    if (item) return { arq, item };
  }
  return null;
}

/** Grava um documento do backup e as subcoleções dele (recursivo). */
async function gravarComSubcolecoes(item, lote) {
  if (item.data) lote.push([db.doc(item.path), deJson(item.data)]);
  for (const docs of Object.values(item.subcolecoes || {})) {
    for (const d of docs) await gravarComSubcolecoes(d, lote);
  }
}

(async () => {
  // 1. Authentication
  let user;
  try {
    user = await admin.auth().getUser(uid);
  } catch (e) {
    console.error(`O uid ${uid} não existe no Authentication (${e.code || e.message}).`);
    console.error('Recrie a conta antes com: node recriar-usuario-auth.js <uid> <email> <senha> [nome]');
    process.exit(1);
  }
  console.log(`Conta: ${user.email || '(sem e-mail)'} · ${user.displayName || '(sem nome)'}`);

  const providerRef = db.collection('providers').doc(uid);
  const directoryRef = db.collection('providerDirectory').doc(uid);
  const [providerSnap, directorySnap, clientSnap] = await Promise.all([
    providerRef.get(),
    directoryRef.get(),
    db.collection('clients').doc(uid).get(),
  ]);
  console.log(`providers/${uid}: ${providerSnap.exists ? 'existe' : 'NÃO existe'}`);
  console.log(`providerDirectory/${uid}: ${directorySnap.exists ? 'existe' : 'NÃO existe'}`);
  console.log(`clients/${uid}: ${clientSnap.exists ? 'existe' : 'não existe'}`);

  const achado = acharNoBackup();
  const anuncio = achado ? deJson(achado.item.data) || {} : null;
  if (achado) console.log(`Anúncio encontrado no backup ${achado.arq}`);
  else console.log('Anúncio NÃO encontrado em nenhum backup-diretorio-*.json.');

  const escritas = []; // [ref, dados]

  // 2. providers/{uid}
  if (!providerSnap.exists) {
    if (!anuncio) {
      console.error('\nSem o anúncio no backup não dá pra saber categoria/cidade. Nada foi feito.');
      process.exit(1);
    }
    const cliente = clientSnap.data() || {};
    const pessoais = {};
    for (const campo of [
      'name', 'email', 'whatsapp', 'addressZipCode', 'addressStreet', 'addressNeighborhood',
      'addressCity', 'addressState', 'pixKey', 'logoUrl',
    ]) {
      if (cliente[campo] != null) pessoais[campo] = cliente[campo];
    }
    const categorias = Array.isArray(anuncio.categories) && anuncio.categories.length
      ? anuncio.categories
      : [anuncio.category].filter(Boolean);
    const novo = {
      name: user.displayName || anuncio.name || '',
      email: user.email || '',
      ...(anuncio.whatsapp ? { whatsapp: anuncio.whatsapp } : {}),
      ...(anuncio.logoUrl ? { logoUrl: anuncio.logoUrl } : {}),
      ...(anuncio.bio ? { description: anuncio.bio } : {}),
      ...pessoais, // o que está em clients/{uid} vale mais que o anúncio
      category: categorias[0],
      categories: categorias,
      city: anuncio.city,
      ...(anuncio.state ? { state: anuncio.state } : {}),
      listingStatus: 'active',
      nextBudgetNumber: 1,
      createdAt: anuncio.createdAt || FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    };
    escritas.push([providerRef, novo]);
  }

  // 3. providerDirectory/{uid} (+ avaliações)
  if (!directorySnap.exists && achado) {
    const lote = [];
    await gravarComSubcolecoes(achado.item, lote);
    for (const [ref, dados] of lote) {
      if (ref.path === directoryRef.path) {
        escritas.push([ref, { ...dados, visible: true, updatedAt: FieldValue.serverTimestamp() }]);
      } else {
        escritas.push([ref, dados]);
      }
    }
  }

  if (!escritas.length) {
    console.log('\nNada a restaurar.');
    process.exit(0);
  }

  console.log(`\n${APLICAR ? 'Gravando' : 'Gravaria'}:`);
  for (const [ref, dados] of escritas) {
    const resumo = Object.entries(dados)
      .filter(([k]) => !['bio', 'description', 'fotos', 'logoUrl'].includes(k))
      .map(([k, v]) => `${k}=${v instanceof Timestamp ? v.toDate().toISOString() : JSON.stringify(v)}`)
      .join(', ');
    console.log(`  ${ref.path}\n    ${resumo.slice(0, 400)}`);
  }

  if (!APLICAR) {
    console.log('\nNada foi gravado. Confira e rode de novo com --aplicar.');
    process.exit(0);
  }

  const batch = db.batch();
  for (const [ref, dados] of escritas) batch.set(ref, dados);
  await batch.commit();
  console.log('\nPronto. Feche e abra o app (ou saia e entre de novo) para ele recarregar o perfil.');
  process.exit(0);
})().catch((e) => {
  console.error('Erro:', e.message);
  process.exit(1);
});
