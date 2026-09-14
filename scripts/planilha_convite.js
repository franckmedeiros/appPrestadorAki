/**
 * Monta a planilha de consentimento de WhatsApp (.xlsx).
 *
 * Separado do script de exportação de propósito: assim a montagem da
 * planilha pode ser testada com dados de mentira, sem precisar do banco.
 *
 * Recebe uma lista de contatos já normalizados e devolve o arquivo salvo.
 */
const ExcelJS = require('exceljs');

const FONTE = 'Arial';
const AZUL = 'FF1F3864';
const AMARELO = 'FFFFF2CC';
const BRANCO = 'FFFFFFFF';

const COLUNAS = [
  { header: 'nome', width: 46 },
  { header: 'whatsapp', width: 16 },
  { header: 'categoria', width: 26 },
  { header: 'cidade', width: 18 },
  { header: 'estado', width: 8 },
  { header: 'origem', width: 16 },
  { header: 'opt_in_whatsapp', width: 16 },
  { header: 'data_opt_in', width: 13 },
  { header: 'status', width: 20 },
  { header: 'mensagem', width: 40 },
];

const STATUS = [
  'sem_consentimento', 'convite_autorizacao', 'autorizado', 'template_aprovado',
  'enviado', 'respondeu', 'interessado', 'recusou', 'remover',
];

const DESCRICAO_STATUS = {
  sem_consentimento: 'ainda não falou com você — não pode receber nada',
  convite_autorizacao: 'você mandou a mensagem individual pedindo autorização',
  autorizado: 'respondeu que sim — marque opt_in_whatsapp = VERDADEIRO e a data',
  template_aprovado: 'a mensagem modelo dele já passou na aprovação da Meta',
  enviado: 'recebeu a mensagem em massa',
  respondeu: 'respondeu alguma coisa',
  interessado: 'quer usar o app',
  recusou: 'disse que não quer',
  remover: 'pediu para sair — apague o contato e nunca mais envie',
};

function preencher(celula, { negrito = false, fundo = null, cor = null, italico = false, tamanho = null } = {}) {
  celula.font = { name: FONTE, bold: negrito, italic: italico, ...(cor ? { color: { argb: cor } } : {}), ...(tamanho ? { size: tamanho } : {}) };
  if (fundo) celula.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: fundo } };
}

function cabecalho(ws, colunas) {
  ws.columns = colunas.map((c) => ({ width: c.width }));
  const linha = ws.getRow(1);
  colunas.forEach((c, i) => {
    const celula = linha.getCell(i + 1);
    celula.value = c.header;
    preencher(celula, { negrito: true, fundo: AZUL, cor: BRANCO });
    celula.alignment = { vertical: 'middle' };
  });
  linha.height = 22;
  ws.views = [{ state: 'frozen', ySplit: 1 }];
}

/**
 * @param {Array} contatos  {nome, whatsapp, categoria, cidade, estado, origem, tipo}
 * @param {Object} opcoes   {arquivo, fonte, geradoEm}
 */
