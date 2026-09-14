#!/usr/bin/env node
/**
 * Gera a planilha de convite por WhatsApp a partir do `providerDirectory`
 * inteiro (as ~9.700 entradas), direto do Firestore.
 *
 *   npm install exceljs          (uma vez, dentro de scripts/)
 *   node scripts/exportar_base_contatos.js <chave.json>
 *   node scripts/exportar_base_contatos.js <chave.json> --com-telefone
 *   node scripts/exportar_base_contatos.js <chave.json> --csv
 *
 * POR QUE PRECISA DE SCRIPT: a base de 9.700 está no Firestore, não no
 * disco. O que sobrou na pasta é só a carga de Criciúma
 * (prospeccao_criciuma.csv, 1.473 linhas) — as cargas anteriores foram
 * importadas e os CSVs de origem não ficaram. O banco é o único lugar
 * onde a base completa existe hoje.
 *
 * `--com-telefone` deixa de fora quem não tem número: sem telefone não há
 * o que enviar. `--csv` gera também o CSV, útil pra abrir em outra
 * ferramenta.
 *
 * SAÍDA: scripts/base_convite_whatsapp.xlsx (abas contatos, resumo,
 * revisar_telefone e leia-me).
 *
 * TODO MUNDO SAI COM opt_in_whatsapp = false e status = sem_consentimento.
 * Ninguém desta base pediu contato; o consentimento é registrado depois,
 * quando a pessoa responder que sim. O script não tem como inventar isso.
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

let montarPlanilha;
try {
  ({ montarPlanilha } = require('./planilha_convite'));
} catch (e) {
  console.error('Não consegui carregar planilha_convite.js.');
  console.error('Se a mensagem abaixo falar em "exceljs", rode dentro de scripts/:  npm install exceljs');
  console.error(e.message);
  process.exit(1);
}

const XLSX = path.join(__dirname, 'base_convite_whatsapp.xlsx');
const CSV = path.join(__dirname, 'base_contatos_export.csv');
const SO_COM_TELEFONE = process.argv.includes('--com-telefone');
const TAMBEM_CSV = process.argv.includes('--csv');

function soDigitos(v) {
  return String(v || '').replace(/\D/g, '');
}

/**
 * Celular no Brasil tem 11 dígitos (DDD + 9 + 8). Dez dígitos começando
 * em 2/3/4/5 é telefone fixo, e fixo não recebe WhatsApp — mandar pra lá
 * é mensagem que nunca chega.
 */
function tipoDoNumero(d) {
  if (!d) return 'sem_telefone';
  const n = d.startsWith('55') ? d.slice(2) : d;
  if (n.length === 11 && n[2] === '9') return 'celular';
  if (n.length === 10 && '2345'.includes(n[2])) return 'fixo';
  return 'invalido';
}

function normalizar(d) {
  if (!d) return '';
  return d.startsWith('55') ? d : `55${d}`;
}

function campo(v) {
  return `"${String(v == null ? '' : v).replace(/"/g, '""')}"`;
}

function hoje() {
  const d = new Date();
  return `${String(d.getDate()).padStart(2, '0')}/${String(d.getMonth() + 1).padStart(2, '0')}/${d.getFullYear()}`;
}

async function main() {
  const chave = process.argv[2];
  if (!chave || chave.startsWith('--')) {
    console.error('uso: node scripts/exportar_base_contatos.js <chave.json> [--com-telefone] [--csv]');
    process.exit(1);
  }
  if (!fs.existsSync(chave)) {
    console.error(`não achei a chave em ${chave}`);
    process.exit(1);
  }

  admin.initializeApp({ credential: admin.credential.cert(require(path.resolve(chave))) });
  const db = admin.firestore();

  console.log('lendo providerDirectory...');
  const snap = await db.collection('providerDirectory').get();
  console.log(`${snap.size} entradas no diretório\n`);

  const contatos = [];
  let semTelefoneDeFora = 0;

  for (const doc of snap.docs) {
    const d = doc.data();
    const digitos = soDigitos(d.whatsapp);
    const tipo = tipoDoNumero(digitos);

    if (!digitos && SO_COM_TELEFONE) {
      semTelefoneDeFora++;
      continue;
    }

    contatos.push({
      nome: d.name || '',
      whatsapp: normalizar(digitos),
      // `categories` (lista) é o formato atual; `category` é o antigo.
      categoria: Array.isArray(d.categories) && d.categories.length
        ? d.categories.join(' | ')
        : d.category || '',
      cidade: d.city || '',
      estado: d.state || '',
      // `claimed` = criou conta e assumiu o perfil, ou seja, chegou por
      // conta própria. O resto veio de busca pública. Essa distinção
      // importa: só a primeira tem alguma relação prévia com você.
      origem: d.claimed === true ? 'cadastro_app' : 'busca_publica',
      tipo,
    });
  }

  // Ordem previsível pra planilha não embaralhar entre duas gerações.
  contatos.sort((a, b) =>
    (a.cidade || '').localeCompare(b.cidade || '', 'pt-BR')
    || (a.categoria || '').localeCompare(b.categoria || '', 'pt-BR')
    || (a.nome || '').localeCompare(b.nome || '', 'pt-BR'));

  const resumo = await montarPlanilha(contatos, {
    arquivo: XLSX,
    fonte: 'providerDirectory (Firestore)',
    geradoEm: hoje(),
  });

  if (TAMBEM_CSV) {
    const cab = 'nome,whatsapp,categoria,cidade,estado,origem,opt_in_whatsapp,data_opt_in,status,mensagem,tipo_numero';
    const linhas = contatos.map((c) => [
      c.nome, c.whatsapp, c.categoria, c.cidade, c.estado, c.origem,
      'false', '', 'sem_consentimento', '', c.tipo,
    ].map(campo).join(','));
    fs.writeFileSync(CSV, `﻿${cab}\n${linhas.join('\n')}\n`, 'utf8');
  }

  const t = resumo.tipos;
  console.log(`contatos na planilha:             ${resumo.total}`);
  console.log(`celular (dá pra mandar WhatsApp): ${t.celular || 0}`);
  console.log(`fixo (não recebe WhatsApp):       ${t.fixo || 0}`);
  console.log(`inválido / 0800:                  ${t.invalido || 0}`);
  console.log(`sem telefone nenhum:              ${(t.sem_telefone || 0) + semTelefoneDeFora}${SO_COM_TELEFONE ? ' (fora do arquivo)' : ''}`);
  console.log(`cidades:                          ${resumo.cidades}`);
  console.log(`\nplanilha: ${XLSX}`);
  if (TAMBEM_CSV) console.log(`csv:      ${CSV}`);
  console.log('\ntodos saíram com opt_in_whatsapp = FALSO — o consentimento entra depois, um a um.');
  console.log('aptos para envio agora: 0. É o número correto até alguém responder que sim.');
}

if (require.main === module) {
  main().catch((e) => {
    console.error('\nfalhou:', e);
    process.exit(1);
  });
}
