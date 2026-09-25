#!/usr/bin/env node
/**
 * Cria (ou atualiza) as contas de DEMONSTRAÇÃO usadas na revisão da Apple
 * e na gravação dos vídeos:
 *
 *   demo@prestadoraki.app          prestador (Denilson) — e também cliente
 *   demo.cliente@prestadoraki.app  cliente (Marina)
 *
 * Duas contas, e não uma, porque a Apple pediu "todos os tipos de conta" —
 * e porque solicitação de orçamento e avaliação SÓ EXISTEM tendo um
 * cliente de verdade do outro lado: os dois são gravados com o uid do
 * cliente (`clientUid` no orçamento, e o próprio id do documento em
 * `ratings/{clientUid}`).
 *
 *   node scripts/criar_conta_demo.js chave.json
 *   node scripts/criar_conta_demo.js chave.json --gravar
 *   node scripts/criar_conta_demo.js chave.json --gravar --semana 1
 *   node scripts/criar_conta_demo.js chave.json --gravar --limpar
 *
 * SIMULA POR PADRÃO. Sem `--gravar` só mostra o que faria.
 *
 * POR QUE ESSAS CONTAS PRECISAM SER CRIADAS POR AQUI, e não pelo app:
 *
 * A conta vira prestador quando `providers/{uid}` passa a existir (ver
 * AuthController._checkIsProvider). No app, o único caminho pra isso é a
 * assinatura: a compra é confirmada pela Cloud Function, que cria o
 * documento. Numa conta de demonstração não existe compra pra confirmar
 * — então o documento é criado aqui, direto, e a conta nasce prestador
 * sem passar pela loja. É por isso que o revisor da Apple consegue ver
 * as telas de prestador sem comprar nada no sandbox.
 *
 * O QUE É GRAVADO:
 *
 *   Auth                                     as duas contas
 *   clients/{uid}                            lado cliente (+ termsAcceptedAt)
 *   providers/{prestador}                    lado prestador — liga o gate
 *   providerDirectory/{prestador}            vitrine pública
 *   providerDirectory/{prestador}/ratings/*  avaliações com comentário
 *   providers/{prestador}/customers/*        clientes
 *   providers/{prestador}/appointments/*     a semana cheia da Agenda
 *   providers/{prestador}/jobs/*             6 meses pagos (Financeiro)
 *   providers/{prestador}/budgets/*          Orçamentos + Solicitações
 *
 * IDs FIXOS, de propósito: rodar de novo ATUALIZA os mesmos documentos em
 * vez de criar duplicata. Pode rodar quantas vezes quiser — inclusive só
 * pra reposicionar a agenda na semana atual, que é o motivo mais provável
 * de você voltar aqui (ver `--semana`).
 *
 * `--limpar` desfaz tudo: apaga os dados de prestador e a vitrine. As
 * contas no Auth continuam existindo.
 *
 * ATENÇÃO — A VITRINE FICA PÚBLICA: com `visible: true` esse prestador
 * aparece na busca de verdade, pra clientes de verdade em Criciúma, com
 * avaliações que foram inventadas aqui. É necessário assim pro revisor da
 * Apple encontrar o perfil. Depois da aprovação, esconda:
 *
 *   node scripts/remover_prestador.js chave.json demo@prestadoraki.app --so-vitrine --gravar
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

// ---------------------------------------------------------------- opções

const GRAVAR = process.argv.includes('--gravar');
const LIMPAR = process.argv.includes('--limpar');

function argNumero(flag, padrao) {
  const i = process.argv.indexOf(flag);
  if (i === -1 || !process.argv[i + 1]) return padrao;
  const n = Number(process.argv[i + 1]);
  return Number.isFinite(n) ? n : padrao;
}

/** Quantas semanas à frente posicionar a agenda (0 = semana atual). */
const SEMANA = argNumero('--semana', 0);

// ------------------------------------------------------------ as personas

const SENHA = '123456';

const PRESTADOR = {
  email: 'demo@prestadoraki.app',
  nome: 'Denilson Rocha',
  whatsapp: '(48) 99999-0000', // número inválido de propósito
  categoria: 'eletricista', // id do assets/data/service_categories.json
  cidade: 'Criciúma',
  uf: 'SC',
  cidadesAtendidas: ['Criciúma/SC', 'Içara/SC', 'Forquilhinha/SC'],
  bio:
    '22 anos de elétrica residencial. Atendo emergência e instalação. ' +
    'Orçamento sem compromisso.',
};

