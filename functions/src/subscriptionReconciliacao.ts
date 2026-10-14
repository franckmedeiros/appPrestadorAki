/**
 * Reconciliação diária das assinaturas — a rede de segurança que faltava.
 *
 * Hoje o corte de um prestador que parou de pagar depende inteiramente de
 * a notificação da loja chegar: RTDN do Google (`processarNotificacaoPlay`)
 * ou App Store Server Notifications V2 (`processarNotificacaoApple`).
 * Quando ela chega, o sistema reage certo. Quando ela NÃO chega — e isso
 * acontece: URL desconfigurada (foi o caso em produção até hoje), deploy
 * fora do ar na hora do POST, tópico Pub/Sub com permissão quebrada,
 * retry esgotado — ninguém nunca mais olha pra aquele prestador, e ele
 * fica ativo de graça pra sempre. Falha ABERTO, que é o pior jeito de
 * falhar num gate de pagamento.
 *
 * Esta função fecha isso: uma vez por dia ela varre os prestadores ativos
 * e, pra cada um cuja validade já passou, RE-PERGUNTA à própria loja qual
 * é o estado verdadeiro e aplica — pelo mesmo `aplicarEstadoNormalizado`
 * que as notificações usam. Ou seja: nada de política nova aqui, só uma
 * segunda chance de executar a política que já existe.
 *
 * Por que re-perguntar em vez de cortar pela data: carência. Em
 * BILLING_GRACE_PERIOD (os dois lados tratam como ativa), a data de
 * expiração JÁ passou mas a pessoa ainda tem direito de uso enquanto a
 * loja tenta cobrar de novo. Cortar pela data sozinha derrubaria quem só
 * teve o cartão recusado e vai pagar em dois dias. A loja é quem sabe.
 *
 * O caminho também conserta o sentido inverso: quem está pagando mas ficou
 * marcado como inativo por uma notificação perdida volta a aparecer.
 *
 * ÓRFÃOS: prestadores sem nenhum dado de assinatura (`subscriptionStore`
 * ausente) são contas criadas fora do paywall — pelo caminho de teste
 * `AuthController.becomeProvider`, ou de antes do gate existir. Eles estão
 * ativos na busca sem nunca ter pago. Esta função NÃO os corta sozinha, de
 * propósito: pode haver conta sua, de teste ou de cortesia, e derrubar
 * silenciosamente a listagem de alguém é pior do que deixar passar mais um
 * dia. Ela os LISTA no relatório, e você decide (ver `ORFAOS_INATIVAR`).
 */

import { onSchedule } from 'firebase-functions/v2/scheduler';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions';
import { FieldValue, Timestamp } from 'firebase-admin/firestore';
import { db } from './lib/admin';
import {
  aplicarEstadoNormalizado,
  EstadoNormalizado,
  consultarEstadoGoogle,
  playServiceAccountKey,
} from './subscription';
import { consultarEstadoApple, appleAppStoreConnectKey } from './subscriptionApple';

/**
 * Ligar isto faz a varredura também desativar os prestadores órfãos
 * (sem `subscriptionStore`). Deixe `false` até ter olhado o relatório
 * pelo menos uma vez e confirmado que a lista não tem ninguém que
 * deveria continuar ativo.
 */
const ORFAOS_INATIVAR = false;

/**
 * Margem depois da data de expiração antes de sequer perguntar à loja.
 * Serve só pra não gastar chamada de API com quem acabou de renovar e
 * ainda não teve o `subscriptionExpiresAt` atualizado pela notificação —
 * a renovação costuma chegar em minutos. Não é período de carência: a
 * carência quem concede é a loja, e vem na resposta dela.
 */
const MARGEM_HORAS = 6;

/** Quantos prestadores processar por execução, pra não estourar o tempo da função. */
const LIMITE_POR_EXECUCAO = 400;

interface Relatorio {
  verificados: number;
  semMudanca: number;
  desativados: number;
  reativados: number;
  orfaos: string[];
  semToken: string[];
  erros: { uid: string; erro: string }[];
}

/**
 * Acha o comprovante guardado pra este uid em `assinaturasVerificadas`.
 * O documento é chaveado pelo token (purchaseToken do Google, ou
 * `apple:{originalTransactionId}`), então a busca por uid é uma query.
 * Se houver mais de um (trocou de loja, reinstalou), fica com o mais
 * recente — é o que vale.
 */
async function acharComprovante(
  uid: string,
): Promise<{ id: string; loja: 'google' | 'apple' } | null> {
  const snap = await db.collection('assinaturasVerificadas').where('uid', '==', uid).get();
  if (snap.empty) return null;

  const candidatos = snap.docs
    .map((d) => {
      const dados = d.data();
      const atualizadoEm: Timestamp | undefined = dados.atualizadoEm;
      // `loja` passou a ser gravada explicitamente; pros documentos
      // antigos, o prefixo do id diz de qual loja é.
      const loja: 'google' | 'apple' =
        dados.loja === 'apple' || d.id.startsWith('apple:') ? 'apple' : 'google';
      return { id: d.id, loja, quando: atualizadoEm?.toMillis() ?? 0 };
    })
    .sort((a, b) => b.quando - a.quando);

  return { id: candidatos[0].id, loja: candidatos[0].loja };
}

/** Pergunta à loja certa qual é o estado real desta assinatura. */
async function consultarEstadoNaLoja(comprovante: {
  id: string;
  loja: 'google' | 'apple';
}): Promise<EstadoNormalizado> {
  if (comprovante.loja === 'apple') {
    // O id guardado é `apple:{originalTransactionId}` — tira o prefixo.
    return consultarEstadoApple(comprovante.id.replace(/^apple:/, ''));
  }
  return consultarEstadoGoogle(comprovante.id);
}

