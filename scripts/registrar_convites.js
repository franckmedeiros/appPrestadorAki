#!/usr/bin/env node
/**
 * PRÉ-CADASTRO COM CONSENTIMENTO — registra quem respondeu "SIM" no
 * WhatsApp ("posso incluir sua empresa no PrestadorAki?").
 *
 * Para cada linha do CSV:
 *   - acha a entrada do `providerDirectory` pelo telefone (`phoneNormalized`)
 *     ou cria uma nova (`imp_<telefone>`), com `claimed: false`,
 *     `visible: true` (aparece na busca) e `aceitaPedidos: true` (o cliente
 *     consegue pedir orçamento). NUNCA grava o WhatsApp como campo público
 *     (`whatsapp`) — só o `phoneNormalized`, que é o que a assinatura usa
 *     pra substituir esta entrada pela do prestador depois.
 *   - grava `convitesPrestador/{id}` (privado, só servidor) com WhatsApp,
 *     data do consentimento e origem. É pra esse número que o aviso de
 *     pedido vai (ver functions/src/convites.ts).
 *
 * Entradas já reivindicadas (`claimed: true`) são puladas.
 *
 * CSV (separado por vírgula ou ponto e vírgula, com cabeçalho):
 *   nome,categoria,cidade,uf,whatsapp
 * `categoria` pode ser o id (eletricista) ou o nome que aparece na
 * planilha ("Eletricista", "Pedreiro / Alvenaria").
 *
 * Sempre simula primeiro:
 *   node scripts/registrar_convites.js C:\caminho\chave.json aceitaram.csv
 *   node scripts/registrar_convites.js C:\caminho\chave.json aceitaram.csv --gravar
 *
 * Para tirar alguém (pediu pra sair): coloque a linha num CSV e rode com
 * `--remover` — esconde da busca, desliga os pedidos e marca o convite
 * como optout.
 */
const fs = require('fs');
const path = require('path');

let admin;
try {
  admin = require('firebase-admin');
} catch {
  console.error('firebase-admin não encontrado. Rode `npm install` dentro de scripts/ primeiro.');
  process.exit(1);
}

const [chave, arquivo, ...flags] = process.argv.slice(2);
const GRAVAR = flags.includes('--gravar');
const REMOVER = flags.includes('--remover');
if (!chave || !arquivo) {
  console.error('Uso: node scripts/registrar_convites.js <chave.json> <arquivo.csv> [--gravar] [--remover]');
  process.exit(1);
}

const norm = (s) => String(s ?? '').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '').trim();
const soDigitos = (s) => String(s ?? '').replace(/\D/g, '');

/** Mesmo formato do `phoneNormalized` gravado pelo app/subscription.ts: só dígitos, sem o 55. */
function telefoneNormalizado(bruto) {
  let d = soDigitos(bruto);
  if (d.startsWith('55') && d.length >= 12) d = d.slice(2);
  if (d.startsWith('0')) d = d.slice(1);
  return d.length === 10 || d.length === 11 ? d : null;
}

// Categorias do app (assets/data/service_categories.json).
const catalogo = JSON.parse(
  fs.readFileSync(path.join(__dirname, '..', 'assets', 'data', 'service_categories.json'), 'utf8'),
);
const categorias = catalogo.groups.flatMap((g) => g.subcategories);
function categoriaId(valor) {
  const v = norm(valor);
  if (!v) return null;
  const exata = categorias.find((c) => c.id === v || norm(c.label) === v);
  if (exata) return exata.id;
  // Nomes usados na planilha de prospecção que não batem com o rótulo do app.
  const apelidos = {
    'reparos gerais': 'reparo_geral',
    'marido de aluguel': 'reparo_geral',
    'fotografo de eventos': 'fotografo_eventos',
    diarista: 'limpeza',
  };
  if (apelidos[v]) return apelidos[v];
  // Qualquer palavra do rótulo do app (ex.: "Reparos" em "Marido de Aluguel / Reparos Gerais").
  const porParte = categorias.find((c) => norm(c.label).split(' / ').some((parte) => parte === v));
  if (porParte) return porParte.id;
  // "Eletricista" casa com "Eletricista Residencial"; "Banho e tosa" com "Banho e Tosa (Pet)".
  const parcial = categorias.find((c) => norm(c.label).startsWith(v) || v.startsWith(norm(c.label).split(' /')[0]));
  return parcial ? parcial.id : null;
}