const CLIENTE = {
  email: 'demo.cliente@prestadoraki.app',
  nome: 'Marina Doring',
  whatsapp: '(48) 98888-0001',
  cidade: 'Criciúma',
  uf: 'SC',
};

const CLIENTES = [
  { id: 'demo-cli-marina', name: 'Marina Doring', whatsapp: '(48) 98888-0001', city: 'Criciúma' },
  { id: 'demo-cli-michel', name: 'Michel Búrigo', whatsapp: '(48) 98888-0002', city: 'Criciúma' },
  { id: 'demo-cli-ana', name: 'Ana Cechinel', whatsapp: '(48) 98888-0003', city: 'Içara' },
  { id: 'demo-cli-solar', name: 'Ed. Solar — Centro', whatsapp: '(48) 98888-0004', city: 'Criciúma' },
  { id: 'demo-cli-atlantico', name: 'Ed. Atlântico', whatsapp: '(48) 98888-0005', city: 'Criciúma' },
];

/**
 * Avaliações. O id do documento É o uid de quem avaliou (ver
 * ProviderRating), então só a da Marina usa uma conta de verdade — as
 * outras usam ids sintéticos, que é o bastante porque o nome mostrado na
 * tela vem do campo `clientName`, copiado no momento da avaliação.
 *
 * `ratingAverage`/`ratingCount` do documento da vitrine são CALCULADOS a
 * partir desta lista, nunca escritos à mão: foi exatamente esse descasamento
 * (o card dizia 37 avaliações e a lista abria vazia) que fez essa parte do
 * script ser reescrita.
 */
const AVALIACOES = [
  { id: 'MARINA', nome: 'Marina Doring', estrelas: 5, diasAtras: 6,   comentario: 'Respondeu no mesmo dia e apareceu na hora combinada. Trocou o chuveiro e ainda conferiu o disjuntor.' },
  { id: 'demo-av-michel',   nome: 'Michel Búrigo',  estrelas: 5, diasAtras: 24,  comentario: 'Refez a instalação da minha casa inteira. Trabalho limpo e explicou tudo o que estava fazendo.' },
  { id: 'demo-av-ana',      nome: 'Ana Cechinel',   estrelas: 5, diasAtras: 41,  comentario: 'Pontual e caprichoso. Já é a terceira vez que chamo.' },
  { id: 'demo-av-solar',    nome: 'Ed. Solar',      estrelas: 4, diasAtras: 58,  comentario: 'Bom serviço. Demorou um pouco pra conseguir a peça, mas avisou antes.' },
  { id: 'demo-av-carlos',   nome: 'Carlos Zanette', estrelas: 5, diasAtras: 73,  comentario: 'Resolveu um curto que dois eletricistas não acharam.' },
  { id: 'demo-av-lucia',    nome: 'Lúcia Fernandes',estrelas: 5, diasAtras: 95,  comentario: 'Preço justo e cumpriu o prazo direitinho.' },
  { id: 'demo-av-rafael',   nome: 'Rafael Minatto', estrelas: 4, diasAtras: 118, comentario: 'Serviço bem feito. Só achei o orçamento um pouco acima do que eu esperava.' },
  { id: 'demo-av-atlantico',nome: 'Ed. Atlântico',  estrelas: 5, diasAtras: 140, comentario: 'Atendeu o condomínio inteiro em dois dias. Recomendo.' },
];

