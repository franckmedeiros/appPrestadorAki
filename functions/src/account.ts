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
 * Chamada pelo app (UserProfileScreen/AuthController.deleteAccount) só
 * DEPOIS de reautenticar com a senha atual no cliente — essa function não
 * pede senha de novo, só confia em `request.auth.uid` (o Firebase já
 * garante que é um token válido de sessão).
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
 * `serviceRequests`, que é uma coleção de nível raiz, fora de `/providers`
 * e `/clients`, então não é coberta pelo `db.recursiveDelete` acima. Em
 * lotes de 400 só por segurança (o limite de um batch do Firestore é 500
 * operações), embora na prática o número de solicitações de uma única
 * conta deva ficar bem abaixo disso.
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

export const excluirContaEDados = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Faça login primeiro.');
  }
  const uid = request.auth.uid;

  try {
    await db.recursiveDelete(db.collection('providers').doc(uid));
    await db.recursiveDelete(db.collection('clients').doc(uid));
    // Perfil público no diretório de busca, se essa conta era prestador
    // com listagem reivindicada (ver ProviderDirectoryRepository), e as
    // avaliações que OUTROS clientes deixaram nele. Sem isso, o perfil
    // continuaria aparecendo na busca pra sempre, sem dono nenhum por
    // trás — foi exatamente o problema que o Franck percebeu ao testar
    // excluir e recriar a conta.
    await db.recursiveDelete(db.collection('providerDirectory').doc(uid));
    // Pedidos de orçamento do marketplace (coleção raiz `serviceRequests`,
    // ver ServiceRequestsRepository) em que essa conta era o cliente OU
    // o prestador.
    await apagarQuery(db.collection('serviceRequests').where('clientUid', '==', uid));
    await apagarQuery(db.collection('serviceRequests').where('providerUid', '==', uid));
  } catch (error) {
    logger.error('Falha ao apagar dados do Firestore na exclusão de conta', { uid, error });
    throw new HttpsError('internal', 'Não foi possível apagar seus dados. Tente novamente.');
  }

  try {
    await getAuth().deleteUser(uid);
  } catch (error) {
    logger.error('Falha ao apagar usuário do Firebase Auth na exclusão de conta', { uid, error });
    throw new HttpsError(
      'internal',
      'Seus dados foram apagados, mas houve um problema ao remover o login. Fale com o suporte.',
    );
  }

  return { ok: true };
});
