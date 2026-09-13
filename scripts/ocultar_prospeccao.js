#!/usr/bin/env node
/**
 * Tira da busca as entradas de curadoria (não reivindicadas) do
 * `providerDirectory`, mantendo as exceções que você indicar.
 *
 *   node scripts/ocultar_prospeccao.js <chave.json> --manter wesley
 *   node scripts/ocultar_prospeccao.js <chave.json> --manter wesley --gravar
 *   node scripts/ocultar_prospeccao.js <chave.json> --reverter --gravar
 *
 * POR QUÊ (decisão do Franck, 13/09): o diretório tem ~9.700 entradas
 * raspadas, e nenhuma delas usa o app. Na prática, todo pedido de
 * orçamento feito pra uma delas morre: o cliente escreve o pedido e
 * recebe "esse profissional ainda não usa o PrestadorAki, copie a
 * mensagem e mande você mesmo". Trabalho perdido, primeira impressão
 * queimada — e num mercado do tamanho de Criciúma isso circula.
 *
 * A escolha foi inverter a ordem: convidar primeiro (ver
 * prospeccao_criciuma.csv e modelo_mensagem_convite.md) e publicar o
 * perfil quando a pessoa aceitar. Assim toda busca devolve gente que
 * responde.
 *
 * SEGURANÇA: só mexe em quem tem `claimed != true`, ou seja, nas
 * entradas de curadoria. Prestador de verdade, que criou conta e assumiu
 * o perfil, nunca é tocado por este script — nem que o nome dele case
 * com algum termo de `--manter`.
 *
 * REVERSÍVEL: `--reverter` devolve `visible: true` pras mesmas entradas.
 * Nada é apagado; só o campo `visible` muda.
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
const REVERTER = process.argv.includes('--reverter');
const LOTE = 400;
 
function normalizar(v) {
  return String(v || '')
    .toLowerCase()
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '');
}
 
/** Tudo que vier depois de cada `--manter`, até o próximo argumento com `--`. */
function termosParaManter(argv) {
  const termos = [];
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--manter' && argv[i + 1] && !argv[i + 1].startsWith('--')) {
      termos.push(normalizar(argv[i + 1]));
    }
  }
  return termos;
}
 
async function main() {
  const chave = process.argv[2];
  if (!chave || chave.startsWith('--')) {
    console.error('uso: node scripts/ocultar_prospeccao.js <chave.json> [--manter termo] [--gravar] [--reverter]');
    process.exit(1);
  }
  if (!fs.existsSync(chave)) {
    console.error(`não achei a chave em ${chave}`);
    process.exit(1);
  }
  const manter = termosParaManter(process.argv);
 
  admin.initializeApp({ credential: admin.credential.cert(require(path.resolve(chave))) });
  const db = admin.firestore();
 
  console.log(REVERTER ? '>>> REVERTENDO (voltar a mostrar) <<<' : '>>> ocultando a curadoria <<<');
  console.log(GRAVAR ? '>>> MODO GRAVAÇÃO <<<' : '>>> simulação (nada será gravado) <<<');
  if (manter.length) console.log(`mantendo visível quem casar com: ${manter.join(', ')}`);
  console.log('');
 
  const snap = await db.collection('providerDirectory').get();
 
  const reivindicados = [];
  const mantidos = [];
  const alvos = [];
 
  for (const doc of snap.docs) {
    const d = doc.data();
    if (d.claimed === true) {
      reivindicados.push(doc);
      continue;
    }
    const nome = normalizar(d.name);
    if (manter.some((t) => nome.includes(t) || doc.id.includes(t))) {
      mantidos.push(doc);
      continue;
    }
    // Já está no estado desejado? Não precisa escrever de novo.
    const jaOculto = d.visible === false;
    if (REVERTER ? !jaOculto : jaOculto) continue;
    alvos.push(doc);
  }
 
  console.log(`total no diretório:            ${snap.size}`);
  console.log(`prestadores de verdade (claimed, intocados): ${reivindicados.length}`);
  reivindicados.slice(0, 10).forEach((d) => console.log(`   • ${d.data().name} [${d.id}]`));
  console.log(`mantidos por --manter:         ${mantidos.length}`);
  mantidos.forEach((d) =>
    console.log(`   ✓ ${d.data().name} — ${d.data().city ?? '?'} [${d.id}]`),
  );
  console.log(`serão ${REVERTER ? 'exibidos' : 'ocultados'}:          ${alvos.length}`);
 
  if (manter.length && mantidos.length === 0) {
    console.log('\nATENÇÃO: nenhum nome casou com o que você pediu pra manter.');
    console.log('Confira a grafia antes de gravar — senão o Wesley some junto.');
  }
 
  if (!GRAVAR) {
    console.log('\nnada foi gravado. rode de novo com --gravar.');
    return;
  }
  if (alvos.length === 0) {
    console.log('nada a fazer.');
    return;
  }
 
  let feitos = 0;
  for (let i = 0; i < alvos.length; i += LOTE) {
    const batch = db.batch();
    for (const doc of alvos.slice(i, i + LOTE)) {
      batch.update(doc.ref, { visible: REVERTER });
      feitos++;
    }
    await batch.commit();
    process.stdout.write(`\r  ${feitos}/${alvos.length}`);
  }
  console.log(`\npronto: ${feitos} entrada(s) com visible = ${REVERTER}.`);
}
 
main().catch((e) => {
  console.error('\nfalhou:', e);
  process.exit(1);
});