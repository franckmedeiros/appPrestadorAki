/**
 * Central de notificações do marketplace (sininho — ver
 * lib/widgets/notification_bell.dart) + push de verdade via FCM. Duas
 * pontas do fluxo de pedido de orçamento (ver DATA_MODEL.md e
 * lib/features/budgets/models/budget.dart — `BudgetStatus`):
 *
 *  - onBudgetRequestCreated: dispara ao CRIAR um orçamento com
 *    `status == 'pendente'` E `clientUid` preenchido (ou seja, veio de um
 *    pedido de cliente pelo marketplace, não de um orçamento manual do
 *    prestador) — avisa o PRESTADOR dono da subcoleção.
 *
 *  - onBudgetStatusChanged: dispara quando o campo `status` muda — avisa
 *    quem precisa agir na etapa seguinte (ver `BudgetStatus`): o cliente
 *    quando o prestador envia ou aceita, o prestador quando o cliente
 *    aprova ou recusa, o cliente quando o próprio prestador recusa.
 *
 * Antes disso essas duas pontas observavam uma coleção à parte,
 * `serviceRequests` — o Franck pediu pra tirar essa etapa do meio: o
 * pedido do cliente já nasce como um orçamento (ver commit que trouxe
 * essa mudança). Só a origem do gatilho mudou; o formato da notificação
 * continua o mesmo de antes.
 *
 * Toda notificação é gravada em `clients/{uid}/notifications` — MESMO
 * pra quem está sendo avisado na capacidade de PRESTADOR (conta
 * unificada, ver AuthController no app: todo uid tem um documento em
 * `clients/{uid}` independente de também ter um em `providers/{uid}`) —
 * é o mesmo uid que recebe o push, guardado em `clients/{uid}.fcmToken`
 * (ver NotificationService no Flutter), e é o que alimenta o sininho
 * dentro do app mesmo depois que o push já sumiu da barra do sistema.
 * Mesmo padrão já usado no app Resenha (functions/index.js de lá).
 *
 * Roda com privilégio de administrador (Admin SDK) — ignora
 * firestore.rules.
 */

import { onDocumentCreated, onDocumentUpdated } from 'firebase-functions/v2/firestore';
import { FieldValue } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';
import { logger } from 'firebase-functions';
import { db } from './lib/admin';

const messaging = getMessaging();

const NOTIFICATION_CHANNEL_ID = 'prestadoraki_avisos';

export interface NotificationInput {
  type: string;
  title: string;
  body: string;
  budgetId?: string;
}

/**
 * Grava o item na central de notificações do destinatário (`uid` — pode
 * ser o cliente ou o prestador, ver comentário do topo do arquivo) e, se
 * ele tiver um token FCM salvo, manda o push também. Nunca lança erro pra
 * fora — notificação é um "extra" sobre a operação principal (criar/
 * atualizar o orçamento), que não pode falhar por causa disso.
 */
export async function notify(uid: string, input: NotificationInput): Promise<void> {
  if (!uid) return;

  try {
    await db.collection('clients').doc(uid).collection('notifications').add({
      type: input.type,
      title: input.title,
      body: input.body,
      budgetId: input.budgetId ?? null,
      read: false,
      createdAt: FieldValue.serverTimestamp(),
    });
  } catch (e) {
    logger.warn('Falha ao gravar notificação na central', e);
  }

  try {
    const doc = await db.collection('clients').doc(uid).get();
    const token = doc.data()?.fcmToken;
    if (typeof token !== 'string' || token.length === 0) return;
    await messaging.send({
      token,
      notification: { title: input.title, body: input.body },
      data: {
        type: input.type,
        ...(input.budgetId ? { budgetId: input.budgetId } : {}),
      },
      android: { notification: { channelId: NOTIFICATION_CHANNEL_ID } },
    });
  } catch (e) {
    // Token inválido/expirado é comum (app desinstalado, dados do app
    // limpos, permissão negada etc.) — só registra no log, não faz a
    // função falhar. Caso real visto em produção: o prestador não recebia
    // o push (só a entrada no sininho) porque o token salvo tinha
    // apodrecido — e como nada aqui limpava esse token morto, toda
    // notificação seguinte ia continuar tentando o mesmo token pra
    // sempre, até a pessoa abrir o app de novo por acaso (que é o que
    // salva um token novo — ver NotificationService._saveCurrentToken no
    // app). Quando o próprio FCM confirma que o token não existe mais,
    // apaga ele daqui — assim o próximo `getToken()`/reabertura do app já
    // encontra o campo limpo, em vez de ficar mascarado por um valor
    // antigo que nunca mais vai funcionar.
    logger.warn('Falha ao enviar push', e);
    const code = (e as { code?: string } | undefined)?.code;
    if (code === 'messaging/registration-token-not-registered' || code === 'messaging/invalid-argument') {
      await db.collection('clients').doc(uid).update({ fcmToken: FieldValue.delete() }).catch(() => {});
      const providerRef = db.collection('providers').doc(uid);
      const providerSnap = await providerRef.get();
      if (providerSnap.exists) {
        await providerRef.update({ fcmToken: FieldValue.delete() }).catch(() => {});
      }
    }
  }
}

