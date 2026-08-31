/**
 * Exclusão de conta — exigida pela política da Google Play/App Store pra
 * apps que permitem criar conta (mesmo desenho do app Resenha, ver
 * lib/services/user_repository.dart:excluirContaEDados de lá — lá é feito
 * direto do cliente, aqui preferimos uma Cloud Function porque
 * `providers/{uid}` tem várias subcoleções aninhadas (customers,
 * appointments, budgets com versions/changeRequests, jobs,
 * technicalVisits, locationSessions, staff — ver DATA_MODEL.md), e
 * `db.recursiveDelete` do Admin SDK apaga tudo isso de uma vez sem
 * precisar listar subcoleção por subcoleção na mão nem se preocupar com
 * o limite de 500 operações por batch do Firestore).
 *
 * Chamada pelo app (UserProfileScreen/AuthController.deleteAccount) só
 * DEPOIS de reautenticar com a senha atual no cliente — essa function não
 * pede senha de novo, só confia em `request.auth.uid` (o Firebase já
 * garante que é um token válido de sessão).
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

export const excluirContaEDados = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Faça login primeiro.');
  }
  const uid = request.auth.uid;

  try {
    await db.recursiveDelete(db.collection('providers').doc(uid));
    await db.recursiveDelete(db.collection('clients').doc(uid));
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
