#!/usr/bin/env node
/**
 * Por que um prestador não aparece na busca do cliente.
 *
 *   node scripts/diagnosticar_prestador.js <chave.json> email@dele.com
 *
 * Só lê, nunca escreve.
 *
 * A pergunta que ele responde: a busca do cliente
 * (ProviderDirectoryRepository.search) lê a coleção `providerDirectory`,
 * e SÓ ela. Ter `providers/{uid}` com `listingStatus: "active"` não
 * coloca ninguém na busca — são duas coisas separadas de propósito:
 * `providers` é o cadastro interno (agenda, clientes, orçamentos),
 * `providerDirectory` é a vitrine pública.
 *
 * Quem cria a vitrine é `ProviderDirectoryRepository.upsertOwnListing`,
 * chamada em UM lugar só: ao salvar "Editar perfil", e mesmo assim só
 * quando as três condições batem (ver EditProfileScreen._save):
 *   1. o salvamento do perfil deu certo;
 *   2. `auth.isProvider` está true NA MEMÓRIA DO APP naquele instante;
 *   3. `listingStatus` do documento lido é diferente de 'pending'.
 *
 * A condição 2 é a mais traiçoeira: `isProvider` é resolvido no login/
 * bootstrap e fica em cache (ver AuthController._checkIsProvider). Uma
 * conta que virou prestador com o app já aberto pode ter esse cache
 * desatualizado, e aí salvar o perfil grava tudo, não dá erro nenhum, e
 * simplesmente não publica a vitrine.
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
 
function mostrar(rotulo, valor) {
  console.log(`   ${rotulo.padEnd(18)} ${valor === undefined ? '(ausente)' : JSON.stringify(valor)}`);
}
 
async function main() {
  const [, , chave, email] = process.argv;
  if (!chave || !email) {
    console.error('uso: node scripts/diagnosticar_prestador.js <chave.json> <email>');
    process.exit(1);
  }
  if (!fs.existsSync(chave)) {
    console.error(`não achei a chave em ${chave}`);
    process.exit(1);
  }
 
  admin.initializeApp({ credential: admin.credential.cert(require(path.resolve(chave))) });
  const db = admin.firestore();
  const auth = admin.auth();
 
  const user = await auth.getUserByEmail(email).catch(() => null);
  if (!user) {
    console.log(`${email} não existe no Firebase Auth.`);
    return;
  }
  const uid = user.uid;
  console.log(`${email}\n   uid: ${uid}\n`);
 
  const prov = await db.collection('providers').doc(uid).get();
  console.log('providers/{uid} — cadastro interno');
  if (!prov.exists) {
    console.log('   NÃO EXISTE — esta conta não é prestadora.');
  } else {
    const d = prov.data();
    mostrar('name', d.name);
    mostrar('listingStatus', d.listingStatus);
    mostrar('category', d.category);
    mostrar('categories', d.categories);
    mostrar('city', d.city);
    mostrar('state', d.state);
  }
 
  const dir = await db.collection('providerDirectory').doc(uid).get();
  console.log('\nproviderDirectory/{uid} — a vitrine, é ESTA que a busca lê');
  if (!dir.exists) {
    console.log('   NÃO EXISTE');
  } else {
    const d = dir.data();
    mostrar('name', d.name);
    mostrar('category', d.category);
    mostrar('categories', d.categories);
    mostrar('city', d.city);
    mostrar('state', d.state);
    mostrar('visible', d.visible);
    mostrar('claimed', d.claimed);
    mostrar('phoneNormalized', d.phoneNormalized);
  }
 
  console.log('\n── veredito');
  if (!prov.exists) {
    console.log('   A conta não é prestadora. Use "Também quero oferecer serviços" no perfil.');
  } else if (!dir.exists) {
    console.log('   A vitrine nunca foi publicada — por isso a busca não acha.');
    console.log('   Entre no app COM ESSA CONTA, abra Editar perfil, confira categoria e');
    console.log('   cidade e salve. Se ainda assim não nascer, o `isProvider` em memória');
    console.log('   está desatualizado: saia da conta, entre de novo e salve outra vez.');
    if (prov.data().listingStatus === 'pending') {
      console.log('   ATENÇÃO: listingStatus está "pending" — salvar o perfil NÃO publica');
      console.log('   nesse estado (ver EditProfileScreen._save).');
    }
  } else if (dir.data().visible === false) {
    console.log('   A vitrine existe mas está com visible: false — a busca filtra ela fora.');
  } else if (!dir.data().name) {
    console.log('   A vitrine existe mas está sem `name` — a busca por nome nunca casa.');
  } else {
    console.log('   A vitrine está publicada e visível. Se a busca ainda não acha:');
    console.log('   1) a busca ESCONDE de você mesmo — se o app estiver logado nesta conta,');
    console.log('      ela nunca aparece (ProviderDirectoryRepository.search filtra o uid');
    console.log('      logado). Teste deslogado ou com outra conta.');
    console.log('   2) confira se o filtro de categoria/cidade da tela casa com os valores');
    console.log('      acima — "Selecione" e "Todas as cidades" não filtram nada.');
  }
 
  // Prévia do que a busca sem filtro nenhum devolveria — é literalmente o
  // que o app baixa antes de aplicar o filtro de nome.
  const todos = await db.collection('providerDirectory').get();
  const visiveis = todos.docs.filter((d) => d.data().visible !== false);
  console.log(`\nproviderDirectory tem ${todos.size} documento(s), ${visiveis.length} visível(is).`);
  visiveis.slice(0, 15).forEach((d) => {
    const x = d.data();
    console.log(`   - ${String(x.name ?? '(sem nome)').padEnd(38)} ${x.city ?? '?'}/${x.state ?? '?'}  [${d.id}]`);
  });
  if (visiveis.length > 15) console.log(`   ... e mais ${visiveis.length - 15}`);
}
 
main().catch((e) => {
  console.error('\nfalhou:', e);
  process.exit(1);
});
 