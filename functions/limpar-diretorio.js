/**
 * Limpa o providerDirectory (a vitrine de prestadores do app), deixando só
 * os anúncios de prestadores que realmente existem.
 *
 * Um anúncio FICA quando:
 *   - tem o campo providerUid, E
 *   - esse uid existe no Firebase Authentication, E
 *   - existe o documento providers/{providerUid}.
 *
 * Todo o resto SAI (com as avaliações dentro dele):
 *   - anúncios cadastrados à mão / curadoria (sem providerUid);
 *   - anúncios de contas apagadas;
 *   - anúncios cujo cadastro de prestador não existe mais.
 *
 * Credenciais: as da sua conta Google (sem arquivo de chave):
 *   gcloud auth application-default login
 *
 * Rode dentro da pasta `functions` do projeto:
 *
 *   node limpar-diretorio.js            -> SÓ LISTA (não muda nada)
 *   node limpar-diretorio.js --apagar   -> salva backup .json e apaga
 */

const fs = require('fs');
const admin = require('firebase-admin');

const APAGAR = process.argv.includes('--apagar');

admin.initializeApp({ projectId: 'prestadoraki' });
const db = admin.firestore();

async function todosOsUids() {
  const uids = new Set();
  let pageToken;
  do {
    const res = await admin.auth().listUsers(1000, pageToken);
    res.users.forEach((u) => uids.add(u.uid));
    pageToken = res.pageToken;
  } while (pageToken);
  return uids;
}

function paraJson(valor) {
  if (valor === null || valor === undefined) return valor;
  if (valor instanceof admin.firestore.Timestamp) return { _timestamp: valor.toDate().toISOString() };
  if (valor instanceof admin.firestore.GeoPoint) return { _geo: [valor.latitude, valor.longitude] };
  if (valor instanceof admin.firestore.DocumentReference) return { _ref: valor.path };
  if (Buffer.isBuffer(valor)) return { _bytes: valor.toString('base64') };
  if (Array.isArray(valor)) return valor.map(paraJson);
  if (typeof valor === 'object') {
    const out = {};
    for (const [k, v] of Object.entries(valor)) out[k] = paraJson(v);
    return out;
  }
  return valor;
}

async function lerComSubcolecoes(ref) {
  const snap = await ref.get();
  const item = { path: ref.path, data: snap.exists ? paraJson(snap.data()) : null, subcolecoes: {} };
  for (const col of await ref.listCollections()) {
    item.subcolecoes[col.id] = [];
    for (const d of await col.listDocuments()) item.subcolecoes[col.id].push(await lerComSubcolecoes(d));
  }
  return item;
}

function rotulo(d) {
  const partes = [d.name || d.nome || d.displayName, d.category || d.categoria, d.city || d.cidade]
    .filter(Boolean);
  return partes.length ? partes.join(' · ') : '(sem nome)';
}

(async () => {
  const uids = await todosOsUids();
  if (uids.size === 0) {
    console.error('Nenhum usuário no Authentication. Confira a credencial/projeto. Nada foi feito.');
    process.exit(1);
  }

  const prestadores = new Set((await db.collection('providers').get()).docs.map((d) => d.id));
  const anuncios = await db.collection('providerDirectory').get();

  const ficam = [];
  const saem = [];
  anuncios.forEach((doc) => {
    const d = doc.data();
    const uid = d.providerUid;
    let motivo = null;
    if (typeof uid !== 'string' || !uid) motivo = 'cadastrado à mão (sem providerUid)';
    else if (!uids.has(uid)) motivo = 'conta não existe mais';
    else if (!prestadores.has(uid)) motivo = 'cadastro de prestador não existe';
    (motivo ? saem : ficam).push({ ref: doc.ref, texto: `${doc.id}  ${rotulo(d)}`, motivo });
  });

  console.log(`Anúncios no providerDirectory: ${ficam.length + saem.length}`);
  console.log(`\nFICAM (${ficam.length}):`);
  ficam.forEach((a) => console.log('  ✓ ' + a.texto));
  console.log(`\nSAEM (${saem.length}):`);
  saem.forEach((a) => console.log(`  ✗ ${a.texto}  — ${a.motivo}`));

  // Trava: se nenhum anúncio ficaria, algo está errado (credencial/projeto).
  if (ficam.length === 0 && saem.length > 0) {
    console.error('\nNenhum anúncio ficaria — isso não parece certo. Nada foi feito.');
    process.exit(1);
  }

  if (!APAGAR || saem.length === 0) {
    console.log(saem.length ? '\nNada foi apagado. Confira a lista e rode de novo com --apagar.' : '\nNada a limpar.');
    process.exit(0);
  }

  const backup = [];
  for (const a of saem) backup.push(await lerComSubcolecoes(a.ref));
  const arquivo = `backup-diretorio-${new Date().toISOString().replace(/[:.]/g, '-')}.json`;
  fs.writeFileSync(arquivo, JSON.stringify(backup, null, 2));
  console.log(`\nBackup salvo em ${arquivo}`);

  for (const a of saem) {
    await db.recursiveDelete(a.ref);
    console.log('  apagado: ' + a.ref.path);
  }
  console.log(`\nPronto: ${saem.length} anúncio(s) removido(s). Ficaram ${ficam.length}.`);
  console.log('Guarde o backup fora do projeto e não envie pro Git.');
  process.exit(0);
})().catch((e) => {
  console.error('Erro:', e.message);
  process.exit(1);
});
