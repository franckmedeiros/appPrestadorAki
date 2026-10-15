/**
 * Encontra (e, se você pedir, apaga) dados "órfãos" no Firestore:
 * documentos que pertencem a um uid que NÃO existe mais no Firebase
 * Authentication.
 *
 * O que ele confere:
 *   providers/{uid}            -> id do documento
 *   clients/{uid}              -> id do documento
 *   providerDirectory/{id}     -> campo providerUid (anúncios SEM providerUid
 *                                 são os cadastrados à mão/curadoria e NUNCA
 *                                 são tocados)
 *   phoneIndex/{telefone}      -> campo clientUid (se ficar órfão, BLOQUEIA
 *                                 alguém de se cadastrar com esse telefone)
 *   assinaturasVerificadas/{t} -> campo uid
 *
 * Só mostra (não apaga) avaliações deixadas por contas apagadas em
 * providerDirectory/{id}/ratings — apagá-las mudaria a nota dos prestadores.
 *
 * providers e clients são apagados JUNTO com as subcoleções (budgets, jobs,
 * notifications, favorites...).
 *
 * Credenciais: as da sua conta Google (sem arquivo de chave):
 *   gcloud auth application-default login
 *
 * Rode dentro da pasta `functions` do projeto:
 *
 *   node limpar-orfaos.js            -> SÓ LISTA o que encontrou (não muda nada)
 *   node limpar-orfaos.js --apagar   -> salva um backup .json e depois apaga
 */

const fs = require('fs');
const admin = require('firebase-admin');

const PROJECT_ID = 'prestadoraki';
const APAGAR = process.argv.includes('--apagar');

admin.initializeApp({ projectId: PROJECT_ID });
const db = admin.firestore();
const auth = admin.auth();

async function todosOsUids() {
  const uids = new Set();
  let pageToken;
  do {
    const res = await auth.listUsers(1000, pageToken);
    res.users.forEach((u) => uids.add(u.uid));
    pageToken = res.pageToken;
  } while (pageToken);
  return uids;
}

// Converte valores do Firestore em JSON legível pro backup.
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

// Lê o documento e todas as subcoleções dele (pro backup).
async function lerComSubcolecoes(ref) {
  const snap = await ref.get();
  const item = { path: ref.path, data: snap.exists ? paraJson(snap.data()) : null, subcolecoes: {} };
  for (const col of await ref.listCollections()) {
    const docs = await col.listDocuments();
    item.subcolecoes[col.id] = [];
    for (const d of docs) item.subcolecoes[col.id].push(await lerComSubcolecoes(d));
  }
  return item;
}

function rotulo(data) {
  if (!data) return '';
  const partes = [data.name || data.nome, data.email, data.category, data.city, data.listingStatus]
    .filter(Boolean);
  return partes.length ? `  (${partes.join(' · ')})` : '';
}

(async () => {
  const uids = await todosOsUids();
  console.log(`Usuários no Authentication: ${uids.size}`);

  // Trava de segurança: se a lista de usuários vier vazia, provavelmente o
  // script está apontando pro projeto/credencial errado. Aí TUDO pareceria
  // órfão — então para aqui.
  if (uids.size === 0) {
    console.error('Nenhum usuário encontrado no Authentication. Confira a credencial/projeto. Nada foi feito.');
    process.exit(1);
  }

  const orfaos = []; // { ref, recursivo, descricao }

  for (const nome of ['providers', 'clients']) {
    const snap = await db.collection(nome).get();
    snap.forEach((doc) => {
      if (!uids.has(doc.id)) {
        orfaos.push({ ref: doc.ref, recursivo: true, descricao: `${doc.ref.path}${rotulo(doc.data())}` });
      }
    });
  }

  const regrasPorCampo = [
    { colecao: 'providerDirectory', campo: 'providerUid' },
    { colecao: 'phoneIndex', campo: 'clientUid' },
    { colecao: 'assinaturasVerificadas', campo: 'uid' },
  ];
  for (const { colecao, campo } of regrasPorCampo) {
    const snap = await db.collection(colecao).get();
    snap.forEach((doc) => {
      const dono = doc.get(campo);
      if (typeof dono === 'string' && dono && !uids.has(dono)) {
        orfaos.push({
          ref: doc.ref,
          recursivo: colecao === 'providerDirectory',
          descricao: `${doc.ref.path}  [${campo}=${dono}]${rotulo(doc.data())}`,
        });
      }
    });
  }

  // Avaliações de contas apagadas: só informa.
  const avaliacoesOrfas = [];
  const ratings = await db.collectionGroup('ratings').get();
  ratings.forEach((doc) => {
    if (doc.ref.parent.parent?.parent.id === 'providerDirectory' && !uids.has(doc.id)) {
      avaliacoesOrfas.push(doc.ref.path);
    }
  });

  if (orfaos.length === 0) {
    console.log('\nNenhum dado órfão encontrado. Nada a fazer.');
  } else {
    console.log(`\nDados órfãos encontrados (${orfaos.length}):`);
    orfaos.forEach((o) => console.log('  - ' + o.descricao));
  }
  if (avaliacoesOrfas.length) {
    console.log(`\nAvaliações deixadas por contas apagadas (NÃO serão apagadas): ${avaliacoesOrfas.length}`);
    avaliacoesOrfas.forEach((p) => console.log('  · ' + p));
  }

  if (!APAGAR || orfaos.length === 0) {
    if (orfaos.length) console.log('\nNada foi apagado. Confira a lista e rode de novo com --apagar.');
    process.exit(0);
  }

  // Backup antes de apagar.
  const backup = [];
  for (const o of orfaos) backup.push(await lerComSubcolecoes(o.ref));
  const arquivo = `backup-orfaos-${new Date().toISOString().replace(/[:.]/g, '-')}.json`;
  fs.writeFileSync(arquivo, JSON.stringify(backup, null, 2));
  console.log(`\nBackup salvo em ${arquivo}`);

  for (const o of orfaos) {
    if (o.recursivo) await db.recursiveDelete(o.ref);
    else await o.ref.delete();
    console.log('  apagado: ' + o.ref.path);
  }
  console.log(`\nPronto: ${orfaos.length} documento(s) órfão(s) apagado(s).`);
  console.log('Guarde o arquivo de backup fora do projeto (ele tem dados pessoais) e não envie pro Git.');
  process.exit(0);
})().catch((e) => {
  console.error('Erro:', e.message);
  process.exit(1);
});
