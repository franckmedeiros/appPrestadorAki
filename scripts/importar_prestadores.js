#!/usr/bin/env node
/**
 * Grava no `providerDirectory` os documentos gerados pelo
 * converter_prospeccao.js — a "carga inicial" de perfis não reivindicados
 * descrita em functions/src/subscription.ts.
 *
 * Sempre simula primeiro: sem `--gravar` ele lê o Firestore de verdade e
 * não escreve nada.
 *
 *   node scripts/importar_prestadores.js C:\caminho\chave.json
 *   node scripts/importar_prestadores.js C:\caminho\chave.json --gravar
 *
 * CREDENCIAL: igual ao seed_provider_directory.js desta pasta — o caminho
 * da chave de conta de serviço vem como primeiro argumento (Firebase
 * Console → Configurações do projeto → Contas de serviço → "Gerar nova
 * chave privada"). Guarde fora do controle de versão: dá acesso total ao
 * projeto.
 *
 * ================== COMO ELE EVITA DUPLICATA ==================
 *
 * O diretório já tem entradas de duas origens, com esquemas de id
 * DIFERENTES, e é aí que nasce a duplicata:
 *
 *   - seed_provider_directory.js  → id `nome-cidade` (sem telefone)
 *   - este script                 → id `imp_<telefone>`
 *
 * O mesmo prestador carregado pelos dois vira dois cards na busca. Pior:
 * o nome quase nunca bate letra por letra ("William Pizzetti" no seed
 * antigo, "Eletricista William Pizzetti" na prospecção), então comparar
 * id com id não resolve.
 *
 * Então, antes de escrever qualquer coisa, este script lê a coleção
 * INTEIRA e decide o destino de cada linha nesta ordem:
 *
 *   1. Já existe alguém com o MESMO `phoneNormalized`? É a mesma pessoa
 *      (telefone é o identificador confiável — é o que a Cloud Function
 *      usa pra reivindicar). Escreve por cima DAQUELE documento, com o id
 *      que ele já tem — preservando avaliações e qualquer coisa que já
 *      esteja lá.
 *   2. Existe um documento cujo id é exatamente o slug `nome-cidade`
 *      desta linha? É uma entrada do seeder antigo. Mesma coisa: escreve
 *      por cima dela, o que de quebra ADICIONA o telefone que faltava e
 *      torna aquela entrada reivindicável.
 *   3. Existe alguém com nome parecido na mesma cidade (um nome contido
 *      no outro)? NÃO decide sozinho — entra na lista de SUSPEITOS e é
 *      pulado. Fusão errada junta dois profissionais diferentes, o que é
 *      pior que a duplicata. Você confirma caso a caso no `fusoes.json`.
 *   4. Nada disso → documento novo, id `imp_<telefone>`.
 *
 * Para confirmar um suspeito, crie `scripts/fusoes.json` com um objeto
 * "telefone da linha nova": "id do documento que já existe":
 *
 *   { "48999361869": "william-pizzetti-criciuma" }
 *
 * E entradas já reivindicadas (`claimed: true` — o prestador criou conta
 * e assumiu o perfil) são SEMPRE puladas: reimportar não pode
 * sobrescrever com dados da prospecção o que a pessoa escreveu.
 */
const fs = require('fs');
const path = require('path');

// `scripts/package.json` já declara firebase-admin (o mesmo que o
// seed_provider_directory.js usa) — basta `npm install` uma vez.
let admin;
try {
  admin = require('firebase-admin');
} catch (e) {
  console.error('firebase-admin não encontrado. Rode `npm install` dentro de scripts/ primeiro.');
  process.exit(1);
}

const GRAVAR = process.argv.includes('--gravar');
const COLECAO = 'providerDirectory';
const LOTE = 400; // o limite do Firestore é 500 operações por batch

/** Mesma normalização de acento/pontuação usada pra comparar nomes. */
function normalizarNome(s) {
  return String(s || '')
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
}

/** Id do seeder antigo — copiado de seed_provider_directory.js:slugId. */
function slugId(name, city) {
  return `${name}-${city}`
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/(^-|-$)/g, '');
}