/** A semana da Agenda. `dia` 0 = segunda. */
const AGENDA = [
  { id: 'demo-apt-1', dia: 0, hora: 8,  min: 0,  dur: 90,  tipo: 'servico',        titulo: 'Troca de disjuntor',          cliente: 'demo-cli-solar',     endereco: 'Rua Coronel Pedro Benedet, 200 — Centro' },
  { id: 'demo-apt-2', dia: 0, hora: 14, min: 0,  dur: 60,  tipo: 'servico',        titulo: 'Instalação de chuveiro',      cliente: 'demo-cli-marina',    endereco: 'Av. Centenário, 1200 — Centro' },
  { id: 'demo-apt-3', dia: 1, hora: 9,  min: 0,  dur: 180, tipo: 'servico',        titulo: 'Revisão elétrica completa',   cliente: 'demo-cli-michel',    endereco: 'Rua São José, 45 — Próspera' },
  { id: 'demo-apt-4', dia: 2, hora: 8,  min: 30, dur: 120, tipo: 'servico',        titulo: 'Ponto de ar-condicionado',    cliente: 'demo-cli-michel',    endereco: 'Rua São José, 45 — Próspera' },
  { id: 'demo-apt-5', dia: 2, hora: 15, min: 0,  dur: 45,  tipo: 'visita_tecnica', titulo: 'Visita de orçamento',         cliente: 'demo-cli-atlantico', endereco: 'Rua Anita Garibaldi, 830 — Centro' },
  { id: 'demo-apt-6', dia: 3, hora: 7,  min: 30, dur: 150, tipo: 'servico',        titulo: 'Instalação de luminárias',    cliente: 'demo-cli-ana',       endereco: 'Rua Getúlio Vargas, 77 — Içara' },
  { id: 'demo-apt-7', dia: 4, hora: 9,  min: 0,  dur: 300, tipo: 'servico',        titulo: 'Quadro de distribuição novo', cliente: 'demo-cli-atlantico', endereco: 'Rua Anita Garibaldi, 830 — Centro' },
];

/**
 * Histórico do Financeiro. `mesAtras` 0 = mês corrente.
 *
 * Um mês baixo de propósito no meio: gráfico que só sobe não parece real,
 * e a tela do Financeiro usa a barra mais alta como escala — com todos os
 * meses iguais o gráfico vira um bloco sem leitura.
 */
const SERVICOS = [
  { mesAtras: 5, itens: [['Troca de padrão de entrada', 'demo-cli-solar', 120000], ['Revisão elétrica', 'demo-cli-michel', 158000], ['Instalação de tomadas', 'demo-cli-ana', 120000]] },
  { mesAtras: 4, itens: [['Quadro de distribuição', 'demo-cli-atlantico', 220000], ['Iluminação de área externa', 'demo-cli-marina', 142000], ['Manutenção preventiva', 'demo-cli-solar', 100000]] },
  { mesAtras: 3, itens: [['Troca de disjuntores', 'demo-cli-michel', 95000], ['Ponto de chuveiro', 'demo-cli-ana', 140000], ['Reparo de curto-circuito', 'demo-cli-marina', 80000]] },
  { mesAtras: 2, itens: [['Instalação elétrica de reforma', 'demo-cli-atlantico', 190000], ['Automação de portão', 'demo-cli-solar', 210000], ['Troca de fiação', 'demo-cli-michel', 124000]] },
  { mesAtras: 1, itens: [['Padrão trifásico', 'demo-cli-atlantico', 240000], ['Instalação de ar-condicionado', 'demo-cli-ana', 199000], ['Iluminação de fachada', 'demo-cli-solar', 150000]] },
  { mesAtras: 0, itens: [['Quadro novo — 2 andares', 'demo-cli-atlantico', 260000], ['Revisão geral', 'demo-cli-michel', 238000], ['Instalação de chuveiro e tomadas', 'demo-cli-marina', 150000]] },
];

// ------------------------------------------------------------- utilitários

/**
 * Mesma normalização do app (lib/core/text_normalize.dart). Repetida aqui
 * porque é o que a busca compara no SERVIDOR: se divergir, o perfil é
 * gravado com um nome e encontrado por outro — e o revisor da Apple digita
 * "Denilson" e não acha nada.
 */
const ACENTOS = 'áàâãäéèêëíìîïóòôõöúùûüç';
const SIMPLES = 'aaaaaeeeeiiiiooooouuuuc';
function normalizeForSearch(value) {
  let r = String(value).toLowerCase();
  for (let i = 0; i < ACENTOS.length; i++) r = r.split(ACENTOS[i]).join(SIMPLES[i]);
  return r;
}
const soDigitos = (t) => String(t).replace(/[^0-9]/g, '');
const reais = (centavos) => (centavos / 100).toLocaleString('pt-BR', { minimumFractionDigits: 2 });

/** Segunda-feira da semana desejada, às 00:00 no fuso da máquina. */
function segundaFeira(offsetSemanas) {
  const hoje = new Date();
  const d = new Date(hoje.getFullYear(), hoje.getMonth(), hoje.getDate());
  // getDay(): 0 = domingo. Domingo conta como fim da semana anterior.
  d.setDate(d.getDate() - ((d.getDay() + 6) % 7) + offsetSemanas * 7);
  return d;
}

