#!/usr/bin/env node
/**
 * Converte o CSV de prospecção (saída do levantamento no Google Places)
 * nos documentos que o `providerDirectory` espera — a "carga inicial"
 * descrita em functions/src/subscription.ts.
 *
 * Roda sem tocar em nada: lê o CSV, escreve um JSON. Quem grava no
 * Firestore é o importar_prestadores.js, num passo separado e conferível.
 *
 *   node scripts/converter_prospeccao.js prospeccao_resultados.csv
 *
 * Três decisões tomadas aqui que valem ser conhecidas:
 *
 * 1. TELEFONE SEM O CÓDIGO DO PAÍS. O CSV traz 5548991617128; o app, ao
 *    cadastrar, normaliza o que a pessoa digita na máscara
 *    (00) 00000-0000 e chega em 48991617128 — sem o 55. Como é por esse
 *    campo (`phoneNormalized`) que a Cloud Function acha e reivindica a
 *    entrada da carga inicial quando o prestador finalmente cria conta,
 *    gravar com o 55 faria NENHUMA das entradas ser encontrada: todas
 *    ficariam órfãs na busca e a pessoa criaria um perfil duplicado ao
 *    lado. Por isso o 55 sai aqui.
 *
 * 2. A BIO DO GOOGLE NÃO VAI. No CSV ela é o tipo do lugar traduzido
 *    ("Categoria pública: pet boarding service.") — no perfil público
 *    isso apareceria como se fosse a descrição escrita pelo profissional.
 *    Melhor vazio: quando a pessoa assumir o perfil, ela escreve a dela.
 *
 * 3. A COLUNA `observacoes` NÃO VAI. Ali estão place_id, endereço, site e
 *    link do Maps, que são conteúdo da API do Google. O diretório não
 *    precisa de nada disso pra funcionar (busca usa nome, categoria e
 *    cidade), então fica de fora — menos dado de terceiro publicado é
 *    melhor, e o que sobra (nome, telefone, cidade) é o mínimo pra
 *    pessoa ser encontrada e convidada.
 */
const fs = require('fs');
const path = require('path');

/** CSV com aspas: nomes de empresa têm vírgula, então split(',') não serve. */
function parseCsv(txt) {
  const rows = [];
  let row = [];
  let cur = '';
  let quoted = false;
  for (let i = 0; i < txt.length; i++) {
    const c = txt[i];
    if (quoted) {
      if (c === '"') {
        if (txt[i + 1] === '"') {
          cur += '"';
          i++;
        } else quoted = false;
      } else cur += c;
    } else if (c === '"') quoted = true;
    else if (c === ',') {
      row.push(cur);
      cur = '';
    } else if (c === '\n') {
      row.push(cur);
      cur = '';
      rows.push(row);
      row = [];
    } else if (c !== '\r') cur += c;
  }
  if (cur || row.length) {
    row.push(cur);
    rows.push(row);
  }
  return rows.filter((r) => r.length > 1);
}

/**
 * Só dígitos e sem o código do país — mesma forma que
 * `AuthController._normalizePhone` produz no app a partir da máscara, e
 * que `normalizarTelefone` (functions/src/subscription.ts) compara.
 */
function normalizarTelefone(bruto) {
  let d = String(bruto || '').replace(/\D/g, '');
  if ((d.length === 12 || d.length === 13) && d.startsWith('55')) d = d.slice(2);
  return d;
}

/** (48) 99161-7128 / (48) 3433-1234 — só pra exibição no perfil. */
function formatarTelefone(digitos) {
  if (digitos.length === 11) {
    return `(${digitos.slice(0, 2)}) ${digitos.slice(2, 7)}-${digitos.slice(7)}`;
  }
  if (digitos.length === 10) {
    return `(${digitos.slice(0, 2)}) ${digitos.slice(2, 6)}-${digitos.slice(6)}`;
  }
  return digitos;
}

/**
 * Correções de categoria: ids que o CSV usa e o catálogo do app não tem.
 * Deixado explícito em vez de "adivinhar o mais parecido" — uma categoria
 * errada faz o prestador nunca aparecer na busca em que ele deveria, e é
 * um erro silencioso.
 */
const CORRECOES_CATEGORIA = {
  cacamba_entulho: 'cacambeiro',
};

