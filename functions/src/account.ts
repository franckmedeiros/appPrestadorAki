/**
 * Exclusão de conta — exigida pela política da Google Play/App Store pra
 * apps que permitem criar conta. Mesmo objetivo do app Resenha (ver
 * lib/services/user_repository.dart:excluirContaEDados de lá), mas feito
 * aqui via Cloud Function em vez de client-side: `providers/{uid}` tem
 * várias subcoleções aninhadas — customers, appointments, budgets (com
 * versions/changeRequests), jobs, technicalVisits, locationSessions,
 * staff, ver DATA_MODEL.md — e `db.recursiveDelete` do Admin SDK apaga
 * tudo isso de uma vez sem precisar listar subcoleção por subcoleção na
 * mão nem se preocupar com o limite de 500 operações por batch do
 * Firestore.
 *
 * Chamada pelo app (UserProfileScreen/AuthController.deleteAccount). Não
 * pede senha: confia em `request.auth.uid`, que o Firebase já garante ser
 * um token válido de sessão. (O app chegou a reautenticar com a senha
 * antes de chamar isto aqui; essa etapa foi removida a pedido do Franck —
 * era uma camada extra de segurança, não um requisito técnico, já que
 * quem apaga a conta é o Admin SDK aqui no servidor, que não está sujeito
 * à exigência de "login recente" do lado do cliente.)
 *
 * Nota honesta sobre o que NÃO é apagado aqui de propósito:
 * `assinaturasVerificadas/{purchaseToken}` fica de fora — é histórico de
 * compra no Google Play, indexado pelo token da compra e não pelo uid,
 * mantido como registro de faturamento (igual a um Stripe que não some
 * com as faturas quando o cliente é excluído). E, se essa conta, como
 * CLIENTE, avaliou outros prestadores, essas avaliações continuam em
 * `providerDirectory/{outroId}/ratings/{uid}` — o documento não guarda
 * nenhum outro dado pessoal além da nota/comentário, então não entrou
 * nessa limpeza por enquanto; viraria uma varredura por collectionGroup
 * em todo o diretório só pra isso.
 *
 * Ordem importa: apaga os dados no Firestore PRIMEIRO, a conta do
 * Firebase Auth em si por ÚLTIMO — se a exclusão do Auth falhar no meio
 * do caminho, pelo menos não sobra nenhum dado órfão associado a um uid
 * que ainda existe.
 */
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { getAuth } from 'firebase-admin/auth';
import { logger } from 'firebase-functions';
import { db } from './lib/admin';

/**
 * Apaga em lotes todos os documentos que casam com uma query — usado pra
 * limpar os orçamentos que esta conta pediu, na capacidade de CLIENTE,
 * dentro da subcoleção `budgets` de OUTROS prestadores (ver
 * `collectionGroup('budgets')` abaixo) — não é coberto pelo
 * `db.recursiveDelete(providers/{uid})` acima, que só apaga o que está
 * DEBAIXO do próprio uid, não o que esta conta criou na árvore de outra
 * conta. Em lotes de 400 só por segurança (o limite de um batch do
 * Firestore é 500 operações), embora na prática o número de pedidos de
 * uma única conta deva ficar bem abaixo disso.
 */
async function apagarQuery(query: FirebaseFirestore.Query): Promise<void> {
  const snapshot = await query.get();
  if (snapshot.empty) return;

  const docs = snapshot.docs;
  for (let i = 0; i < docs.length; i += 400) {
    const batch = db.batch();
    for (const doc of docs.slice(i, i + 400)) {
      batch.delete(doc.ref);
    }
    await batch.commit();
  }
}

/**
 * Igual a [apagarQuery], mas apagando cada documento COM AS SUBCOLEÇÕES
 * dele.
 *
 * Por que existe: no Firestore, apagar um documento NÃO apaga o que está
 * debaixo dele — as subcoleções continuam vivas, agora penduradas num
 * documento que não existe mais, e não aparecem em lugar nenhum. O
 * `batch.delete` de cima faz exatamente isso.
 *
 * Isso passava despercebido enquanto os orçamentos que esta conta criou
 * na árvore de OUTROS prestadores não tinham nada debaixo. Hoje têm: a
 * conversa (`mensagens`, ver functions/src/messages.ts) e o histórico de
 * aditivos (`versions`). Sem isto, excluir a conta deixaria para trás as
 * mensagens que a pessoa escreveu — justamente o tipo de dado que uma
 * exclusão de conta precisa levar junto.
 *
 * `recursiveDelete` um por um em vez de um batch só: ele já faz o
 * trabalho em lotes internamente, com o próprio controle de paralelismo.
 */
async function apagarQueryComSubcolecoes(query: FirebaseFirestore.Query): Promise<void> {
  const snapshot = await query.get();
  for (const doc of snapshot.docs) {
    await db.recursiveDelete(doc.ref);
  }
}

/**
 * Roda UMA etapa da limpeza dizendo, no erro que chega no app, QUAL delas
 * falhou e com que código do Firestore.
 *
 * Antes as cinco etapas abaixo ficavam dentro de um `try` só, e qualquer
 * uma que quebrasse produzia a mesmíssima frase ("Não foi possível apagar
 * seus dados") — o Franck viu exatamente isso, e não dava pra saber se o
 * problema estava no cadastro de prestador, nos orçamentos espalhados em
 * outros prestadores ou na reserva de telefone sem ir atrás do log da
 * função. Nome da etapa e código (`failed-precondition`,
 * `deadline-exceeded`, `permission-denied`...) são diagnóstico, não dado
 * sensível: não dizem nada sobre outras contas.
 *
 * Continua valendo a regra de NUNCA usar o código 'internal' nem
 * 'unknown': o protocolo de Callable Functions descarta a mensagem nesses
 * dois e o app só recebe um "INTERNAL" opaco (reclamação antiga do
 * Franck). Com 'unavailable' a frase chega inteira.
 */