function horasAtras(h) {
  const d = new Date();
  d.setHours(d.getHours() - h);
  return d;
}

function diasAtras(n) {
  const d = new Date();
  d.setDate(d.getDate() - n);
  return d;
}

/**
 * Uma data dentro de um mês passado. O dia é limitado ao dia de hoje
 * quando o mês é o corrente, senão o "histórico" teria pagamento com data
 * no futuro — que o gráfico do Financeiro somaria num mês que ainda não
 * aconteceu.
 */
function diaDoMes(mesAtras, dia) {
  const hoje = new Date();
  const alvo = new Date(hoje.getFullYear(), hoje.getMonth() - mesAtras, 1);
  const ultimoDia = new Date(alvo.getFullYear(), alvo.getMonth() + 1, 0).getDate();
  let d = Math.min(dia, ultimoDia);
  if (mesAtras === 0) d = Math.min(d, hoje.getDate());
  return new Date(alvo.getFullYear(), alvo.getMonth(), d, 15, 0, 0);
}

const nomeDoCliente = (id) => (CLIENTES.find((c) => c.id === id) || {}).name || '';
const DIAS = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];
const item = (desc, qtd, unit, centavos) => ({
  description: desc, quantity: qtd, unit, unitPriceCents: centavos,
});
const somaItens = (itens) => itens.reduce((s, i) => s + Math.round(i.quantity * i.unitPriceCents), 0);

// --------------------------------------------------------- os orçamentos

/**
 * Orçamentos e solicitações, em `providers/{uid}/budgets`.
 *
 * A tela "Solicitações" do prestador é, no banco, um orçamento com
 * `status: pendente` e `clientUid` preenchido — ou seja, um pedido que
 * chegou do marketplace e ainda não foi respondido (ver `BudgetStatus`).
 * Um orçamento SEM `status` e SEM `clientUid` é o criado à mão pelo
 * prestador pra um cliente do caderno dele, e não aparece em Solicitações.
 * A lista abaixo tem os dois tipos de propósito, pras duas telas terem
 * conteúdo.
 */
