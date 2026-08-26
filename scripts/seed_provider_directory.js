#!/usr/bin/env node
/**
 * Carga inicial do diretório público de prestadores (`providerDirectory`,
 * entradas "não reivindicadas" — ver README.md e DATA_MODEL.md, seção
 * "Marketplace").
 *
 * ANTES DE RODAR ISSO COM NOMES DE VERDADE, leia com atenção:
 *
 *   Só coloque aqui prestadores que você (ou alguém da equipe) JÁ TEM
 *   consentimento pra listar publicamente no PrestadorAki — uma conversa,
 *   uma mensagem, algo que comprove que a pessoa topou. Nunca telefone,
 *   WhatsApp ou e-mail aqui: só nome, categoria e cidade. Usar o nome de
 *   alguém (principalmente autônomo, onde "nome do negócio" costuma ser o
 *   próprio nome da pessoa) pra criar um perfil comercial sem permissão
 *   esbarra na LGPD, mesmo que a informação já fosse pública em outro
 *   lugar (um catálogo do Google Maps, por exemplo). Ver a discussão
 *   completa no README.md.
 *
 *   Este script usa a chave de administrador do Firebase — ela IGNORA as
 *   regras do firestore.rules. É fácil escrever besteira em produção por
 *   engano; o script mostra tudo que vai gravar e pede confirmação antes
 *   de tocar no banco de verdade.
 *
 * Uso:
 *   cd scripts
 *   npm install
 *   node seed_provider_directory.js <service-account.json> <providers.csv>
 *
 * O arquivo de credencial (service-account.json) é gerado em:
 *   Console do Firebase → ⚙️ Configurações do projeto → Contas de serviço
 *   → "Gerar nova chave privada". NUNCA cometa esse arquivo no git — ele
 *   dá acesso total ao seu projeto Firebase (o .gitignore da raiz já
 *   bloqueia qualquer *serviceAccount*.json dentro de scripts/).
 *
 * Formato do CSV (cabeçalho obrigatório, nessa ordem — ver
 * providers_seed.example.csv):
 *   name,category,city,state
 *
 * `category` precisa ser um destes valores (os mesmos do enum
 * ServiceCategory do app — lib/features/marketplace/models/service_category.dart):
 *   eletricista, encanador, pedreiro, pintor, jardineiro, limpeza,
 *   marceneiro, serralheiro, climatizacao, vidraceiro, azulejista, outro
 * `state` é opcional (sigla, ex.: SC).
 */

const fs = require('fs');
const path = require('path');
const readline = require('readline');
const admin = require('firebase-admin');

const VALID_CATEGORIES = new Set([
  'eletricista', 'encanador', 'pedreiro', 'pintor', 'jardineiro',
  'limpeza', 'marceneiro', 'serralheiro', 'climatizacao', 'vidraceiro', 'azulejista', 'outro',
]);

/** Parser de CSV simples que respeita campos entre aspas (nomes com vírgula). */
function splitCsvLine(line) {
  const result = [];
  let current = '';
  let inQuotes = false;
  for (let i = 0; i < line.length; i++) {
    const char = line[i];
    if (char === '"') {
      inQuotes = !inQuotes;
    } else if (char === ',' && !inQuotes) {
      result.push(current);
      current = '';
    } else {
      current += char;
    }
  }
  result.push(current);
  return result.map((value) => value.trim());
}

function parseCsv(text) {
  const lines = text.split(/\r?\n/).filter((line) => line.trim().length > 0);
  if (lines.length === 0) return [];
  const [headerLine, ...rows] = lines;
  const headers = splitCsvLine(headerLine);
  return rows.map((line) => {
    const values = splitCsvLine(line);
    const row = {};
    headers.forEach((header, i) => { row[header] = values[i] ?? ''; });
    return row;
  });
}

/**
 * Id determinístico (nome+cidade) — rodar o script de novo com o mesmo CSV
 * atualiza a mesma entrada em vez de criar uma duplicata.
 */
function slugId(name, city) {
  return `${name}-${city}`
    .toLowerCase()
    .normalize('NFD').replace(/[\u0300-\u036f]/g, '') // remove acentos
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/(^-|-$)/g, '');
}

function confirm(question) {
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  return new Promise((resolve) => {
    rl.question(question, (answer) => {
      rl.close();
      resolve(answer.trim().toLowerCase());
    });
  });
}

async function main() {
  const [, , serviceAccountPath, csvPath] = process.argv;
  if (!serviceAccountPath || !csvPath) {
    console.error('Uso: node seed_provider_directory.js <service-account.json> <providers.csv>');
    process.exit(1);
  }

  const serviceAccount = JSON.parse(fs.readFileSync(path.resolve(serviceAccountPath), 'utf8'));
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
  const db = admin.firestore();

  const csvText = fs.readFileSync(path.resolve(csvPath), 'utf8');
  const rows = parseCsv(csvText);

  if (rows.length === 0) {
    console.error('Nenhuma linha encontrada no CSV.');
    process.exit(1);
  }

  const valid = [];
  let skipped = 0;

  console.log(`Lidas ${rows.length} linha(s):\n`);
  for (const row of rows) {
    const { name, category, city, state } = row;
    const label = `${name || '(sem nome)'} — ${category || '(sem categoria)'} — ${city || '(sem cidade)'}${state ? '/' + state : ''}`;
    if (!name || !category || !city) {
      console.warn(`  ⚠️  ${label}  [incompleta — pulando]`);
      skipped++;
      continue;
    }
    if (!VALID_CATEGORIES.has(category)) {
      console.warn(`  ⚠️  ${label}  [categoria inválida — pulando. Valores aceitos: ${[...VALID_CATEGORIES].join(', ')}]`);
      skipped++;
      continue;
    }
    console.log(`  ✓ ${label}`);
    valid.push(row);
  }

  if (valid.length === 0) {
    console.error('\nNenhuma linha válida pra carregar. Nada foi escrito.');
    process.exit(1);
  }

  console.log(`\n${valid.length} linha(s) válida(s), ${skipped} pulada(s).`);
  const answer = await confirm(
    '\nConfirma a carga dessas linhas no Firestore de PRODUÇÃO, em providerDirectory? ' +
      '(digite "sim" pra continuar) ',
  );
  if (answer !== 'sim') {
    console.log('Cancelado — nada foi escrito.');
    process.exit(0);
  }

  let written = 0;
  for (const row of valid) {
    const { name, category, city, state } = row;
    const id = slugId(name, city);
    const ref = db.collection('providerDirectory').doc(id);
    const existing = await ref.get();
    const now = admin.firestore.FieldValue.serverTimestamp();
    await ref.set(
      {
        name,
        category,
        city,
        ...(state ? { state: state.toUpperCase() } : {}),
        claimed: false,
        updatedAt: now,
        // Só grava createdAt na primeira vez — igual ao
        // ProviderDirectoryRepository.upsertOwnListing do app, pra não
        // perder a data original se você rodar o script de novo depois.
        ...(existing.exists ? {} : { createdAt: now }),
      },
      { merge: true },
    );
    written++;
  }

  console.log(`\n✅ ${written} prestador(es) carregado(s)/atualizado(s) em providerDirectory.`);
  process.exit(0);
}

main().catch((err) => {
  console.error('\nErro ao carregar os dados:', err);
  process.exit(1);
});