async function main() {
  const chave = process.argv[2];
  if (!chave || chave.startsWith('--')) {
    console.error('uso: node scripts/importar_prestadores.js <chave-conta-servico.json> [--gravar]');
    process.exit(1);
  }
  if (!fs.existsSync(chave)) {
    console.error(`não achei a chave em ${chave}`);
    process.exit(1);
  }

  const arquivo = path.resolve(__dirname, 'prestadores_para_importar.json');
  if (!fs.existsSync(arquivo)) {
    console.error(`não achei ${arquivo} — rode o converter_prospeccao.js antes.`);
    process.exit(1);
  }
  const docs = JSON.parse(fs.readFileSync(arquivo, 'utf8'));

  const arquivoFusoes = path.resolve(__dirname, 'fusoes.json');
  const fusoes = fs.existsSync(arquivoFusoes)
    ? JSON.parse(fs.readFileSync(arquivoFusoes, 'utf8'))
    : {};

  admin.initializeApp({ credential: admin.credential.cert(require(path.resolve(chave))) });
  const db = admin.firestore();

  console.log(`${docs.length} linhas no arquivo.`);
  console.log(GRAVAR ? '>>> MODO GRAVAÇÃO <<<' : '>>> simulação (nada será gravado) <<<');

  // Lê a coleção inteira uma vez — é ela que permite decidir "já existe?"
  // por telefone e por nome, não só por id.
  console.log(`lendo ${COLECAO} pra comparar...`);
  const atuais = await db.collection(COLECAO).get();
  const porId = new Map();
  const porTelefone = new Map();
  const porNomeCidade = [];
  atuais.forEach((snap) => {
    const d = snap.data();
    porId.set(snap.id, d);
    if (d.phoneNormalized) porTelefone.set(String(d.phoneNormalized), snap.id);
    porNomeCidade.push({ id: snap.id, nome: normalizarNome(d.name), cidade: normalizarNome(d.city) });
  });
  console.log(`   ${atuais.size} documentos já existem na coleção.`);

  const novos = [];
  const sobrescrever = []; // { doc, idDestino, motivo }
  const suspeitos = [];
  const pulados = [];

  for (const doc of docs) {
    // 0) Fusão confirmada manualmente.
    const fusao = fusoes[doc.phoneNormalized];
    if (fusao) {
      if (!porId.has(fusao)) {
        suspeitos.push(`${doc.name}: fusoes.json aponta pra "${fusao}", que não existe na coleção`);
        continue;
      }
      if (porId.get(fusao).claimed === true) {
        pulados.push(`${doc.name} (destino ${fusao} já reivindicado)`);
        continue;
      }
      sobrescrever.push({ doc, idDestino: fusao, motivo: 'fusão confirmada no fusoes.json' });
      continue;
    }

    // 1) Mesmo telefone: é a mesma pessoa, sem dúvida.
    const porTel = porTelefone.get(doc.phoneNormalized);
    if (porTel) {
      if (porId.get(porTel).claimed === true) {
        pulados.push(`${doc.name} (${porTel} já reivindicado)`);
        continue;
      }
      sobrescrever.push({ doc, idDestino: porTel, motivo: 'mesmo telefone' });
      continue;
    }

    // 2) Id no formato do seeder antigo.
    const slug = slugId(doc.name, doc.city);
    if (porId.has(slug)) {
      if (porId.get(slug).claimed === true) {
        pulados.push(`${doc.name} (${slug} já reivindicado)`);
        continue;
      }
      sobrescrever.push({ doc, idDestino: slug, motivo: 'entrada antiga com mesmo nome+cidade' });
      continue;
    }

    // 3) Nome parecido na mesma cidade — decisão humana.
    const nome = normalizarNome(doc.name);
    const cidade = normalizarNome(doc.city);
    const parecido = porNomeCidade.find(
      (e) =>
        e.cidade === cidade &&
        e.nome.length > 4 &&
        nome.length > 4 &&
        (e.nome.includes(nome) || nome.includes(e.nome)),
    );
    if (parecido) {
      suspeitos.push(
        `"${doc.name}" (tel ${doc.phoneNormalized}) parece ser "${porId.get(parecido.id).name}" (id ${parecido.id})`,
      );
      continue;
    }

    // 4) Novo de verdade.
    if (porId.has(doc.id)) {
      // Já importado numa rodada anterior deste mesmo script.
      if (porId.get(doc.id).claimed === true) {
        pulados.push(`${doc.name} (${doc.id} já reivindicado)`);
        continue;
      }
      sobrescrever.push({ doc, idDestino: doc.id, motivo: 'reimportação da mesma entrada' });
    } else {
      novos.push(doc);
    }
  }

  console.log('');
  console.log(`   novos:                        ${novos.length}`);
  console.log(`   atualizam entrada existente:  ${sobrescrever.length}`);
  console.log(`   pulados (já reivindicados):   ${pulados.length}`);
  console.log(`   SUSPEITOS (não importados):   ${suspeitos.length}`);
  pulados.slice(0, 10).forEach((p) => console.log(`      - ${p}`));
  if (suspeitos.length) {
    console.log('\n   precisam da sua decisão (crie scripts/fusoes.json):');
    suspeitos.forEach((s) => console.log(`      - ${s}`));
  }

  if (!GRAVAR) {
    console.log('\nexemplo do que seria gravado:');
    console.log(JSON.stringify(novos[0] || sobrescrever[0]?.doc, null, 2));
    console.log('\nnada foi gravado. rode de novo com --gravar pra valer.');
    return;
  }

  const agora = admin.firestore.FieldValue.serverTimestamp();
  const fila = [
    ...novos.map((doc) => ({ doc, idDestino: doc.id, novo: true })),
    ...sobrescrever.map((s) => ({ ...s, novo: false })),
  ];
  let gravados = 0;
  for (let i = 0; i < fila.length; i += LOTE) {
    const batch = db.batch();
    for (const item of fila.slice(i, i + LOTE)) {
      const { id, state, ...resto } = item.doc;
      batch.set(
        db.collection(COLECAO).doc(item.idDestino),
        {
          ...resto,
          ...(state ? { state } : {}),
          updatedAt: agora,
          // `createdAt` só em documento novo — merge não sobrescreve o que
          // já existe, mas mandar o campo de novo mexeria na data de
          // criação de quem já estava lá.
          ...(item.novo ? { createdAt: agora } : {}),
        },
        { merge: true },
      );
      gravados++;
    }
    await batch.commit();
    process.stdout.write(`\r  gravados ${gravados}/${fila.length}`);
  }
  console.log(`\npronto: ${gravados} documentos gravados em ${COLECAO}.`);
}

main().catch((e) => {
  console.error('\nfalhou:', e);
  process.exit(1);
});