function montarOrcamentos(clienteUid) {
  return [
    {
      id: 'demo-orc-solicitacao-1',
      status: 'pendente',
      clientUid: clienteUid, // conta de verdade — a Marina
      customerId: 'demo-cli-marina',
      customerName: 'Marina Doring',
      clientPhone: CLIENTE.whatsapp,
      addressText: 'Av. Centenário, 1200 — Centro, Criciúma/SC',
      requestDescription:
        'Meu chuveiro parou de esquentar ontem à noite. O disjuntor não desarmou. ' +
        'Consegue dar uma olhada essa semana?',
      preferredDate: 'Segunda ou terça, de tarde',
      criadoHorasAtras: 3,
      naoLidasPrestador: 1,
      itens: [],
    },
    {
      id: 'demo-orc-solicitacao-2',
      status: 'pendente',
      clientUid: 'demo-uid-carlos',
      customerName: 'Carlos Zanette',
      clientPhone: '(48) 98888-0006',
      addressText: 'Rua Manoel Gaya, 310 — Santa Bárbara, Criciúma/SC',
      requestDescription:
        'Duas tomadas da cozinha pararam de funcionar depois de uma queda de energia.',
      preferredDate: 'Qualquer dia pela manhã',
      criadoHorasAtras: 27,
      naoLidasPrestador: 2,
      itens: [],
    },
    {
      id: 'demo-orc-enviado',
      status: 'enviado',
      clientUid: 'demo-uid-lucia',
      customerName: 'Lúcia Fernandes',
      clientPhone: '(48) 98888-0007',
      addressText: 'Rua Henrique Lage, 88 — Michel, Criciúma/SC',
      requestDescription: 'Quero trocar toda a iluminação da sala e da cozinha por LED.',
      criadoDiasAtras: 2,
      itens: [
        item('Instalação de luminária de embutir (fornecimento do cliente)', 8, 'un', 4500),
        item('Passagem de fiação nova até o ponto de comando', 1, 'serviço', 32000),
        item('Instalação de dimmer', 2, 'un', 9000),
      ],
    },
    {
      id: 'demo-orc-aprovado',
      status: 'aprovado',
      clientUid: 'demo-uid-rafael',
      customerName: 'Rafael Minatto',
      clientPhone: '(48) 98888-0008',
      addressText: 'Rua Pascoal Meller, 415 — Universitário, Criciúma/SC',
      requestDescription: 'Preciso de um ponto novo pro ar-condicionado do quarto.',
      criadoDiasAtras: 4,
      itens: [
        item('Ponto exclusivo 20A com disjuntor dedicado', 1, 'serviço', 38000),
        item('Eletroduto e cabeamento (até 6 m)', 1, 'serviço', 14000),
      ],
    },
    {
      id: 'demo-orc-aceito',
      status: 'aceito',
      clientUid: 'demo-uid-michel',
      customerId: 'demo-cli-michel',
      customerName: 'Michel Búrigo',
      clientPhone: '(48) 98888-0002',
      addressText: 'Rua São José, 45 — Próspera, Criciúma/SC',
      requestDescription: 'Revisão elétrica completa antes de alugar a casa.',
      criadoDiasAtras: 8,
      // Amarrado ao compromisso de terça-feira da Agenda: o aceite final é
      // o que lança o serviço na agenda (ver BudgetsRepository.acceptFinal),
      // então deixar os dois sem ligação mostraria um estado que o app
      // nunca produz sozinho.
      agendaId: 'demo-apt-3',
      serviceStatus: 'novo',
      itens: [
        item('Revisão geral do quadro e dos circuitos', 1, 'serviço', 45000),
        item('Substituição de tomadas antigas', 12, 'un', 3500),
        item('Laudo de conformidade', 1, 'serviço', 18000),
      ],
    },
    {
      id: 'demo-orc-manual',
      // Sem `status` e sem `clientUid`: orçamento criado à mão pelo
      // prestador, que é o outro caminho do módulo Orçamentos.
      customerId: 'demo-cli-atlantico',
      customerName: 'Ed. Atlântico',
      addressText: 'Rua Anita Garibaldi, 830 — Centro, Criciúma/SC',
      observations:
        'Valores válidos por 15 dias. Material elétrico incluso; andaime por conta do condomínio.',
      criadoDiasAtras: 1,
      itens: [
        item('Quadro de distribuição 24 disjuntores — 2 andares', 2, 'un', 68000),
        item('Disjuntor DR 40A', 4, 'un', 12500),
        item('Mão de obra de instalação e certificação', 1, 'serviço', 42000),
      ],
      descontoCents: 10000,
    },
  ];
}

// ------------------------------------------------------------------ main

/** Cria a conta se não existir, redefine a senha se já existir. */
async function garantirConta(auth, { email, nome }) {
  try {
    const user = await auth.getUserByEmail(email);
    if (GRAVAR) {
      await auth.updateUser(user.uid, { password: SENHA, displayName: nome, emailVerified: true });
    }
    return { uid: user.uid, novo: false };
  } catch (e) {
    if (e.code !== 'auth/user-not-found') throw e;
    if (!GRAVAR) return { uid: `(uid de ${email})`, novo: true };
    const user = await auth.createUser({
      email,
      password: SENHA,
      displayName: nome,
      emailVerified: true, // não há caixa de entrada pra confirmar
    });
    return { uid: user.uid, novo: true };
  }
}

