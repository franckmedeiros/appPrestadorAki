#!/usr/bin/env node
/**
 * Apaga o campo `pushDebug` de todos os documentos de `clients`.
 *
 *   node scripts/limpar_push_debug.js <chave.json>            # simulação
 *   node scripts/limpar_push_debug.js <chave.json> --gravar   # apaga
 *
 * `pushDebug` é o rastro de diagnóstico que o app gravava enquanto
 * caçávamos o bug do push no iPhone (ver NotificationService._debugLog e
 * a flag `kGravarDiagnosticoDePush` em lib/core/testing_flags.dart).
 * Agora que o push funciona e a gravação está desligada, o que ficou no
 * banco é só sujeira visual no Console.
 *
 * Apaga SÓ esse campo, com `FieldValue.delete()` — nada mais do documento
 * é tocado. Nenhuma tela do app lê `pushDebug`, então não há o que
 * quebrar: quem lia era você, no Console.
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
const LOTE = 400; // o limite do Firestore é 500 operações por batch

async function main() {
  const chave = process.argv[2];
  if (!chave || chave.startsWith('--')) {
    console.error('uso: node scripts/limpar_push_debug.js <chave.json> [--gravar]');
    process.exit(1);
  }
  if (!fs.existsSync(chave)) {
    console.error(`não achei a chave em ${chave}`);
    process.exit(1);
  }

  admin.initializeApp({ credential: admin.credential.cert(require(path.resolve(chave))) });
  const db = admin.firestore();

  console.log(GRAVAR ? '>>> MODO GRAVAÇÃO <<<' : '>>> simulação (nada será gravado) <<<');

  const snap = await db.collection('clients').get();
  const comDebug = snap.docs.filter((d) => d.data().pushDebug !== undefined);

  console.log(`documentos em clients:        ${snap.size}`);
  console.log(`com o campo pushDebug:        ${comDebug.length}`);
  comDebug.slice(0, 20).forEach((d) => console.log(`   - ${d.id}  (${d.data().name ?? 'sem nome'})`));

  if (!GRAVAR) {
    console.log('\nnada foi gravado. rode de novo com --gravar pra apagar.');
    return;
  }
  if (comDebug.length === 0) {
    console.log('nada a fazer.');
    return;
  }

  let feitos = 0;
  for (let i = 0; i < comDebug.length; i += LOTE) {
    const batch = db.batch();
    for (const doc of comDebug.slice(i, i + LOTE)) {
      batch.update(doc.ref, { pushDebug: admin.firestore.FieldValue.delete() });
      feitos++;
    }
    await batch.commit();
  }
  console.log(`pronto: campo removido de ${feitos} documento(s).`);
}

main().catch((e) => {
  console.error('\nfalhou:', e);
  process.exit(1);
});
