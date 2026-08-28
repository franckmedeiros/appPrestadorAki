/**
 * Central de notificações do marketplace (sininho — ver
 * lib/widgets/notification_bell.dart) + push de verdade via FCM. Duas
 * pontas do fluxo de `serviceRequests` (ver DATA_MODEL.md):
 *
 *  - onServiceRequestCreated: dispara ao CRIAR um pedido de orçamento —
 *    avisa o PRESTADOR, só quando o perfil já era reivindicado no
 *    momento do pedido (ou seja, já existe `providerUid` — perfil "não
 *    reivindicado" não tem conta nenhuma pra avisar).
 *
 *  - onServiceRequestResponded: dispara quando o campo `status` muda pra
 *    'orcamento_enviado', 'aceito' ou 'recusado' — avisa o CLIENTE que
 *    fez o pedido original.
 *
 * Toda notificação é gravada em `clients/{uid}/notifications` (mesmo uid
 * que recebe o push, guardado em `clients/{uid}.fcmToken` — ver
 * NotificationService no Flutter) — é o que alimenta o sininho dentro do
 * app mesmo depois que o push já sumiu da barra do sistema. Mesmo padrão
 * já usado no app Resenha (functions/index.js de lá).
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

interface NotificationInput {
  type: string;
  title: string;
  body: string;
  serviceRequestId?: string;
}

/**
 * Grava o item na central de notificações do destinatário e, se ele tiver
 * um token FCM salvo, manda o push também. Nunca lança erro pra fora —
 * notificação é um "extra" sobre a operação principal (criar/atualizar o
 * pedido de orçamento), que não pode falhar por causa disso.
 */
async function notifyClient(uid: string, input: NotificationInput): Promise<void> {
  if (!uid) return;

  try {
    await db.collection('clients').doc(uid).collection('notifications').add({
      type: input.type,
      title: input.title,
      body: input.body,
      serviceRequestId: input.serviceRequestId ?? null,
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
        ...(input.serviceRequestId ? { serviceRequestId: input.serviceRequestId } : {}),
      },
      android: { notification: { channelId: NOTIFICATION_CHANNEL_ID } },
    });
  } catch (e) {
    // Token inválido/expirado é comum (app desinstalado, permissão
    // negada etc.) — só registra no log, não faz a função falhar.
    logger.warn('Falha ao enviar push', e);
  }
}

export const onServiceRequestCreated = onDocumentCreated(
  'serviceRequests/{requestId}',
  async (event) => {
    const request = event.data?.data();
    if (!request) return;

    const providerUid = request.providerUid as string | undefined;
    if (!providerUid) return; // Perfil ainda não reivindicado — ninguém pra avisar dentro do app.

    const clientName = (request.clientName as string | undefined) || 'Um cliente';
    const category = (request.category as string | undefined) || 'um serviço';

    await notifyClient(providerUid, {
      type: 'novo_pedido',
      title: 'Novo pedido de orçamento',
      body: `${clientName} pediu um orçamento de ${category}.`,
      serviceRequestId: event.params.requestId,
    });
  },
);

const RESPONSE_STATUSES = new Set(['orcamento_enviado', 'aceito', 'recusado']);

export const onServiceRequestResponded = onDocumentUpdated(
  'serviceRequests/{requestId}',
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    if (!before || !after) return;

    const beforeStatus = before.status as string | undefined;
    const afterStatus = after.status as string | undefined;
    if (beforeStatus === afterStatus) return;
    if (!afterStatus || !RESPONSE_STATUSES.has(afterStatus)) return;

    const clientUid = after.clientUid as string | undefined;
    if (!clientUid) return;

    const providerName = (after.providerName as string | undefined) || 'O prestador';
    const messages: Record<string, string> = {
      orcamento_enviado: `${providerName} enviou um orçamento pro seu pedido.`,
      aceito: `${providerName} aceitou seu pedido.`,
      recusado: `${providerName} recusou seu pedido.`,
    };

    await notifyClient(clientUid, {
      type: 'resposta_pedido',
      title: 'Resposta ao seu pedido',
      body: messages[afterStatus] ?? `Seu pedido mudou de status: ${afterStatus}.`,
      serviceRequestId: event.params.requestId,
    });
  },
);