async function main() {
  const chave = process.argv[2];
  if (!chave || chave.startsWith('--')) {
    console.error('uso: node scripts/criar_conta_demo.js chave.json [--semana N] [--limpar] [--gravar]');
    process.exit(1);
  }
  if (!fs.existsSync(chave)) {
    console.error(`não achei a chave em ${chave}`);
    process.exit(1);
  }

  admin.initializeApp({ credential: admin.credential.cert(require(path.resolve(chave))) });
  const db = admin.firestore();
  const auth = admin.auth();

  console.log(LIMPAR ? '>>> MODO: limpar <<<' : '>>> MODO: criar/atualizar <<<');
  console.log(GRAVAR ? '>>> GRAVANDO <<<' : '>>> simulação (nada será gravado) <<<');
  console.log('');

  const prestador = await garantirConta(auth, PRESTADOR);
  const cliente = await garantirConta(auth, CLIENTE);
  console.log(`prestador: ${PRESTADOR.email}  ${prestador.novo ? '(será criada)' : `(já existe — uid ${prestador.uid})`}`);
  console.log(`cliente:   ${CLIENTE.email}  ${cliente.novo ? '(será criada)' : `(já existe — uid ${cliente.uid})`}`);

  const uid = prestador.uid;
  const providerRef = db.collection('providers').doc(uid);
  const listingRef = db.collection('providerDirectory').doc(uid);

  if (LIMPAR) {
    console.log('\nVOU APAGAR:');
    console.log(`   providerDirectory/${uid} (com as avaliações)`);
    console.log(`   providers/${uid} (com clientes, compromissos, serviços e orçamentos)`);
    console.log('\nAs contas no Auth e os clients/{uid} continuam.');
    if (!GRAVAR) {
      console.log('\nnada foi gravado. rode de novo com --gravar.');
      return;
    }
    await db.recursiveDelete(listingRef);
    await db.recursiveDelete(providerRef);
    console.log('\npronto. a conta demo voltou a ser só cliente.');
    return;
  }

  const orcamentos = montarOrcamentos(cliente.uid);

  // --- prévia

  const inicio = segundaFeira(SEMANA);
  console.log(`\nAgenda: semana de ${inicio.toLocaleDateString('pt-BR')}` +
    (SEMANA === 0 ? ' (semana atual)' : ` (${SEMANA} semana(s) à frente)`));
  for (const a of AGENDA) {
    const h = `${String(a.hora).padStart(2, '0')}:${String(a.min).padStart(2, '0')}`;
    console.log(`   ${DIAS[a.dia]} ${h}  ${a.titulo} — ${nomeDoCliente(a.cliente)}`);
  }

  console.log('\nFinanceiro:');
  let totalGeral = 0;
  for (const mes of SERVICOS) {
    const soma = mes.itens.reduce((s, [, , v]) => s + v, 0);
    totalGeral += soma;
    const rotulo = diaDoMes(mes.mesAtras, 15).toLocaleDateString('pt-BR', { month: 'long', year: 'numeric' });
    console.log(`   ${rotulo.padEnd(20)} R$ ${reais(soma)}  (${mes.itens.length} serviços)`);
  }
  console.log(`   ${'total'.padEnd(20)} R$ ${reais(totalGeral)}`);

  const pendentes = orcamentos.filter((o) => o.status === 'pendente');
  console.log(`\nOrçamentos (${orcamentos.length}), sendo ${pendentes.length} em Solicitações:`);
  for (const o of orcamentos) {
    const total = somaItens(o.itens) - (o.descontoCents || 0);
    const rotulo = o.status ? o.status : 'manual (sem status)';
    console.log(`   ${rotulo.padEnd(22)} ${o.customerName.padEnd(18)} ${total > 0 ? 'R$ ' + reais(total) : '—'}`);
  }

  const somaEstrelas = AVALIACOES.reduce((s, a) => s + a.estrelas, 0);
  const media = somaEstrelas / AVALIACOES.length;
  console.log(`\nAvaliações: ${AVALIACOES.length}, média ${media.toFixed(2).replace('.', ',')}`);
  console.log('   (o agregado da vitrine é calculado dessa lista — nunca escrito à mão)');

  console.log(`\nVitrine: ${PRESTADOR.nome} — Eletricista — ${PRESTADOR.cidadesAtendidas.join(' · ')} — visible: true`);

  if (!GRAVAR) {
    console.log('\nnada foi gravado. rode de novo com --gravar.');
    return;
  }

  const agora = admin.firestore.FieldValue.serverTimestamp();
  const ts = (d) => admin.firestore.Timestamp.fromDate(d);

  // --- lado cliente das duas contas
  //
  // `termsAcceptedAt` gravado à mão porque estas contas não passam pela
  // tela de cadastro, que é onde a caixa dos Termos de Uso é marcada (ver
  // TermsAcceptanceCheckbox). Sem isso, as contas de demonstração seriam
  // justamente as únicas do app sem registro de aceite — e são as que a
  // Apple vai abrir.
  for (const [conta, dados] of [[prestador, PRESTADOR], [cliente, CLIENTE]]) {
    await db.collection('clients').doc(conta.uid).set({
      name: dados.nome,
      email: dados.email,
      whatsapp: dados.whatsapp,
      addressCity: dados.cidade,
      addressState: dados.uf,
      termsAcceptedAt: agora,
      updatedAt: agora,
      createdAt: agora,
    }, { merge: true });
  }

  // --- favoritos da Marina
  //
  // `clients/{uid}/favorites/{listingId}` é só um ponteiro pro id do
  // diretório (ver FavoritesRepository) — nada dos dados do prestador é
  // copiado. Sem isso a aba Favoritos do cliente abre vazia, que é
  // justamente uma das telas que o revisor vai tocar.
  await db.collection('clients').doc(cliente.uid)
    .collection('favorites').doc(uid)
    .set({ addedAt: ts(diasAtras(6)) }, { merge: true });

  // --- lado prestador (é a existência deste documento que liga o gate)
  await providerRef.set({
    name: PRESTADOR.nome,
    email: PRESTADOR.email,
    whatsapp: PRESTADOR.whatsapp,
    category: PRESTADOR.categoria,
    categories: [PRESTADOR.categoria],
    city: PRESTADOR.cidade,
    state: PRESTADOR.uf,
    addressCity: PRESTADOR.cidade,
    addressState: PRESTADOR.uf,
    bio: PRESTADOR.bio,
    updatedAt: agora,
    createdAt: agora,
  }, { merge: true });

  // --- vitrine pública
  //
  // `visible: true` não é detalhe: é filtro de SERVIDOR na busca (ver
  // ProviderDirectoryRepository.search) e é ele que faz os selos
  // "Verificado" e "Responde rápido" aparecerem no card — os dois dependem
  // de isVerifiedSubscriber, que é claimed && visible != false.
  const cidadesNormalizadas = [...new Set(
    PRESTADOR.cidadesAtendidas.map((c) => normalizeForSearch(c.split('/')[0].trim())),
  )];
  await listingRef.set({
    name: PRESTADOR.nome,
    nameNormalized: normalizeForSearch(PRESTADOR.nome),
    category: PRESTADOR.categoria,
    categories: [PRESTADOR.categoria],
    city: PRESTADOR.cidade,
    cityNormalized: normalizeForSearch(PRESTADOR.cidade),
    state: PRESTADOR.uf,
    cidadesAtendidas: PRESTADOR.cidadesAtendidas,
    cidadesNormalizadas,
    bio: PRESTADOR.bio,
    whatsapp: PRESTADOR.whatsapp,
    phoneNormalized: soDigitos(PRESTADOR.whatsapp),
    claimed: true,
    providerUid: uid,
    visible: true,
    // Calculados da lista de avaliações logo abaixo — ver AVALIACOES.
    ratingAverage: Number(media.toFixed(2)),
    ratingCount: AVALIACOES.length,
    updatedAt: agora,
    createdAt: agora,
  }, { merge: true });

  // --- avaliações (é o que a lista do perfil lê de verdade)
  const loteAvaliacoes = db.batch();
  for (const a of AVALIACOES) {
    const docId = a.id === 'MARINA' ? cliente.uid : a.id;
    loteAvaliacoes.set(listingRef.collection('ratings').doc(docId), {
      stars: a.estrelas,
      comment: a.comentario,
      clientName: a.nome,
      createdAt: ts(diasAtras(a.diasAtras)),
    }, { merge: true });
  }
  await loteAvaliacoes.commit();

  // --- clientes
  const loteClientes = db.batch();
  for (const c of CLIENTES) {
    loteClientes.set(providerRef.collection('customers').doc(c.id), {
      name: c.name,
      whatsapp: c.whatsapp,
      phone: c.whatsapp,
      addressCity: c.city,
      addressState: PRESTADOR.uf,
      ...(c.id === 'demo-cli-marina' ? { clientUid: cliente.uid, email: CLIENTE.email } : {}),
      updatedAt: agora,
      createdAt: agora,
    }, { merge: true });
  }
  await loteClientes.commit();

  // --- agenda da semana
  const loteAgenda = db.batch();
  for (const a of AGENDA) {
    const quando = new Date(inicio);
    quando.setDate(quando.getDate() + a.dia);
    quando.setHours(a.hora, a.min, 0, 0);
    loteAgenda.set(providerRef.collection('appointments').doc(a.id), {
      type: a.tipo,
      status: 'agendado',
      scheduledAt: ts(quando),
      durationMinutes: a.dur,
      customerId: a.cliente,
      customerName: nomeDoCliente(a.cliente),
      addressText: a.endereco,
      observations: a.titulo,
      updatedAt: agora,
      createdAt: agora,
    }, { merge: true });
  }
  await loteAgenda.commit();

  // --- orçamentos e solicitações
  const loteOrcamentos = db.batch();
  for (const o of orcamentos) {
    const quando = o.criadoHorasAtras != null
      ? horasAtras(o.criadoHorasAtras)
      : diasAtras(o.criadoDiasAtras || 1);
    const agendado = o.agendaId ? AGENDA.find((a) => a.id === o.agendaId) : null;
    let agendadoEm = null;
    if (agendado) {
      agendadoEm = new Date(inicio);
      agendadoEm.setDate(agendadoEm.getDate() + agendado.dia);
      agendadoEm.setHours(agendado.hora, agendado.min, 0, 0);
    }
    loteOrcamentos.set(providerRef.collection('budgets').doc(o.id), {
      customerName: o.customerName,
      ...(o.customerId ? { customerId: o.customerId } : {}),
      ...(o.addressText ? { addressText: o.addressText } : {}),
      date: ts(quando),
      items: o.itens,
      discountCents: o.descontoCents || 0,
      ...(o.observations ? { observations: o.observations } : {}),
      ...(o.status ? { status: o.status } : {}),
      ...(o.clientUid ? { clientUid: o.clientUid } : {}),
      ...(o.clientPhone ? { clientPhone: o.clientPhone } : {}),
      // `providerUid` como CAMPO, não só inferido do caminho: é o que a
      // regra de `list` do firestore.rules usa (ver o comentário longo em
      // Budget.providerUid). Sem ele, a consulta do cliente é negada.
      providerUid: uid,
      providerDirectoryId: uid,
      providerName: PRESTADOR.nome,
      category: PRESTADOR.categoria,
      ...(o.requestDescription ? { requestDescription: o.requestDescription } : {}),
      ...(o.preferredDate ? { preferredDate: o.preferredDate } : {}),
      ...(agendadoEm ? {
        serviceScheduledAt: ts(agendadoEm),
        serviceDurationMinutes: agendado.dur,
        appointmentId: o.agendaId,
      } : {}),
      ...(o.serviceStatus ? { serviceStatus: o.serviceStatus } : {}),
      ...(o.naoLidasPrestador ? {
        naoLidasPrestador: o.naoLidasPrestador,
        ultimaMensagemEm: ts(quando),
      } : {}),
      archivedByClient: false,
      archivedByProvider: false,
      revisionNumber: 0,
      createdAt: ts(quando),
      updatedAt: ts(quando),
    }, { merge: true });
  }
  await loteOrcamentos.commit();

  // --- serviços concluídos (o que alimenta o Financeiro)
  //
  // `paidAt` E `status: concluido`: a tela do Financeiro soma pelo
  // pagamento, e o Kanban de Serviços lê o status. Gravar só um dos dois
  // deixaria uma das telas mentindo sobre a outra.
  const diasDoMes = [8, 16, 24];
  const loteJobs = db.batch();
  for (const mes of SERVICOS) {
    mes.itens.forEach(([titulo, clienteId, centavos], i) => {
      const quando = diaDoMes(mes.mesAtras, diasDoMes[i] || 20);
      loteJobs.set(providerRef.collection('jobs').doc(`demo-job-m${mes.mesAtras}-${i}`), {
        status: 'concluido',
        customerName: nomeDoCliente(clienteId),
        totalCents: centavos,
        providerUid: uid,
        providerName: PRESTADOR.nome,
        category: PRESTADOR.categoria,
        addressText: titulo,
        archived: false,
        createdAt: ts(quando),
        updatedAt: ts(quando),
        paidAt: ts(quando),
        completedAt: ts(quando),
      }, { merge: true });
    });
  }
  await loteJobs.commit();

  console.log('\n✅ pronto.\n');
  console.log(`   prestador:  ${PRESTADOR.email} / ${SENHA}   (uid ${prestador.uid})`);
  console.log(`   cliente:    ${CLIENTE.email} / ${SENHA}   (uid ${cliente.uid})`);
  console.log('\nSe alguma delas já estava aberta em algum aparelho, saia e entre de');
  console.log('novo: o `isProvider` fica em cache na sessão (ver');
  console.log('AuthController.bootstrap) e só é relido ao entrar.');
  console.log('\nDepois que o app for aprovado, esconda a vitrine pra essa conta não');
  console.log('aparecer pra clientes de verdade:');
  console.log(`   node scripts/remover_prestador.js ${chave} ${PRESTADOR.email} --so-vitrine --gravar`);
}

main().catch((e) => {
  console.error('\nfalhou:', e);
  process.exit(1);
});
