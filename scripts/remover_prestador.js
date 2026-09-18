#!/usr/bin/env node
/**
 * Faz uma conta deixar de ser prestador, voltando a ser só cliente.
 *
 *   node scripts/remover_prestador.js chave.json fulano@email.com
 *   node scripts/remover_prestador.js chave.json fulano@email.com --gravar
 *   node scripts/remover_prestador.js chave.json fulano@email.com --so-vitrine --gravar
 *
 * (Aceita o uid no lugar do e-mail, se preferir.)
 *
 * POR QUE PRECISA DISSO: no app não existe "deixar de ser prestador". A
 * conta vira prestador quando `providers/{uid}` passa a existir (ver
 * AuthController._checkIsProvider) e some da busca quando a listagem em
 * `providerDirectory/{uid}` sai do ar — não há tela que desfaça isso, e
 * criar uma seria desenhar um caminho que nenhum usuário de verdade pede.
 *
 * DOIS MODOS:
 *
 * `--so-vitrine` só ESCONDE da busca (`visible: false`). A conta continua
 * prestador, com agenda, clientes e orçamentos intactos, e volta a
 * aparecer quando você quiser. É o modo reversível.
 *
 * Sem `--so-vitrine`, a conta volta a ser SÓ CLIENTE: apaga
 * `providers/{uid}` inteiro e a listagem. Isso leva junto orçamentos,
 * serviços, clientes e compromissos daquele prestador. Não tem desfazer.
 *
 * `recursiveDelete`, e não `delete`: apagar um documento no Firestore NÃO
 * apaga as subcoleções dele — elas ficam órfãs, invisíveis no Console e
 * ainda contando como dados. Foi exatamente o bug que a exclusão de conta
 * teve em setembro (ver functions/src/account.ts).
 *
 * SIMULA POR PADRÃO. Sem `--gravar` só mostra o que faria.
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
const SO_VITRINE = process.argv.includes('--so-vitrine');

const SUBCOLECOES = ['budgets', 'jobs', 'customers', 'appointments'];

async function contar(ref) {
  try {
    const snap = await ref.count().get();
    return snap.data().count;
  } catch (e) {
    // `count()` é recente; se o SDK instalado não tiver, cai pra leitura.
    const snap = await ref.limit(500).get();
    return snap.size;
  }
}

async function main() {
  const chave = process.argv[2];
  const alvo = process.argv[3];
  if (!chave || chave.startsWith('--') || !alvo || alvo.startsWith('--')) {
    console.error('uso: node scripts/remover_prestador.js chave.json <email-ou-uid> [--so-vitrine] [--gravar]');
    process.exit(1);
  }
  if (!fs.existsSync(chave)) {
    console.error(`não achei a chave em ${chave}`);
    process.exit(1);
  }

  admin.initializeApp({ credential: admin.credential.cert(require(path.resolve(chave))) });
  const db = admin.firestore();

  let uid = alvo;
  let email = '(uid informado direto)';
  if (alvo.includes('@')) {
    try {
      const user = await admin.auth().getUserByEmail(alvo);
      uid = user.uid;
      email = user.email;
    } catch (e) {
      console.error(`não achei conta com o e-mail ${alvo}.`);
      process.exit(1);
    }
  } else {
    try {
      email = (await admin.auth().getUser(uid)).email || '(sem e-mail)';
    } catch (e) {
      console.error(`não achei conta com o uid ${uid}.`);
      process.exit(1);
    }
  }

  console.log(`conta:  ${email}`);
  console.log(`uid:    ${uid}`);
  console.log(SO_VITRINE ? '>>> MODO: só esconder da busca <<<' : '>>> MODO: voltar a ser só cliente <<<');
  console.log(GRAVAR ? '>>> GRAVANDO <<<' : '>>> simulação (nada será gravado) <<<');
  console.log('');

  const providerRef = db.collection('providers').doc(uid);
  const listingRef = db.collection('providerDirectory').doc(uid);
  const [providerSnap, listingSnap] = await Promise.all([providerRef.get(), listingRef.get()]);

  console.log(`providers/${uid}:          ${providerSnap.exists ? 'existe' : 'NÃO existe'}`);
  console.log(`providerDirectory/${uid}:  ${listingSnap.exists ? 'existe' : 'NÃO existe'}`);
  if (listingSnap.exists) {
    console.log(`   nome:    ${listingSnap.get('name') || '(sem nome)'}`);
    console.log(`   visible: ${listingSnap.get('visible')}`);
  }

  if (!providerSnap.exists && !listingSnap.exists) {
    console.log('\nessa conta já não é prestador. nada a fazer.');
    return;
  }

  if (providerSnap.exists) {
    console.log('\ndados do prestador:');
    for (const nome of SUBCOLECOES) {
      const total = await contar(providerRef.collection(nome));
      console.log(`   ${nome}: ${total}`);
    }
  }

  if (SO_VITRINE) {
    console.log('\nvou apenas gravar visible = false na listagem. Nada é apagado.');
    if (!GRAVAR) {
      console.log('nada foi gravado. rode de novo com --gravar.');
      return;
    }
    if (!listingSnap.exists) {
      console.log('não há listagem pra esconder.');
      return;
    }
    await listingRef.update({ visible: false });
    console.log('pronto. o perfil não aparece mais na busca, e a conta continua prestador.');
    return;
  }

  console.log('\nVOU APAGAR, SEM DESFAZER:');
  console.log(`   providerDirectory/${uid} (com as avaliações recebidas)`);
  console.log(`   providers/${uid} (com orçamentos, serviços, clientes e compromissos)`);
  console.log('\nA conta em si NÃO é apagada: login, dados de cliente, favoritos e');
  console.log('os orçamentos que ela pediu como CLIENTE continuam intactos.');

  if (!GRAVAR) {
    console.log('\nnada foi gravado. rode de novo com --gravar.');
    return;
  }

  if (listingSnap.exists) {
    await db.recursiveDelete(listingRef);
    console.log('listagem removida da vitrine.');
  }
  if (providerSnap.exists) {
    await db.recursiveDelete(providerRef);
    console.log('dados de prestador removidos.');
  }

  console.log('\npronto. a conta voltou a ser só cliente.');
  console.log('No app, saia e entre de novo: o `isProvider` fica em cache na sessão');
  console.log('(ver AuthController.bootstrap) e só é relido ao entrar.');
}

main().catch((e) => {
  console.error('\nfalhou:', e);
  process.exit(1);
});
