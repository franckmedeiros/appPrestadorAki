#!/usr/bin/env node
/**
 * Fila de moderação: lista as denúncias abertas e permite agir sobre elas.
 *
 *   node scripts/moderar_denuncias.js <chave.json>
 *   node scripts/moderar_denuncias.js <chave.json> --remover <idDaDenuncia> --gravar
 *   node scripts/moderar_denuncias.js <chave.json> --manter  <idDaDenuncia> --gravar
 *   node scripts/moderar_denuncias.js <chave.json> --remover <id> --desativar-autor --gravar
 *   node scripts/moderar_denuncias.js <chave.json> --resolvidas
 *
 * POR QUE EXISTE: a Apple (App Store Review Guideline 1.2) exige que um app
 * com conteúdo escrito por usuários tenha como DENUNCIAR, como BLOQUEAR
 * quem publicou, e um processo de REMOÇÃO em até 24 horas. O app cobre as
 * duas primeiras (ver lib/features/moderation/); esta é a terceira — a
 * parte que é sua, não do app.
 *
 * A coleção `reports` é fechada no firestore.rules: o app só cria, ninguém
 * lê. Este script usa o Admin SDK, que ignora as regras — é justamente por
 * isso que ele roda na sua máquina, com a chave, e não dentro do app.
 *
 * O QUE `--remover` FAZ: apaga a avaliação denunciada e RECALCULA a média
 * do prestador. Isso não é detalhe: a média e a contagem ficam gravadas no
 * documento do diretório (ver ProviderDirectoryRepository.rate), então
 * apagar a avaliação sem recalcular deixaria o prestador com uma nota que
 * não corresponde a avaliação nenhuma — e ninguém descobriria tão cedo.
 *
 * `--desativar-autor` desativa a conta de quem escreveu, no Firebase Auth.
 * A pessoa deixa de conseguir entrar. É reversível pelo Console, mas é a
 * ação mais pesada aqui — por isso precisa ser pedida explicitamente, nunca
 * vem junto com a remoção.
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
const DESATIVAR_AUTOR = process.argv.includes('--desativar-autor');
const VER_RESOLVIDAS = process.argv.includes('--resolvidas');

const MOTIVOS = {
  ofensivo: 'Ofensivo ou discurso de ódio',
  spam: 'Spam ou propaganda',
  falso: 'Informação falsa sobre o serviço',
  dados_pessoais: 'Expõe dados pessoais',
  outro: 'Outro motivo',
};

function valorDaOpcao(nome) {
  const i = process.argv.indexOf(nome);
  if (i === -1) return null;
  const proximo = process.argv[i + 1];
  return !proximo || proximo.startsWith('--') ? '' : proximo;
}

function horas(data) {
  if (!data) return '?';
  const h = Math.floor((Date.now() - data.getTime()) / 3600000);
  return h < 1 ? 'menos de 1h' : `${h}h`;
}

async function listar(db) {
  const status = VER_RESOLVIDAS ? ['removida', 'mantida'] : ['aberta'];
  const snap = await db
    .collection('reports')
    .where('status', 'in', status)
    .orderBy('createdAt', 'asc')
    .get();

  console.log(VER_RESOLVIDAS ? '>>> denúncias já resolvidas <<<' : '>>> denúncias abertas <<<');
  console.log(`total: ${snap.size}\n`);

  if (snap.empty) {
    console.log(VER_RESOLVIDAS ? 'nenhuma.' : 'nada na fila. tudo tratado.');
    return;
  }

  for (const doc of snap.docs) {
    const d = doc.data();
    const criada = d.createdAt?.toDate?.();
    const idade = horas(criada);
    // O prazo da Apple é 24h. Marcar o que já passou disso é o ponto todo
    // de olhar esta lista.
    const atraso = !VER_RESOLVIDAS && criada && Date.now() - criada.getTime() > 24 * 3600000;

    console.log(`${atraso ? '!!' : '  '} ${doc.id}   (há ${idade})`);
    console.log(`     motivo:    ${MOTIVOS[d.motivo] || d.motivo}`);
    if (d.detalhe) console.log(`     detalhe:   ${d.detalhe}`);
    console.log(`     conteúdo:  ${d.conteudo ? `"${d.conteudo}"` : '(a avaliação não tinha comentário)'}`);
    console.log(`     autor:     ${d.autorUid}`);
    console.log(`     prestador: ${d.listingId}`);
    if (VER_RESOLVIDAS) console.log(`     decisão:   ${d.status}`);
    console.log('');
  }

  if (!VER_RESOLVIDAS) {
    const atrasadas = snap.docs.filter((doc) => {
      const c = doc.data().createdAt?.toDate?.();
      return c && Date.now() - c.getTime() > 24 * 3600000;
    }).length;
    if (atrasadas > 0) {
      console.log(`ATENÇÃO: ${atrasadas} denúncia(s) passaram das 24 horas (marcadas com !!).`);
      console.log('');
    }
    console.log('Para decidir:');
    console.log('  node scripts/moderar_denuncias.js <chave.json> --remover <id> --gravar');
    console.log('  node scripts/moderar_denuncias.js <chave.json> --manter  <id> --gravar');
  }
}

/**
 * Apaga a avaliação e refaz média/contagem numa transação, pra duas
 * remoções ao mesmo tempo não se atropelarem.
 */
