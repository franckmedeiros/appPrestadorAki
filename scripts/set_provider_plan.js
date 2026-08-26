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
 * Uso:
 *   cd scripts
 *   node set_provider_plan.js <service-account.json> <providerDirectoryId> ativar [dias]
 *   node set_provider_plan.js <service-account.json> <providerDirectoryId> desativar
 *
 * `dias` é opcional, padrão 30 (uma assinatura mensal).
 *
 * Não sabe o id do documento de cabeça? Ele é o mesmo uid do prestador
 * (perfil reivindicado) — dá pra achar no Console do Firebase, coleção
 * providerDirectory, procurando pelo nome, ou pedindo pro próprio
 * prestador o e-mail/uid da conta dele.
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
      resolve(answer.trim().toLowerCase());
    });
  });
}

async function main() {
  const [, , serviceAccountPath, listingId, action, daysArg] = process.argv;
  if (!serviceAccountPath || !listingId || !['ativar', 'desativar'].includes(action)) {
    console.error(
      'Uso:\n' +
        '  node set_provider_plan.js <service-account.json> <providerDirectoryId> ativar [dias]\n' +
        '  node set_provider_plan.js <service-account.json> <providerDirectoryId> desativar',
    );
    process.exit(1);
  }

  const serviceAccount = JSON.parse(fs.readFileSync(path.resolve(serviceAccountPath), 'utf8'));
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
  const db = admin.firestore();

  const ref = db.collection('providerDirectory').doc(listingId);
  const snapshot = await ref.get();
  if (!snapshot.exists) {
    console.error(`\nNão existe nenhum prestador com id "${listingId}" em providerDirectory.`);
    process.exit(1);
  }
  const data = snapshot.data();
  console.log(`\nPrestador encontrado: ${data.name} — ${data.category} — ${data.city}${data.state ? '/' + data.state : ''}`);
  if (!data.claimed) {
    console.warn(
      '⚠️  Esse é um perfil NÃO reivindicado (ainda não tem conta no PrestadorAki) — ' +
        'Destaque só faz sentido pra quem já é cliente pagante de verdade. Confirma mesmo assim se ' +
        'for um teste.',
    );
  }

  if (action === 'desativar') {
    const answer = await confirm(`\nConfirma DESATIVAR o Destaque de "${data.name}"? (digite "sim" pra continuar) `);
    if (answer !== 'sim') {
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
  if (answer !== 'sim') {
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