async function etapa(nome: string, uid: string, trabalho: () => Promise<void>): Promise<void> {
  try {
    await trabalho();
  } catch (error) {
    const codigo = (error as { code?: string | number } | null)?.code;
    logger.error('Falha ao apagar dados do Firestore na exclusão de conta', {
      uid,
      etapa: nome,
      codigo,
      error,
    });
    throw new HttpsError(
      'unavailable',
      `Não foi possível apagar seus dados na etapa "${nome}"` +
        `${codigo !== undefined ? ` (${codigo})` : ''}. Tente novamente.`,
    );
  }
}

export const excluirContaEDados = onCall(
  {
    // `recursiveDelete` varre subcoleção por subcoleção (customers,
    // appointments, budgets com versions/changeRequests, jobs,
    // technicalVisits, locationSessions, staff — ver DATA_MODEL.md), e
    // uma conta de prestador com histórico leva tempo. O padrão de uma
    // callable é 60s, apertado pra isso; 5 minutos é folga sem custo (só
    // se paga o tempo realmente usado).
    timeoutSeconds: 300,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Faça login primeiro.');
    }
    const uid = request.auth.uid;

    await etapa('cadastro de prestador', uid, () =>
      db.recursiveDelete(db.collection('providers').doc(uid)),
    );
    await etapa('perfil de cliente', uid, () =>
      db.recursiveDelete(db.collection('clients').doc(uid)),
    );
    // Perfil público no diretório de busca, se essa conta era prestador
    // com listagem reivindicada (ver ProviderDirectoryRepository), e as
    // avaliações que OUTROS clientes deixaram nele. Sem isso, o perfil
    // continuaria aparecendo na busca pra sempre, sem dono nenhum por
    // trás — foi exatamente o problema que o Franck percebeu ao testar
    // excluir e recriar a conta.
    await etapa('perfil público na busca', uid, () =>
      db.recursiveDelete(db.collection('providerDirectory').doc(uid)),
    );
    // Orçamentos que esta conta pediu, na capacidade de CLIENTE, na
    // subcoleção de OUTROS prestadores (ver Budget.clientUid/
    // BudgetRequestsRepository) — os que esta conta criou como
    // PRESTADOR, na própria subcoleção, já foram embora junto com
    // `db.recursiveDelete(providers/{uid})` acima.
    // Com subcoleções: cada um desses orçamentos pode ter a conversa
    // (`mensagens`) e o histórico de aditivos (`versions`) debaixo dele —
    // ver `apagarQueryComSubcolecoes`.
    await etapa('orçamentos em outros prestadores', uid, () =>
      apagarQueryComSubcolecoes(db.collectionGroup('budgets').where('clientUid', '==', uid)),
    );
    // Reserva de telefone único (ver `phoneIndex` no firestore.rules e
    // AuthController.register). Faltava aqui, e era um bug de verdade: o
    // documento é indexado pelo TELEFONE (não pelo uid), então não é
    // alcançado por nenhum dos recursiveDelete acima. Sem apagar, o
    // telefone continuava "reservado" pra sempre por uma conta que não
    // existe mais, e tentar recadastrar com o mesmo número dava "Esse
    // telefone já está cadastrado em outra conta" — exatamente o que o
    // Franck viu ao excluir e tentar criar a conta de novo.
    //
    // Busca por `clientUid` em vez de calcular o id a partir do telefone
    // do documento do cliente: aqui em cima o `clients/{uid}` JÁ foi
    // apagado, e de qualquer forma o vínculo confiável é este campo.
    await etapa('reserva de telefone', uid, () =>
      apagarQuery(db.collection('phoneIndex').where('clientUid', '==', uid)),
    );

    // É esta chamada que libera o E-MAIL pra ser usado num cadastro novo —
    // não existe nenhum índice de e-mail no Firestore, quem garante que um
    // e-mail só pertence a uma conta é o próprio Firebase Auth. Se ela
    // falhar, o e-mail continua ocupado; por isso o erro sobe pro app em
    // vez de ser engolido.
    try {
      await getAuth().deleteUser(uid);
      logger.info('Conta removida do Firebase Auth', { uid });
    } catch (error) {
      // `user-not-found` não é falha: significa que a conta já não existia
      // (ex.: uma tentativa anterior chegou até aqui e só a resposta se
      // perdeu). Tratar como erro faria o app mostrar "houve um problema
      // ao remover o login" numa exclusão que, na prática, está completa.
      const code = (error as { code?: string } | null)?.code;
      if (code === 'auth/user-not-found') {
        logger.info('Conta já não existia no Firebase Auth na exclusão', { uid });
        return { ok: true };
      }
      logger.error('Falha ao apagar usuário do Firebase Auth na exclusão de conta', { uid, error });
      throw new HttpsError(
        'unavailable',
        'Seus dados foram apagados, mas houve um problema ao remover o login. Fale com o suporte.',
      );
    }

    return { ok: true };
  },
);
