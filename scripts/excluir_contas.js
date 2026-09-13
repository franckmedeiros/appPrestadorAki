#!/usr/bin/env node
/**
 * Exclusão administrativa de contas — a mesma limpeza que a Cloud
 * Function `excluirContaEDados` faz quando a PESSOA pede a exclusão pelo
 * app (ver functions/src/account.ts), só que aqui partindo do e-mail, sem
 * precisar da senha nem do aparelho dela. Serve pra faxina de contas de
 * teste.
 *
 *   node scripts/excluir_contas.js <chave.json> teste@x.com outra@y.com
 *   node scripts/excluir_contas.js <chave.json> teste@x.com --gravar
 *
 * Sem `--gravar` ele só CONTA o que seria apagado, sem escrever nada.
 * Rode assim primeiro, sempre: exclusão de conta não tem desfazer, e o
 * relatório da simulação é a sua última chance de perceber que digitou o
 * e-mail errado.
 *
 * CREDENCIAL: o caminho da chave de conta de serviço vem como primeiro
 * argumento, igual aos outros scripts desta pasta.
 *
 * O QUE APAGA, por conta:
 *   - providers/{uid} inteiro (clientes, agenda, orçamentos com as
 *     conversas e aditivos, serviços, visitas técnicas, equipe...)
 *   - clients/{uid} inteiro (perfil, notificações, favoritos)
 *   - providerDirectory/{uid} (o perfil público na busca) e as avaliações
 *     que essa pessoa recebeu
 *   - os orçamentos que ela pediu, como CLIENTE, dentro de OUTROS
 *     prestadores — com as subcoleções deles (conversa e aditivos)
 *   - a reserva de telefone em phoneIndex
 *   - as avaliações que ela DEU em outros prestadores, recalculando a
 *     média de estrelas de quem foi avaliado
 *   - a conta no Firebase Auth (é isso que libera o e-mail pra um
 *     cadastro novo)
 *
 * A diferença pra Cloud Function está no penúltimo item. Lá as
 * avaliações dadas ficam de propósito (o comentário no account.ts explica
 * que varrer o diretório inteiro só pra isso não valia a pena numa
 * chamada do app). Aqui vale: este script existe justamente pra apagar
 * contas de TESTE, e uma nota de teste esquecida continuaria puxando pra
 * cima ou pra baixo a média de um prestador de verdade — pior, uma média
 * que ninguém mais consegue explicar de onde veio.
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

async function apagarSubarvore(db, ref, gravar) {
  if (gravar) await db.recursiveDelete(ref);
}

async function main() {
  const [, , chave, ...resto] = process.argv;
  const emails = resto.filter((a) => !a.startsWith('--'));

  if (!chave || chave.startsWith('--') || emails.length === 0) {
    console.error('uso: node scripts/excluir_contas.js <chave.json> <email> [email...] [--gravar]');
    process.exit(1);
  }
  if (!fs.existsSync(chave)) {
    console.error(`não achei a chave em ${chave}`);
    process.exit(1);
  }

  admin.initializeApp({ credential: admin.credential.cert(require(path.resolve(chave))) });
  const db = admin.firestore();
  const auth = admin.auth();

  console.log(GRAVAR ? '>>> MODO GRAVAÇÃO — ISTO NÃO TEM DESFAZER <<<' : '>>> simulação <<<');
  console.log(`${emails.length} conta(s): ${emails.join(', ')}\n`);

  for (const email of emails) {
    console.log(`── ${email}`);

    let uid = null;
    let displayName = '';
    try {
      const user = await auth.getUserByEmail(email);
      uid = user.uid;
      displayName = user.displayName || '(sem nome)';
    } catch (e) {
      if (e.code === 'auth/user-not-found') {
        console.log('   não existe no Firebase Auth — pulando.\n');
        continue;
      }
      throw e;
    }
    console.log(`   uid: ${uid}  nome: ${displayName}`);

    // ---- o que existe hoje (a simulação vive deste levantamento) ----
    const provider = await db.collection('providers').doc(uid).get();
    const client = await db.collection('clients').doc(uid).get();
    const listagem = await db.collection('providerDirectory').doc(uid).get();
    const orcamentosComoCliente = await db
      .collectionGroup('budgets')
      .where('clientUid', '==', uid)
      .get();
    const telefones = await db.collection('phoneIndex').where('clientUid', '==', uid).get();

    // Avaliações que esta conta DEU: o id do documento é o uid de quem
    // avaliou (ver ProviderDirectoryRepository.rate), e não existe campo
    // nenhum com esse uid dentro — então não dá pra filtrar no servidor.
    // Varre o grupo `ratings` inteiro e compara o id aqui. São poucos
    // documentos (uma avaliação por cliente por prestador); se um dia
    // isso crescer muito, vira um campo `clientUid` no documento.
    const todasAvaliacoes = await db.collectionGroup('ratings').get();
    const avaliacoesDadas = todasAvaliacoes.docs.filter(
      // O teste de caminho é cinto de segurança: hoje só
      // `providerDirectory` tem subcoleção `ratings`, mas um
      // `collectionGroup` casa QUALQUER coleção com esse nome, e no dia
      // em que aparecer outra este script sairia recalculando média em
      // documento que não tem média nenhuma.
      (d) => d.id === uid && d.ref.path.startsWith('providerDirectory/'),
    );

    console.log(`   providers/${uid}:        ${provider.exists ? 'existe' : '—'}`);
    console.log(`   clients/${uid}:          ${client.exists ? 'existe' : '—'}`);
    console.log(`   providerDirectory/${uid}: ${listagem.exists ? 'existe' : '—'}`);
    console.log(`   orçamentos em outros prestadores: ${orcamentosComoCliente.size}`);
    console.log(`   reservas de telefone:            ${telefones.size}`);
    console.log(`   avaliações dadas a terceiros:    ${avaliacoesDadas.length}`);

    if (!GRAVAR) {
      console.log('');
      continue;
    }

    // ---- exclusão, na mesma ordem da Cloud Function: Firestore antes,
    // Auth por último, pra não sobrar dado órfão de um uid que ainda
    // existe caso algo falhe no meio ----
    await apagarSubarvore(db, db.collection('providers').doc(uid), true);
    await apagarSubarvore(db, db.collection('clients').doc(uid), true);
    await apagarSubarvore(db, db.collection('providerDirectory').doc(uid), true);

    // `recursiveDelete` e não `batch.delete`: apagar um documento no
    // Firestore NÃO apaga as subcoleções dele, e estes orçamentos têm a
    // conversa (`mensagens`) e os aditivos (`versions`) pendurados.
    for (const doc of orcamentosComoCliente.docs) {
      await db.recursiveDelete(doc.ref);
    }

    for (const doc of telefones.docs) {
      await doc.ref.delete();
    }

    // Avaliações dadas: apaga e RECALCULA a média do prestador avaliado.
    // Só apagar deixaria `ratingAverage`/`ratingCount` mentindo pra
    // sempre — o app não recalcula sozinho, quem mantém esses números é
    // a transação de `rate()`, que só roda quando alguém avalia.
    const listagensAfetadas = new Set();
    for (const doc of avaliacoesDadas) {
      listagensAfetadas.add(doc.ref.parent.parent.path);
      await doc.ref.delete();
    }
    for (const caminho of listagensAfetadas) {
      const listagemRef = db.doc(caminho);
      const restantes = await listagemRef.collection('ratings').get();
      const soma = restantes.docs.reduce((t, d) => t + (Number(d.data().stars) || 0), 0);
      const quantidade = restantes.size;
      const media = quantidade === 0 ? 0 : Number((soma / quantidade).toFixed(2));
      await listagemRef.update({ ratingAverage: media, ratingCount: quantidade });
      console.log(`   média recalculada em ${caminho}: ${media} (${quantidade} avaliações)`);
    }

    await auth.deleteUser(uid);
    console.log('   conta removida do Firebase Auth.\n');
  }

  console.log(
    GRAVAR
      ? 'Concluído.'
      : '\nNada foi gravado. Confira a lista acima e rode de novo com --gravar.',
  );
}

main().catch((e) => {
  console.error('\nfalhou:', e);
  process.exit(1);
});