function lerCsv(caminho) {
  const linhas = fs.readFileSync(caminho, 'utf8').replace(/^\uFEFF/, '').split(/\r?\n/).filter((l) => l.trim());
  const sep = linhas[0].includes(';') ? ';' : ',';
  const dividir = (l) => {
    const out = [];
    let cur = '';
    let aspas = false;
    for (const ch of l) {
      if (ch === '"') aspas = !aspas;
      else if (ch === sep && !aspas) {
        out.push(cur);
        cur = '';
      } else cur += ch;
    }
    out.push(cur);
    return out.map((x) => x.trim());
  };
  const cab = dividir(linhas[0]).map(norm);
  const idx = (...nomes) => cab.findIndex((c) => nomes.includes(c));
  const iNome = idx('nome', 'name', 'empresa');
  const iCat = idx('categoria', 'category', 'servico');
  const iCid = idx('cidade', 'city');
  const iUf = idx('uf', 'estado', 'state');
  const iTel = idx('whatsapp', 'telefone', 'whatsapp_normalizado', 'phone', 'celular');
  if (iNome < 0 || iTel < 0) throw new Error('O CSV precisa das colunas nome e whatsapp.');
  return linhas.slice(1).map((l) => {
    const c = dividir(l);
    return { nome: c[iNome], categoria: c[iCat], cidade: c[iCid], uf: c[iUf], whatsapp: c[iTel] };
  });
}

async function main() {
  admin.initializeApp({ credential: admin.credential.cert(require(path.resolve(chave))) });
  const db = admin.firestore();
  const agora = admin.firestore.FieldValue.serverTimestamp();

  const linhas = lerCsv(arquivo);
  let ok = 0;
  const problemas = [];

  for (const [n, l] of linhas.entries()) {
    const tel = telefoneNormalizado(l.whatsapp);
    if (!tel) {
      problemas.push(`linha ${n + 2}: WhatsApp inválido (${l.whatsapp})`);
      continue;
    }
    const existentes = await db.collection('providerDirectory').where('phoneNormalized', '==', tel).get();
    const ja = existentes.docs[0];
    if (ja && ja.data().claimed === true) {
      problemas.push(`linha ${n + 2}: ${l.nome} já tem conta no app (pulado)`);
      continue;
    }
    const id = ja ? ja.id : `imp_${tel}`;

    if (REMOVER) {
      console.log(`${GRAVAR ? 'REMOVENDO' : '[simulação] removeria'} ${l.nome} (${id})`);
      if (GRAVAR) {
        await db.collection('providerDirectory').doc(id).set({ visible: false, aceitaPedidos: false, updatedAt: agora }, { merge: true });
        await db.collection('convitesPrestador').doc(id).set({ optout: true, optoutEm: agora }, { merge: true });
      }
      ok++;
      continue;
    }

    const cat = categoriaId(l.categoria) ?? (ja && ja.data().category) ?? null;
    if (!cat) {
      problemas.push(`linha ${n + 2}: categoria "${l.categoria}" não reconhecida (${l.nome})`);
      continue;
    }
    const cidade = String(l.cidade || (ja && ja.data().city) || '').trim();
    if (!cidade) {
      problemas.push(`linha ${n + 2}: sem cidade (${l.nome})`);
      continue;
    }

    console.log(`${GRAVAR ? 'GRAVANDO' : '[simulação]'} ${l.nome} · ${cat} · ${cidade}/${l.uf || ''} · ${tel} → ${id}${ja ? ' (já existia)' : ' (nova)'}`);
    if (GRAVAR) {
      await db.collection('providerDirectory').doc(id).set(
        {
          name: ja ? ja.data().name || l.nome : l.nome,
          category: cat,
          categories: ja && Array.isArray(ja.data().categories) && ja.data().categories.length ? ja.data().categories : [cat],
          city: cidade,
          ...(l.uf ? { state: String(l.uf).toUpperCase() } : {}),
          claimed: false,
          visible: true,
          aceitaPedidos: true,
          phoneNormalized: tel,
          updatedAt: agora,
          ...(ja ? {} : { createdAt: agora, ratingAverage: 0, ratingCount: 0 }),
        },
        { merge: true },
      );
      await db.collection('convitesPrestador').doc(id).set(
        {
          nome: l.nome,
          whatsapp: tel,
          categoria: cat,
          cidade,
          consentimentoEm: agora,
          origem: 'whatsapp_manual',
          optout: false,
        },
        { merge: true },
      );
    }
    ok++;
  }

  console.log(`\n${ok} prestador(es) ${GRAVAR ? 'processados' : 'seriam processados'}.`);
  if (problemas.length) console.log(`\nAtenção:\n- ${problemas.join('\n- ')}`);
  if (!GRAVAR) console.log('\nNada foi gravado. Confira e rode de novo com --gravar.');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