async function reconciliar(): Promise<Relatorio> {
  const relatorio: Relatorio = {
    verificados: 0,
    semMudanca: 0,
    desativados: 0,
    reativados: 0,
    orfaos: [],
    semToken: [],
    erros: [],
  };

  // Varredura simples da coleção inteira de prestadores ativos. Na
  // escala atual (dezenas) isso é barato e dispensa índice composto. Se
  // um dia passar de alguns milhares, troque por uma query indexada em
  // `subscriptionExpiresAt` + paginação por cursor — mas aí os órfãos
  // (que não têm o campo) precisam de uma passada separada, porque o
  // Firestore não devolve documentos sem o campo num filtro de
  // desigualdade.
  const ativos = await db.collection('providers').where('listingStatus', '==', 'active').get();

  const limite = Timestamp.fromMillis(Date.now() - MARGEM_HORAS * 60 * 60 * 1000);
  let processados = 0;

  for (const doc of ativos.docs) {
    if (processados >= LIMITE_POR_EXECUCAO) {
      logger.warn(
        `Reconciliação parou no limite de ${LIMITE_POR_EXECUCAO} prestadores — ` +
          'os restantes entram na próxima execução.',
      );
      break;
    }

    const uid = doc.id;
    const dados = doc.data();

    // Órfão: ativo sem nenhum vínculo com uma loja.
    if (!dados.subscriptionStore) {
      relatorio.orfaos.push(uid);
      if (ORFAOS_INATIVAR) {
        processados += 1;
        await aplicarEstadoNormalizado(uid, {
          ativa: false,
          expiraEm: null,
          rawState: 'SEM_ASSINATURA',
          loja: 'google',
        });
        relatorio.desativados += 1;
      }
      continue;
    }

    // Teste grátis (sem loja): quem expira é `expirarTestesGratis`
    // (testeGratis.ts), de hora em hora — não há loja pra perguntar.
    if (dados.subscriptionStore === 'teste') {
      relatorio.semMudanca += 1;
      continue;
    }

    const expiraEm: Timestamp | null = dados.subscriptionExpiresAt ?? null;
    // Ainda dentro da validade conhecida: nada a perguntar.
    if (expiraEm && expiraEm.toMillis() > limite.toMillis()) {
      relatorio.semMudanca += 1;
      continue;
    }

    const comprovante = await acharComprovante(uid);
    if (!comprovante) {
      // Tem `subscriptionStore` mas nenhum comprovante guardado — não há
      // o que perguntar à loja. Não corta sozinho: entra no relatório.
      relatorio.semToken.push(uid);
      continue;
    }

    processados += 1;
    relatorio.verificados += 1;

    try {
      const estado = await consultarEstadoNaLoja(comprovante);
      const estavaAtiva = dados.listingStatus === 'active';
      await aplicarEstadoNormalizado(uid, estado);
      await db
        .collection('assinaturasVerificadas')
        .doc(comprovante.id)
        .set(
          { subscriptionState: estado.rawState, atualizadoEm: Timestamp.now() },
          { merge: true },
        );

      if (estado.ativa && !estavaAtiva) relatorio.reativados += 1;
      else if (!estado.ativa && estavaAtiva) {
        relatorio.desativados += 1;
        logger.info(
          `Reconciliação desativou ${uid} (loja: ${comprovante.loja}, estado: ${estado.rawState}) — ` +
            'a notificação dessa mudança nunca chegou.',
        );
      } else relatorio.semMudanca += 1;
    } catch (e) {
      const erro = e instanceof Error ? e.message : String(e);
      logger.error(`Reconciliação falhou para ${uid}`, e);
      relatorio.erros.push({ uid, erro });
    }
  }

  return relatorio;
}

/** Guarda o resultado pra dar pra olhar depois sem caçar log. */
async function gravarRelatorio(relatorio: Relatorio, origem: string): Promise<void> {
  await db.collection('relatoriosReconciliacao').add({
    ...relatorio,
    origem,
    executadoEm: FieldValue.serverTimestamp(),
  });
}

export const reconciliarAssinaturas = onSchedule(
  {
    schedule: '17 4 * * *',
    timeZone: 'America/Sao_Paulo',
    timeoutSeconds: 540,
    secrets: [playServiceAccountKey, appleAppStoreConnectKey],
  },
  async () => {
    const relatorio = await reconciliar();
    logger.info('Reconciliação diária concluída', relatorio);
    await gravarRelatorio(relatorio, 'agendada');
  },
);

/**
 * A mesma varredura, sob demanda. Serve pra conferir o efeito logo depois
 * de arrumar alguma configuração (como o URL de produção da Apple) sem
 * esperar até a madrugada, e é o que a futura página de admin vai chamar.
 *
 * Só para quem estiver em `admins/{uid}` — a varredura mexe na
 * visibilidade pública de todo mundo.
 */
export const reconciliarAssinaturasAgora = onCall(
  {
    timeoutSeconds: 540,
    secrets: [playServiceAccountKey, appleAppStoreConnectKey],
  },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Faça login primeiro.');
    const admin = await db.collection('admins').doc(request.auth.uid).get();
    if (!admin.exists) throw new HttpsError('permission-denied', 'Só administradores.');

    const relatorio = await reconciliar();
    await gravarRelatorio(relatorio, `manual:${request.auth.uid}`);
    return relatorio;
  },
);
