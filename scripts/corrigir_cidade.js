#!/usr/bin/env node
/**
 * Unifica as grafias de uma cidade no PrestadorAki.
 *
 * Caso de 20/10: a lista "Escolha a cidade" tinha "Criciuma", "Criciúma" e
 * "Crici�ma" (CSV salvo pelo Excel em ANSI e lido como UTF-8 — o "ú" virou
 * "�"). Quem ficou com "Crici�ma" nem aparecia na busca por Criciúma.
 *
 * Acha toda grafia que, sem acento, é a mesma cidade (o "�" vale por
 * qualquer letra) e troca pela grafia certa em:
 *   - providerDirectory: city, cityNormalized, cidadesAtendidas, cidadesNormalizadas
 *   - convitesPrestador: cidade
 *   - providers: city, addressCity
 *   - meta/cidades: tira as grafias erradas e deixa só a certa
 *
 * Sempre simula primeiro:
 *   node scripts/corrigir_cidade.js C:\caminho\chave.json "Criciúma"
 *   node scripts/corrigir_cidade.js C:\caminho\chave.json "Criciúma" --gravar
 */
const path = require('path');

let admin;
try {
  admin = require('firebase-admin');
} catch {
  console.error('firebase-admin não encontrado. Rode `npm install` dentro de scripts/ primeiro.');
  process.exit(1);
}

const [chave, certa, ...flags] = process.argv.slice(2);
const GRAVAR = flags.includes('--gravar');
if (!chave || !certa) {
  console.error('Uso: node scripts/corrigir_cidade.js <chave.json> "<Cidade certa>" [--gravar]');
  process.exit(1);
}

const norm = (s) => String(s ?? '').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '').trim();
const alvo = norm(certa);
// "crici\uFFFDma" casa com "criciuma": o caractere estragado vale por um qualquer.
function mesmaCidade(valor) {
  const v = norm(valor);
  if (!v) return false;
  if (v === alvo) return true;
  if (!v.includes('\uFFFD') || v.length !== alvo.length) return false;
  return [...v].every((ch, i) => ch === '\uFFFD' || ch === alvo[i]);
}
const errada = (valor) => mesmaCidade(valor) && String(valor).trim() !== certa;

/** "Crici�ma/SC" -> "Criciúma/SC" */
function corrigirComUf(item) {
  const [cid, ...resto] = String(item).split('/');
  return mesmaCidade(cid) ? [certa, ...resto].join('/') : item;
}

async function main() {
  admin.initializeApp({ credential: admin.credential.cert(require(path.resolve(chave))) });
  const db = admin.firestore();
  const agora = admin.firestore.FieldValue.serverTimestamp();
  const mudancas = []; // [ref, dados, descrição]

  // providerDirectory
  const dir = await db.collection('providerDirectory').get();
  for (const doc of dir.docs) {
    const d = doc.data();
    const upd = {};
    if (errada(d.city)) {
      upd.city = certa;
      upd.cityNormalized = alvo;
    }
    if (Array.isArray(d.cidadesAtendidas) && d.cidadesAtendidas.some((c) => errada(String(c).split('/')[0]))) {
      upd.cidadesAtendidas = [...new Set(d.cidadesAtendidas.map(corrigirComUf))];
    }
    if (Array.isArray(d.cidadesNormalizadas) && d.cidadesNormalizadas.some((c) => mesmaCidade(c) && c !== alvo)) {
      upd.cidadesNormalizadas = [...new Set(d.cidadesNormalizadas.map((c) => (mesmaCidade(c) ? alvo : c)))];
    }
    if (Object.keys(upd).length) {
      mudancas.push([doc.ref, { ...upd, updatedAt: agora }, `vitrine  ${d.name ?? doc.id}: "${d.city}"`]);
    }
  }

  // convitesPrestador
  const conv = await db.collection('convitesPrestador').get();
  for (const doc of conv.docs) {
    const d = doc.data();
    if (errada(d.cidade)) mudancas.push([doc.ref, { cidade: certa }, `convite  ${d.nome ?? doc.id}: "${d.cidade}"`]);
  }

  // providers
  const prov = await db.collection('providers').get();
  for (const doc of prov.docs) {
    const d = doc.data();
    const upd = {};
    if (errada(d.city)) upd.city = certa;
    if (errada(d.addressCity)) upd.addressCity = certa;
    if (Object.keys(upd).length) mudancas.push([doc.ref, upd, `conta    ${d.name ?? doc.id}: "${d.city ?? d.addressCity}"`]);
  }

  // meta/cidades
  const metaRef = db.collection('meta').doc('cidades');
  const meta = (await metaRef.get()).data() ?? {};
  const lista = Array.isArray(meta.cidades) ? meta.cidades.map(String) : [];
  const tirar = lista.filter((c) => mesmaCidade(c) && c !== certa);
  if (tirar.length || (lista.length && !lista.includes(certa) && lista.some(mesmaCidade))) {
    const nova = [...new Set(lista.map((c) => (mesmaCidade(c) ? certa : c)))];
    mudancas.push([metaRef, { cidades: nova }, `lista de cidades: tira ${tirar.map((t) => `"${t}"`).join(', ')}`]);
  }

  if (!mudancas.length) {
    console.log(`Nada a corrigir: todas as grafias de ${certa} já estão certas.`);
    return;
  }
  for (const [, , desc] of mudancas) console.log(`${GRAVAR ? 'CORRIGINDO' : '[simulação]'} ${desc} -> "${certa}"`);

  if (GRAVAR) {
    for (let i = 0; i < mudancas.length; i += 400) {
      const batch = db.batch();
      for (const [ref, dados] of mudancas.slice(i, i + 400)) batch.set(ref, dados, { merge: true });
      await batch.commit();
    }
    // A lista inteira precisa ser substituída (merge não apaga itens de array).
    const metaMud = mudancas.find(([ref]) => ref.path === metaRef.path);
    if (metaMud) await metaRef.update({ cidades: metaMud[1].cidades });
  }

  console.log(`\n${mudancas.length} registro(s) ${GRAVAR ? 'corrigidos' : 'seriam corrigidos'}.`);
  if (!GRAVAR) console.log('Nada foi gravado. Confira e rode de novo com --gravar.');
}

main().then(() => process.exit(0)).catch((e) => {
  console.error(e);
  process.exit(1);
});
