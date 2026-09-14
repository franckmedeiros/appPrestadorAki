#!/usr/bin/env node
/**
 * Diagnóstico e demonstração do selo "Responde rápido".
 *
 *   node scripts/responde_rapido.js <chave.json>
 *   node scripts/responde_rapido.js <chave.json> --demo wesley
 *   node scripts/responde_rapido.js <chave.json> --demo wesley --gravar
 *   node scripts/responde_rapido.js <chave.json> --limpar wesley --gravar
 *
 * O SELO hoje é benefício de assinatura: aparece pra todo prestador com
 * conta e assinatura ativa (ver ProviderListing.respondeRapido). Este
 * script mostra quem está nessa condição e, portanto, quem deve estar
 * com o selo aceso no app.
 *
 * O TEMPO DE RESPOSTA continua sendo medido de verdade por trás (ver
 * functions/src/directory.ts, `registrarTempoDeResposta`): a diferença
 * entre a hora em que o cliente pediu o orçamento e a hora em que o
 * prestador respondeu. Ninguém olha pra esse número na tela hoje, mas
 * ele é listado aqui — serve pra você saber quem realmente responde
 * rápido, e pra o dia em que o selo voltar a depender disso já existir
 * histórico.
 *
 * `--demo` grava um tempo de resposta de mentira (3 respostas, média de
 * 25 min) num prestador. Como o selo não depende mais disso, serve só
 * pra testar a parte medida; pra ver o selo, basta uma assinatura ativa.
 * Some com `--limpar`.
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

// Referência de "rápido" só pra leitura desta lista — NÃO é o que
// decide o selo hoje (quem decide é a assinatura, ver
// ProviderListing.respondeRapido). Serve pra você bater o olho e ver
// quem está de fato respondendo bem.
const MEDIA_DE_REFERENCIA_MINUTOS = 120;

// Valores da demonstração: 3 respostas somando 75 min (média de 25).
const DEMO_RESPOSTAS = 3;
const DEMO_MINUTOS = 75;

function normalizar(v) {
  return String(v || '')
    .toLowerCase()
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '');
}

function valorDaOpcao(argv, nome) {
  const i = argv.indexOf(nome);
  if (i === -1) return null;
  const proximo = argv[i + 1];
  if (!proximo || proximo.startsWith('--')) return '';
  return normalizar(proximo);
}

/** Se este prestador tem o selo hoje — e, se não tem, por quê. */
function diagnostico(d) {
  const claimed = d.claimed === true;
  const assinante = claimed && d.visible !== false;
  const contadas = Number(d.respostasContadas || 0);
  const soma = Number(d.respostaMinutosSoma || 0);
  const media = contadas === 0 ? null : soma / contadas;

  let falta;
  if (!claimed) falta = 'não é conta de verdade (entrada de curadoria)';
  else if (!assinante) falta = 'assinatura inativa (visible = false)';
  else falta = null;

  return { assinante, contadas, media, falta };
}

async function main() {
  const chave = process.argv[2];
  if (!chave || chave.startsWith('--')) {
    console.error('uso: node scripts/responde_rapido.js <chave.json> [--demo termo] [--limpar termo] [--gravar]');
    process.exit(1);
  }
  if (!fs.existsSync(chave)) {
    console.error(`não achei a chave em ${chave}`);
    process.exit(1);
  }

  const demo = valorDaOpcao(process.argv, '--demo');
  const limpar = valorDaOpcao(process.argv, '--limpar');
  if (demo === '' || limpar === '') {
    console.error('--demo e --limpar precisam de um termo depois (ex.: --demo wesley).');
    process.exit(1);
  }

  admin.initializeApp({ credential: admin.credential.cert(require(path.resolve(chave))) });
  const db = admin.firestore();

  // Só os prestadores de verdade. As ~9.700 entradas de curadoria não
  // podem ter o selo de qualquer jeito (não são assinantes), e listar
  // todas só encheria a tela.
  const snap = await db.collection('providerDirectory').where('claimed', '==', true).get();

  console.log(`prestadores com conta: ${snap.size}\n`);

  const alvos = [];

  for (const doc of snap.docs) {
    const d = doc.data();
    const { contadas, media, falta } = diagnostico(d);
    const marca = falta === null ? '★' : ' ';
    const mediaTexto =
      media === null
        ? 'ainda sem resposta medida'
        : `${Math.round(media)} min${media <= MEDIA_DE_REFERENCIA_MINUTOS ? '' : ' (acima das 2h)'}`;
    console.log(`${marca} ${d.name || '(sem nome)'} [${doc.id}]`);
    console.log(`    selo "Responde rápido": ${falta === null ? 'SIM' : `não — ${falta}`}`);
    console.log(`    tempo real de resposta: ${contadas} resposta(s), média ${mediaTexto}`);

    const termo = demo || limpar;
    if (termo && (normalizar(d.name).includes(termo) || doc.id.includes(termo))) {
      alvos.push(doc);
    }
  }

  if (!demo && !limpar) {
    console.log('\nO selo depende só da assinatura: quem está com SIM acima deve');
    console.log('aparecer com ele na busca. A média serve de informação sua.');
    return;
  }

  console.log('');
  if (alvos.length === 0) {
    console.log(`nenhum prestador casou com "${demo || limpar}". confira a grafia.`);
    return;
  }

  const acao = demo ? 'gravar números de demonstração' : 'apagar os números';
  console.log(`vou ${acao} em ${alvos.length} prestador(es):`);
  alvos.forEach((d) => console.log(`   • ${d.data().name} [${d.id}]`));

  if (!GRAVAR) {
    console.log('\nnada foi gravado. rode de novo com --gravar.');
    return;
  }

  const batch = db.batch();
  for (const doc of alvos) {
    batch.update(
      doc.ref,
      demo
        ? { respostasContadas: DEMO_RESPOSTAS, respostaMinutosSoma: DEMO_MINUTOS }
        : {
            respostasContadas: admin.firestore.FieldValue.delete(),
            respostaMinutosSoma: admin.firestore.FieldValue.delete(),
          },
    );
  }
  await batch.commit();

  if (demo) {
    console.log(
      `\npronto. ${alvos.length} prestador(es) com ${DEMO_RESPOSTAS} respostas e média de ${DEMO_MINUTOS / DEMO_RESPOSTAS} min.`,
    );
    console.log('número inventado — rode --limpar quando terminar o teste.');
  } else {
    console.log(`\npronto. números apagados em ${alvos.length} prestador(es).`);
  }
}

main().catch((e) => {
  console.error('\nfalhou:', e);
  process.exit(1);
});
