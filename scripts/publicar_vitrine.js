#!/usr/bin/env node
/**
 * Publica a vitrine (`providerDirectory/{uid}`) de um prestador que já
 * tem o cadastro interno (`providers/{uid}`) mas nunca apareceu na busca.
 *
 *   node scripts/publicar_vitrine.js <chave.json> email@dele.com
 *   node scripts/publicar_vitrine.js <chave.json> email@dele.com --gravar
 *
 * Existe porque a publicação da vitrine, no app, depende de salvar
 * "Editar perfil" com o `isProvider` correto em memória — e esse valor
 * fica em cache desde o login (ver o comentário em
 * EditProfileScreen._save). Quando ele está velho, o perfil salva, não
 * dá erro nenhum e a vitrine não nasce. Isto aqui resolve o caso já
 * acontecido; o conserto do caminho normal está naquele arquivo.
 *
 * Escreve exatamente os mesmos campos que
 * `ProviderDirectoryRepository.upsertOwnListing` escreveria, lendo tudo
 * de `providers/{uid}` — id do documento é o uid, `claimed: true`,
 * `providerUid` preenchido. Nada de inventar dado.
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

async function main() {
  const [, , chave, email] = process.argv;
  if (!chave || !email || email.startsWith('--')) {
    console.error('uso: node scripts/publicar_vitrine.js <chave.json> <email> [--gravar]');
    process.exit(1);
  }
  if (!fs.existsSync(chave)) {
    console.error(`não achei a chave em ${chave}`);
    process.exit(1);
  }

  admin.initializeApp({ credential: admin.credential.cert(require(path.resolve(chave))) });
  const db = admin.firestore();

  const user = await admin.auth().getUserByEmail(email).catch(() => null);
  if (!user) {
    console.error(`${email} não existe no Firebase Auth.`);
    process.exit(1);
  }
  const uid = user.uid;

  const provSnap = await db.collection('providers').doc(uid).get();
  if (!provSnap.exists) {
    console.error('essa conta não tem providers/{uid} — não é prestadora.');
    process.exit(1);
  }
  const p = provSnap.data();

  if (p.listingStatus === 'pending') {
    console.error('listingStatus está "pending" — a assinatura não está ativa. Abortando.');
    process.exit(1);
  }

  const categorias = Array.isArray(p.categories) && p.categories.length
    ? p.categories
    : (p.category ? [p.category] : []);
  if (categorias.length === 0 || !p.city) {
    console.error('faltam categoria e/ou cidade em providers/{uid} — sem isso não dá pra publicar.');
    process.exit(1);
  }

  const soDigitos = String(p.whatsapp ?? '').replace(/\D/g, '');
  const doc = {
    name: p.name ?? '',
    categories: categorias,
    // `category` singular continua gravado por compatibilidade, mesma
    // razão do upsertOwnListing.
    category: categorias[0],
    city: p.city,
    ...(p.state ? { state: p.state } : {}),
    ...(p.bio ? { bio: p.bio } : {}),
    ...(p.whatsapp ? { whatsapp: p.whatsapp, phoneNormalized: soDigitos } : {}),
    claimed: true,
    providerUid: uid,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  const dirRef = db.collection('providerDirectory').doc(uid);
  const jaExiste = (await dirRef.get()).exists;

  console.log(`${email}  uid: ${uid}`);
  console.log(jaExiste ? 'vitrine JÁ EXISTE — seria atualizada:' : 'vitrine NÃO existe — seria criada:');
  console.log(JSON.stringify({ ...doc, updatedAt: '(serverTimestamp)' }, null, 2));

  if (!GRAVAR) {
    console.log('\nnada foi gravado. rode de novo com --gravar.');
    return;
  }

  if (!jaExiste) doc.createdAt = admin.firestore.FieldValue.serverTimestamp();
  await dirRef.set(doc, { merge: true });
  console.log('\npublicado. A busca do cliente já deve encontrar.');
}

main().catch((e) => {
  console.error('\nfalhou:', e);
  process.exit(1);
});
