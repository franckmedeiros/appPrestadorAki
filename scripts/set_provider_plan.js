#!/usr/bin/env node
/**
 * Liga ou desliga o selo "Destaque" (plano pago) de um prestador do
 * diretório público (`providerDirectory` — ver DATA_MODEL.md e
 * firestore.rules). Hoje a assinatura é cobrada por fora do app (Franck
 * combina o pagamento direto com o prestador) — este script é a única
 * forma de marcar quem pagou, porque o firestore.rules bloqueia o próprio
 * prestador de gravar `featured`/`featuredUntil` no perfil dele mesmo.
 *
 * "Destaque" é sempre uma assinatura MENSAL: ativar sempre define uma data
 * de validade (`featuredUntil`), nunca fica destacado pra sempre sem
 * renovar. Se a validade passar, o selo some sozinho no app (ver
 * ProviderListing.isFeatured) — não precisa rodar nada pra "desligar",
 * só rodar de novo com `ativar` quando o prestador renovar o pagamento.
 *
 * Uso — busca pelo NOME (ou parte do nome), não pelo id do documento:
 *   cd scripts
 *   node set_provider_plan.js <service-account.json> "<nome do prestador>" ativar [dias]
 *   node set_provider_plan.js <service-account.json> "<nome do prestador>" desativar
 *
 * `dias` é opcional, padrão 30 (uma assinatura mensal). Se o nome bater
 * com mais de um prestador, o script lista todos e pede pra você escolher
 * o número certo — não precisa ir catar id nenhum no Console do Firebase.
 */

const fs = require('fs');
const path = require('path');
const readline = require('readline');
const admin = require('firebase-admin');

function confirm(question) {
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  return new Promise((resolve) => {
    rl.question(question, (answer) => {
      rl.close();
      resolve(answer.trim());
    });
  });
}

// Mesma ideia do _normalize do app (ClientHomeScreen): remove acento e
// caixa pra "jose zeferino" achar "José Zeferino" mesmo sem digitar
// certinho.
function normalize(value) {
  return value
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '');
}

function describe(data) {
  return `${data.name} — ${data.category} — ${data.city}${data.state ? '/' + data.state : ''}` +
    (data.claimed ? '' : '  [perfil não reivindicado, sem conta ainda]');
}

async function findListing(db, query) {
  // Firestore não tem busca por substring nativa — pro tamanho esperado
  // do diretório (prestadores de algumas regiões), ler tudo e filtrar
  // aqui é simples e barato o bastante (mesma lógica já usada em
  // ProviderDirectoryRepository.listCities no app).
  const snapshot = await db.collection('providerDirectory').get();
  const normalizedQuery = normalize(query);
  const matches = snapshot.docs.filter((doc) =>
    normalize(doc.data().name || '').includes(normalizedQuery),
  );

  if (matches.length === 0) return null;
  if (matches.length === 1) return matches[0];

  console.log(`\nMais de um prestador bateu com "${query}":\n`);
  matches.forEach((doc, i) => {
    console.log(`  ${i + 1}. ${describe(doc.data())}`);
  });
  const answer = await confirm('\nDigite o número do prestador certo (ou deixe em branco pra cancelar): ');
  const index = Number(answer) - 1;
  if (!Number.isInteger(index) || index < 0 || index >= matches.length) {
    return undefined; // cancelado / entrada inválida
  }
  return matches[index];
}

async function main() {
  const [, , serviceAccountPath, query, action, daysArg] = process.argv;
  if (!serviceAccountPath || !query || !['ativar', 'desativar'].includes(action)) {
    console.error(
      'Uso:\n' +
        '  node set_provider_plan.js <service-account.json> "<nome do prestador>" ativar [dias]\n' +
        '  node set_provider_plan.js <service-account.json> "<nome do prestador>" desativar',
    );
    process.exit(1);
  }

  const serviceAccount = JSON.parse(fs.readFileSync(path.resolve(serviceAccountPath), 'utf8'));
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
  const db = admin.firestore();

  const doc = await findListing(db, query);
  if (doc === null) {
    console.error(`\nNenhum prestador encontrado com "${query}" no nome. Confere a grafia (o jeito ` +
      'que está gravado no providerDirectory, sem precisar acento certinho) e tenta de novo.');
    process.exit(1);
  }
  if (doc === undefined) {
    console.log('Cancelado — nada foi escrito.');
    process.exit(0);
  }

  const ref = doc.ref;
  const data = doc.data();
  console.log(`\nPrestador: ${describe(data)}`);
  console.log(`(id do documento: ${doc.id})`);
  if (!data.claimed) {
    console.warn(
      '⚠️  Esse é um perfil NÃO reivindicado (ainda não tem conta no PrestadorAki) — ' +
        'Destaque só faz sentido pra quem já é cliente pagante de verdade. Confirma mesmo assim se ' +
        'for um teste.',
    );
  }

  if (action === 'desativar') {
    const answer = await confirm(`\nConfirma DESATIVAR o Destaque de "${data.name}"? (digite "sim" pra continuar) `);
    if (answer.trim().toLowerCase() !== 'sim') {
      console.log('Cancelado — nada foi escrito.');
      process.exit(0);
    }
    await ref.update({ featured: false, updatedAt: admin.firestore.FieldValue.serverTimestamp() });
    console.log(`\n✅ Destaque desativado para "${data.name}".`);
    process.exit(0);
  }

  const days = Number(daysArg) > 0 ? Number(daysArg) : 30;
  const until = new Date(Date.now() + days * 24 * 60 * 60 * 1000);
  console.log(`\nIsso vai marcar "${data.name}" como Destaque até ${until.toLocaleDateString('pt-BR')} (${days} dia(s)).`);
  const answer = await confirm('Confirma? (digite "sim" pra continuar) ');
  if (answer.trim().toLowerCase() !== 'sim') {
    console.log('Cancelado — nada foi escrito.');
    process.exit(0);
  }

  await ref.update({
    featured: true,
    featuredUntil: admin.firestore.Timestamp.fromDate(until),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  console.log(`\n✅ "${data.name}" está em Destaque até ${until.toLocaleDateString('pt-BR')}.`);
  process.exit(0);
}

main().catch((err) => {
  console.error('\nErro ao atualizar o plano:', err);
  process.exit(1);
});