function main() {
  const csvPath = process.argv[2];
  if (!csvPath) {
    console.error('uso: node scripts/converter_prospeccao.js <arquivo.csv>');
    process.exit(1);
  }
  const raiz = path.resolve(__dirname, '..');
  const catalogo = JSON.parse(
    fs.readFileSync(path.join(raiz, 'assets/data/service_categories.json'), 'utf8'),
  );
  const idsValidos = new Set();
  for (const grupo of catalogo.groups) {
    for (const sub of grupo.subcategories) idsValidos.add(sub.id);
  }

  const rows = parseCsv(fs.readFileSync(csvPath, 'utf8').replace(/^﻿/, ''));
  const head = rows[0].map((h) => h.trim());
  const col = Object.fromEntries(head.map((h, i) => [h, i]));
  for (const obrigatoria of ['nome', 'whatsapp', 'categorias', 'cidade', 'estado']) {
    if (col[obrigatoria] === undefined) {
      console.error(`coluna obrigatória ausente no CSV: ${obrigatoria}`);
      process.exit(1);
    }
  }

  const docs = [];
  const semTelefone = [];
  const categoriasDesconhecidas = new Map();
  const porTelefone = new Map();
  const duplicados = [];

  for (const r of rows.slice(1)) {
    const nome = (r[col.nome] || '').trim();
    if (!nome) continue;

    const telefone = normalizarTelefone(r[col.whatsapp]);
    if (!telefone || telefone.length < 10) {
      semTelefone.push(nome);
      continue;
    }

    const categorias = [];
    for (const bruta of (r[col.categorias] || '').split(',')) {
      const id = CORRECOES_CATEGORIA[bruta.trim()] || bruta.trim();
      if (!id) continue;
      if (!idsValidos.has(id)) {
        categoriasDesconhecidas.set(id, (categoriasDesconhecidas.get(id) || 0) + 1);
        continue;
      }
      if (!categorias.includes(id)) categorias.push(id);
    }
    // Sem categoria válida o prestador não aparece em busca nenhuma —
    // não adianta importar, vira peso morto na coleção.
    if (categorias.length === 0) continue;

    if (porTelefone.has(telefone)) {
      duplicados.push(`${nome} (mesmo telefone de ${porTelefone.get(telefone)})`);
      continue;
    }
    porTelefone.set(telefone, nome);

    docs.push({
      // Id derivado do telefone: rodar a importação duas vezes ATUALIZA a
      // mesma entrada em vez de criar uma segunda.
      id: `imp_${telefone}`,
      name: nome,
      // `category` (singular) é o campo antigo, ainda lido por versões do
      // app instaladas que não atualizaram; `categories` é o que a busca
      // usa hoje (ver ProviderDirectoryRepository.search).
      category: categorias[0],
      categories: categorias,
      city: (r[col.cidade] || '').trim(),
      state: (r[col.estado] || '').trim() || undefined,
      whatsapp: formatarTelefone(telefone),
      phoneNormalized: telefone,
      // Explícito, não ausente: a consulta que reivindica a entrada usa
      // `where('claimed','==',false)`, e o Firestore não casa `==` com
      // campo que não existe.
      claimed: false,
    });
  }

  const saida = path.join(raiz, 'scripts', 'prestadores_para_importar.json');
  fs.writeFileSync(saida, JSON.stringify(docs, null, 2));

  console.log(`linhas lidas:            ${rows.length - 1}`);
  console.log(`documentos gerados:      ${docs.length}`);
  console.log(`sem telefone utilizável: ${semTelefone.length}`);
  console.log(`descartados por duplicidade de telefone: ${duplicados.length}`);
  duplicados.slice(0, 10).forEach((d) => console.log(`   - ${d}`));
  if (categoriasDesconhecidas.size) {
    console.log('CATEGORIAS NÃO RECONHECIDAS (essas linhas perderam a categoria):');
    for (const [id, n] of categoriasDesconhecidas) console.log(`   - ${id}: ${n}x`);
  } else {
    console.log('todas as categorias foram reconhecidas pelo catálogo do app');
  }
  const celulares = docs.filter((d) => d.phoneNormalized.length === 11).length;
  console.log(`celulares (reivindicáveis por telefone): ${celulares}`);
  console.log(`fixos:                                   ${docs.length - celulares}`);
  console.log(`\narquivo gerado: ${saida}`);
}

main();