async function removerAvaliacao(db, listingId, autorUid) {
  const listingRef = db.collection('providerDirectory').doc(listingId);
  const ratingRef = listingRef.collection('ratings').doc(autorUid);

  return db.runTransaction(async (tx) => {
    const ratingSnap = await tx.get(ratingRef);
    if (!ratingSnap.exists) return { removida: false };

    const listingSnap = await tx.get(listingRef);
    const mediaAtual = Number(listingSnap.get('ratingAverage') || 0);
    const totalAtual = Number(listingSnap.get('ratingCount') || 0);
    const estrelasRemovidas = Number(ratingSnap.get('stars') || 0);

    const novoTotal = Math.max(0, totalAtual - 1);
    const somaAtual = mediaAtual * totalAtual;
    const novaMedia = novoTotal === 0 ? 0 : (somaAtual - estrelasRemovidas) / novoTotal;

    tx.delete(ratingRef);
    tx.update(listingRef, {
      ratingCount: novoTotal,
      ratingAverage: Number(novaMedia.toFixed(2)),
    });
    return { removida: true, novoTotal, novaMedia: Number(novaMedia.toFixed(2)) };
  });
}

async function decidir(db, reportId, remover) {
  const ref = db.collection('reports').doc(reportId);
  const snap = await ref.get();
  if (!snap.exists) {
    console.error(`não achei a denúncia ${reportId}.`);
    process.exit(1);
  }
  const d = snap.data();

  console.log(`denúncia:  ${reportId}`);
  console.log(`motivo:    ${MOTIVOS[d.motivo] || d.motivo}`);
  console.log(`conteúdo:  ${d.conteudo ? `"${d.conteudo}"` : '(sem comentário)'}`);
  console.log(`autor:     ${d.autorUid}`);
  console.log(`decisão:   ${remover ? 'REMOVER a avaliação' : 'MANTER a avaliação'}`);
  if (DESATIVAR_AUTOR) console.log('           + DESATIVAR a conta do autor');
  console.log('');

  if (!GRAVAR) {
    console.log('nada foi gravado. rode de novo com --gravar.');
    return;
  }

  if (remover) {
    const r = await removerAvaliacao(db, d.listingId, d.autorUid);
    if (r.removida) {
      console.log(`avaliação removida. prestador agora com ${r.novoTotal} avaliação(ões), média ${r.novaMedia}.`);
    } else {
      console.log('a avaliação já não existia mais — só a denúncia foi encerrada.');
    }
  }

  if (DESATIVAR_AUTOR) {
    try {
      await admin.auth().updateUser(d.autorUid, { disabled: true });
      console.log('conta do autor desativada (reversível pelo Console do Firebase).');
    } catch (e) {
      console.error('não consegui desativar a conta do autor:', e.message);
    }
  }

  await ref.update({
    status: remover ? 'removida' : 'mantida',
    resolvidaEm: admin.firestore.FieldValue.serverTimestamp(),
    autorDesativado: DESATIVAR_AUTOR,
  });
  console.log('denúncia encerrada.');
}

async function main() {
  const chave = process.argv[2];
  if (!chave || chave.startsWith('--')) {
    console.error('uso: node scripts/moderar_denuncias.js <chave.json> [--remover|--manter <id>] [--desativar-autor] [--gravar] [--resolvidas]');
    process.exit(1);
  }
  if (!fs.existsSync(chave)) {
    console.error(`não achei a chave em ${chave}`);
    process.exit(1);
  }

  admin.initializeApp({ credential: admin.credential.cert(require(path.resolve(chave))) });
  const db = admin.firestore();

  const remover = valorDaOpcao('--remover');
  const manter = valorDaOpcao('--manter');

  if (remover === '' || manter === '') {
    console.error('--remover e --manter precisam do id da denúncia depois.');
    process.exit(1);
  }
  if (remover && manter) {
    console.error('escolha um dos dois: --remover ou --manter.');
    process.exit(1);
  }

  if (remover) return decidir(db, remover, true);
  if (manter) return decidir(db, manter, false);
  return listar(db);
}

main().catch((e) => {
  console.error('\nfalhou:', e);
  process.exit(1);
});