async function montarPlanilha(contatos, opcoes) {
  const { arquivo, fonte, geradoEm } = opcoes;
  const wb = new ExcelJS.Workbook();
  const ultima = contatos.length + 1;

  // ------------------------------------------------------------ contatos
  const ws = wb.addWorksheet('contatos');
  cabecalho(ws, COLUNAS);

  contatos.forEach((c, i) => {
    const r = ws.getRow(i + 2);
    const valores = [
      c.nome, c.whatsapp, c.categoria, c.cidade, c.estado, c.origem,
      false, '', 'sem_consentimento', '',
    ];
    valores.forEach((v, j) => {
      const celula = r.getCell(j + 1);
      celula.value = v;
      preencher(celula, {});
    });
    // Telefone como TEXTO: sem isso o Excel come o zero à esquerda e
    // transforma número grande em notação científica.
    r.getCell(2).numFmt = '@';
    // As três colunas que a pessoa preenche ficam marcadas.
    [7, 8, 9].forEach((col) => preencher(r.getCell(col), { fundo: AMARELO }));

    r.getCell(9).dataValidation = {
      type: 'list', allowBlank: false, showErrorMessage: true,
      formulae: [`"${STATUS.join(',')}"`],
      errorTitle: 'Status inválido', error: 'Use um dos status da lista.',
    };
    r.getCell(7).dataValidation = {
      type: 'list', allowBlank: false, showErrorMessage: true,
      formulae: ['"VERDADEIRO,FALSO"'],
    };
  });

  ws.autoFilter = `A1:J${ultima}`;

  // ------------------------------------------------------------ resumo
  const rs = wb.addWorksheet('resumo');
  rs.columns = [{ width: 52 }, { width: 14 }];

  const G = `contatos!$G$2:$G$${ultima}`;
  const I = `contatos!$I$2:$I$${ultima}`;
  // Aceita tanto o booleano VERDADEIRO quanto o texto "VERDADEIRO": a
  // lista suspensa entrega texto, e quem digita na mão costuma deixar
  // booleano. Contar só um dos dois faria a planilha mentir justamente
  // na linha que decide se pode enviar.
  const OPTIN = `((${G}=TRUE())+(${G}="VERDADEIRO")>0)`;

  function linha(r, rotulo, opts = {}) {
    const { formula, valor, resultado, negrito = false, fundo = null, italico = false, tamanho = null } = opts;
    const a = rs.getCell(r, 1);
    a.value = rotulo;
    preencher(a, { negrito, fundo, italico, tamanho });
    if (formula === undefined && valor === undefined) return;
    const b = rs.getCell(r, 2);
    b.value = formula !== undefined ? { formula, result: resultado } : valor;
    preencher(b, { negrito, fundo });
    b.alignment = { horizontal: 'center' };
  }

  linha(1, `Base de convite — PrestadorAki`, { negrito: true });
  linha(2, `Gerado em ${geradoEm} a partir de ${fonte}`, { italico: true, tamanho: 9 });

  linha(4, 'APTOS PARA ENVIO AGORA', {
    negrito: true, fundo: AMARELO, resultado: 0,
    formula: `SUMPRODUCT(--${OPTIN},--((${I}="autorizado")+(${I}="template_aprovado")>0))`,
  });
  linha(5, 'Regra: só entra aqui quem tem opt_in_whatsapp = VERDADEIRO', { italico: true, tamanho: 9 });

  linha(7, 'Contatos na base', {
    negrito: true, formula: `COUNTA(contatos!$A$2:$A$${ultima})`, resultado: contatos.length,
  });

  linha(9, 'Por status', { negrito: true });
  STATUS.forEach((s, i) => {
    linha(10 + i, `   ${s}`, {
      formula: `COUNTIF(${I},"${s}")`,
      resultado: s === 'sem_consentimento' ? contatos.length : 0,
    });
  });

  const tipos = { celular: 0, fixo: 0, invalido: 0, sem_telefone: 0 };
  contatos.forEach((c) => { tipos[c.tipo] = (tipos[c.tipo] || 0) + 1; });

  linha(20, 'Por tipo de número', { negrito: true });
  linha(21, '   celular (tem WhatsApp)', { valor: tipos.celular });
  linha(22, '   fixo (NÃO tem WhatsApp)', { valor: tipos.fixo });
  linha(23, '   inválido / 0800', { valor: tipos.invalido });
  linha(24, '   sem telefone na base', { valor: tipos.sem_telefone });
  linha(25, 'Contado pelo formato do número: celular no Brasil tem 11 dígitos e o 9 depois do DDD.',
    { italico: true, tamanho: 9 });

  const cidades = new Map();
  contatos.forEach((c) => cidades.set(c.cidade || '(sem cidade)', (cidades.get(c.cidade || '(sem cidade)') || 0) + 1));
  const ordenadas = [...cidades.entries()].sort((a, b) => b[1] - a[1]);

  linha(27, `Cidades (${ordenadas.length})`, { negrito: true });
  ordenadas.slice(0, 25).forEach(([c, n], i) => linha(28 + i, `   ${c}`, { valor: n }));

  // ------------------------------------------------------ revisar_telefone
  const rv = wb.addWorksheet('revisar_telefone');
  cabecalho(rv, [
    { header: 'nome', width: 46 }, { header: 'whatsapp', width: 20 },
    { header: 'tipo', width: 14 }, { header: 'categoria', width: 26 },
    { header: 'cidade', width: 18 },
  ]);
  let r = 2;
  contatos.filter((c) => c.tipo !== 'celular').forEach((c) => {
    const linhaRv = rv.getRow(r++);
    [c.nome, c.whatsapp, c.tipo, c.categoria, c.cidade].forEach((v, j) => {
      const celula = linhaRv.getCell(j + 1);
      celula.value = v;
      preencher(celula, {});
    });
    linhaRv.getCell(2).numFmt = '@';
  });
  if (r > 2) rv.autoFilter = `A1:E${r - 1}`;

  // ------------------------------------------------------------ leia-me
  const lm = wb.addWorksheet('leia-me');
  lm.columns = [{ width: 26 }, { width: 96 }];

  function par(linhaNum, a, b) {
    const ca = lm.getCell(linhaNum, 1);
    ca.value = a;
    preencher(ca, { negrito: true });
    ca.alignment = { vertical: 'top' };
    const cb = lm.getCell(linhaNum, 2);
    cb.value = b;
    preencher(cb, {});
    cb.alignment = { vertical: 'top', wrapText: true };
    lm.getRow(linhaNum).height = Math.max(15, 13 * (1 + Math.floor(b.length / 95)));
  }

  par(1, 'O que é', 'Base de contatos para convidar prestadores a usar o PrestadorAki, com o '
    + 'registro de quem autorizou receber mensagem no WhatsApp.');
  par(2, 'De onde veio', `${fonte}. Nenhum desses contatos pediu para ser procurado: por isso `
    + 'todos entram com opt_in_whatsapp = FALSO.');
  par(3, 'A regra', 'Não enviar para quem está com opt_in_whatsapp vazio ou FALSO.');
  par(5, 'O que você preenche', 'As três colunas em amarelo: opt_in_whatsapp, data_opt_in e '
    + 'status. As outras vieram da base.');
  par(6, 'Exemplo de linha pronta', '"João Elétrica" | 5548999999999 | eletricista | Criciúma | '
    + 'SC | formulario | VERDADEIRO | 2026-09-14 | autorizado');
  par(8, 'Os status', '');
  STATUS.forEach((s, i) => {
    const ca = lm.getCell(9 + i, 1);
    ca.value = `   ${s}`;
    preencher(ca, {});
    const cb = lm.getCell(9 + i, 2);
    cb.value = DESCRICAO_STATUS[s];
    preencher(cb, {});
  });
  par(19, 'Telefone', 'Guardado como texto, no formato 55 + DDD + número (5548999999999), que é '
    + 'o que a API do WhatsApp espera. A aba revisar_telefone lista quem tem número fixo, 0800 '
    + 'ou nenhum — esses não recebem WhatsApp.');
  par(20, 'Antes de qualquer envio', 'A primeira mensagem, a que pede autorização, é individual '
    + 'e sai da sua conta WhatsApp Business na mão. Só depois do "sim" o contato entra em '
    + 'disparo.');

  await wb.xlsx.writeFile(arquivo);
  return { arquivo, total: contatos.length, tipos, cidades: ordenadas.length };
}

module.exports = { montarPlanilha, STATUS };