export const onBudgetRequestCreated = onDocumentCreated(
  'providers/{providerId}/budgets/{budgetId}',
  async (event) => {
    const budget = event.data?.data();
    if (!budget) return;
    // Só pedidos vindos de um cliente pelo marketplace — um orçamento
    // manual do prestador não tem `status`/`clientUid` nenhum.
    if (budget.status !== 'pendente' || !budget.clientUid) return;

    const providerId = event.params.providerId as string;
    const clientName = (budget.customerName as string | undefined) || 'Um cliente';
    const category = (budget.category as string | undefined) || 'um serviço';

    await notify(providerId, {
      type: 'novo_pedido',
      title: 'Novo pedido de orçamento',
      body: `${clientName} pediu um orçamento de ${category}.`,
      budgetId: event.params.budgetId as string,
    });
  },
);

export const onBudgetStatusChanged = onDocumentUpdated(
  'providers/{providerId}/budgets/{budgetId}',
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    if (!before || !after) return;

    // Orçamento manual (sem `clientUid`) não tem cliente do app pra
    // avisar — só os que vieram de um pedido pelo marketplace chegam
    // aqui de verdade.
    const clientUid = after.clientUid as string | undefined;
    if (!clientUid) return;

    const providerId = event.params.providerId as string;
    const budgetId = event.params.budgetId as string;
    const providerName = (after.providerName as string | undefined) || 'O prestador';
    const customerName = (after.customerName as string | undefined) || 'O cliente';

    const beforeStatus = before.status as string | undefined;
    const afterStatus = after.status as string | undefined;

    // Aditivo (ver BudgetsRepository.registerAditivo, pedido do Franck:
    // "quando o orçamento sofrer revisão, realizar a opção de aditivo") —
    // checado ANTES do `return` por status igual logo abaixo, porque um
    // aditivo pode muito bem deixar o status como estava (ex.: já estava
    // `aceito`, o aditivo não desfaz o agendamento — ver o método citado)
    // e mesmo assim precisa avisar o cliente do valor novo.
    const beforeRevision = (before.revisionNumber as number | undefined) ?? 0;
    const afterRevision = (after.revisionNumber as number | undefined) ?? 0;
    if (afterRevision > beforeRevision) {
      const items = (after.items as Array<{ quantity?: number; unitPriceCents?: number }> | undefined) ?? [];
      const subtotalCents = items.reduce(
        (sum, item) => sum + Math.round((item.quantity ?? 0) * (item.unitPriceCents ?? 0)),
        0,
      );
      const discountCents = (after.discountCents as number | undefined) ?? 0;
      const totalCents = Math.max(0, subtotalCents - discountCents);
      const totalLabel = `R$ ${(totalCents / 100).toFixed(2).replace('.', ',')}`;
      await notify(clientUid, {
        type: 'orcamento_revisado',
        title: 'Orçamento revisado',
        body: `${providerName} registrou um aditivo no seu orçamento — novo valor: ${totalLabel}.`,
        budgetId,
      });
      return;
    }

    if (!afterStatus || beforeStatus === afterStatus) return;

    switch (afterStatus) {
      case 'enviado':
        await notify(clientUid, {
          type: 'resposta_pedido',
          title: 'Orçamento enviado',
          body: `${providerName} enviou um orçamento pro seu pedido.`,
          budgetId,
        });
        return;
      case 'aceito':
        await notify(clientUid, {
          type: 'resposta_pedido',
          title: 'Serviço confirmado',
          body: `${providerName} confirmou e agendou seu serviço.`,
          budgetId,
        });
        return;
      case 'aprovado':
        // Cliente aprovou — falta o prestador dar o aceite final (ver
        // BudgetsRepository.acceptFinal), por isso quem precisa agir
        // agora é o PRESTADOR.
        await notify(providerId, {
          type: 'resposta_pedido',
          title: 'Orçamento aprovado',
          body: `${customerName} aprovou o orçamento — confirme pra agendar o serviço.`,
          budgetId,
        });
        return;
      case 'recusado':
        // Quem recusou já sabe (foi ação da própria pessoa) — avisa só o
        // OUTRO lado (ver Budget.rejectedBy).
        if (after.rejectedBy === 'cliente') {
          await notify(providerId, {
            type: 'resposta_pedido',
            title: 'Orçamento recusado',
            body: `${customerName} recusou o orçamento.`,
            budgetId,
          });
        } else {
          await notify(clientUid, {
            type: 'resposta_pedido',
            title: 'Orçamento recusado',
            body: `${providerName} recusou seu pedido.`,
            budgetId,
          });
        }
        return;
      default:
        return;
    }
  },
);
