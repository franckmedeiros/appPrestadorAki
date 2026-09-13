#!/usr/bin/env node
/**
 * Prepara o `providerDirectory` existente pra busca filtrar no servidor.
 *
 *   node scripts/backfill_diretorio.js <chave.json>            # simulação
 *   node scripts/backfill_diretorio.js <chave.json> --gravar   # grava
 *
 * Faz duas coisas, uma passada só:
 *
 * 1. Grava `nameNormalized` e `cityNormalized` (minúsculas, sem acento)
 *    em quem ainda não tem. São eles que permitem a busca comparar no
 *    Firestore — sem isso, ela teria que baixar a coleção inteira e
 *    comparar no app, que é exatamente o problema que estamos resolvendo.
 *    A Cloud Function `onListagemEscrita` mantém esses campos daqui pra
 *    frente; este script é pro acervo que já está lá.
 *
 * 2. Monta `meta/cidades`, o documento único com a lista de cidades que
 *    têm prestador — lido pelo autocomplete da busca no lugar de varrer
 *    a coleção toda.
 *
 * Roda de novo sem problema: quem já está normalizado é pulado.
 *
 * NOTA SOBRE A FUNÇÃO: se `onListagemEscrita` já estiver publicada, cada
 * documento que este script gravar vai disparar ela — que vai olhar,
 * achar tudo certo e não escrever nada (é a guarda anti-loop dela). Não
 * dá problema, mas roda mais barato se você fizer o backfill ANTES do
 * deploy da função.
 */
const fs = require('fs');
const path = require('path');

let admin;
try {
  admin = require('firebase-admin');
} catch (e) {
  console.error('firebase-admin não encontrado. Rode `npm install` dentro de scripts/ primeiro.');
  process.exit(1);
}

const GRAVAR = process.argv.includes('--gravar');
const LOTE = 400;

function normalizar(valor) {
  return String(valor || '')
    .toLowerCase()
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '');
}

async function main() {
  const chave = process.argv[2];
  if (!chave || chave.startsWith('--')) {
    console.error('uso: node scripts/backfill_diretorio.js <chave.json> [--gravar]');
    process.exit(1);
  }
  if (!fs.existsSync(chave)) {
    console.error(`não achei a chave em ${chave}`);
    process.exit(1);
  }

  admin.initializeApp({ credential: admin.credential.cert(require(path.resolve(chave))) });
  const db = admin.firestore();

  console.log(GRAVAR ? '>>> MODO GRAVAÇÃO <<<' : '>>> simulação (nada será gravado) <<<');
  console.log('lendo providerDirectory...');
  const snap = await db.collection('providerDirectory').get();
  console.log(`${snap.size} documento(s).`);

  const pendentes = [];
  const cidades = new Map(); // normalizada -> primeira grafia vista
  let semCidade = 0;

  for (const doc of snap.docs) {
    const d = doc.data();
    const nomeOk = normalizar(d.name);
    const cidadeOk = normalizar(d.city);

    if ((d.name && d.nameNormalized !== nomeOk) || (d.city && d.cityNormalized !== cidadeOk)) {
      pendentes.push({ ref: doc.ref, nomeOk, cidadeOk, temNome: !!d.name, temCidade: !!d.city });
    }

    if (d.visible === false) continue;
    if (!d.city) {
      semCidade++;
      continue;
    }
    // Dedupe pela grafia normalizada, guardando a primeira forma vista
    // como rótulo — não tenta adivinhar qual grafia está "certa" entre
    // "Criciuma" e "Criciúma".
    if (!cidades.has(cidadeOk)) cidades.set(cidadeOk, d.city);
  }

  console.log(`precisam de normalização: ${pendentes.length}`);
  console.log(`cidades distintas:        ${cidades.size}`);
  if (semCidade) console.log(`sem cidade (ignorados no resumo): ${semCidade}`);
  console.log(`   ${[...cidades.values()].sort().slice(0, 12).join(', ')}${cidades.size > 12 ? ', ...' : ''}`);

  if (!GRAVAR) {
    console.log('\nnada foi gravado. rode de novo com --gravar.');
    return;
  }

  let feitos = 0;
  for (let i = 0; i < pendentes.length; i += LOTE) {
    const batch = db.batch();
    for (const p of pendentes.slice(i, i + LOTE)) {
      batch.update(p.ref, {
        ...(p.temNome ? { nameNormalized: p.nomeOk } : {}),
        ...(p.temCidade ? { cityNormalized: p.cidadeOk } : {}),
      });
      feitos++;
    }
    await batch.commit();
    process.stdout.write(`\r  normalizados ${feitos}/${pendentes.length}`);
  }
  if (pendentes.length) console.log('');

  await db
    .collection('meta')
    .doc('cidades')
    .set({
      cidades: [...cidades.values()].sort((a, b) => a.localeCompare(b, 'pt-BR')),
      atualizadoEm: admin.firestore.FieldValue.serverTimestamp(),
    });
  console.log(`meta/cidades gravado com ${cidades.size} cidade(s).`);
  console.log('pronto.');
}

main().catch((e) => {
  console.error('\nfalhou:', e);
  process.exit(1);
});
