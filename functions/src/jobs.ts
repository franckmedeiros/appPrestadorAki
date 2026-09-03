/**
 * Notificações do módulo "Serviços" (Kanban — ver
 * lib/features/jobs/jobs_kanban_screen.dart). O Job em si nasce no
 * aceite final de um orçamento, direto do app
 * (`BudgetsRepository.acceptFinal` -> `JobsRepository.create`) —
 * diferente de `onBudgetRequestCreated`/`onBudgetStatusChanged` em
 * notifications.ts, esta função não cria nada, só observa a mudança de
 * status pra avisar o cliente nas duas etapas em que ele precisa fazer
 * alguma coisa:
 *
 *  - "aguardando_pagamento": o serviço terminou, falta o cliente pagar —
 *    o prestador já gerou o QR Code Pix na tela (ver `PixPayload`), aqui
 *    só avisa que a cobrança está disponível.
 *  - "concluido": pagamento confirmado, serviço encerrado — pede pro
 *    cliente avaliar o prestador (ver
 *    `BudgetRequestsRepository.hasAcceptedBudgetWith`/avaliação por
 *    estrelas em `providerDirectory/{id}/ratings`).
 *
 * Roda com privilégio de administrador (Admin SDK) — ignora
 * firestore.rules, mesmo padrão de notifications.ts.
 */

import { onDocumentUpdated } from 'firebase-functions/v2/firestore';
import { logger } from 'firebase-functions';
import { FieldValue } from 'firebase-admin/firestore';
import { db } from './lib/admin';
import { notify } from './notifications';
import { buildPixPayload } from './pix_payload';

export const onJobStatusChanged = onDocumentUpdated(
  'providers/{providerId}/jobs/{jobId}',
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    if (!before || !after) return;

    const beforeStatus = before.status as string | undefined;
    const afterStatus = after.status as string | undefined;
    if (!afterStatus || beforeStatus === afterStatus) return;

    // Só jobs vindos de um pedido de cliente pelo marketplace têm
    // `clientUid` pra avisar (ver `Job.clientUid`) — na prática hoje todo
    // Job tem isso, porque só nasce em `acceptFinal` de um orçamento
    // desse tipo, mas a checagem fica por segurança.
    const clientUid = after.clientUid as string | undefined;
    if (!clientUid) return;

    const providerName = (after.providerName as string | undefined) || 'O prestador';
    const budgetId = after.budgetId as string | undefined;
    const providerId = event.params.providerId as string;

    switch (afterStatus) {
      case 'aguardando_pagamento':
        // Pedido do Franck: o cliente precisa ver o QR Code de pagamento
        // dentro do próprio app, em "Meus orçamentos" — não só escanear a
        // tela do prestador presencialmente. Como a chave Pix mora em
        // `providers/{uid}.pixKey` (campo privado, não exposto no
        // diretório público), quem monta o QR Code é esta function (com
        // privilégio de administrador), e grava o resultado pronto no
        // orçamento do cliente (`budgets/{budgetId}` deste mesmo
        // prestador) — o app só precisa saber renderizar (ver
        // MyRequestsScreen).
        if (budgetId) {
          try {
            const providerSnap = await db.collection('providers').doc(providerId).get();
            const pixKey = providerSnap.data()?.pixKey as string | undefined;
            const totalCents = (after.totalCents as number | undefined) ?? 0;
            if (pixKey && pixKey.trim().length > 0 && totalCents > 0) {
              const payload = buildPixPayload({
                pixKey,
                amountCents: totalCents,
                merchantName: providerName,
                referenceLabel: event.params.jobId as string,
              });
              await db
                .collection('providers')
                .doc(providerId)
                .collection('budgets')
                .doc(budgetId)
                .set(
                  {
                    paymentPixPayload: payload,
                    paymentAmountCents: totalCents,
                    paymentRequestedAt: FieldValue.serverTimestamp(),
                    paymentPaidAt: FieldValue.delete(),
                    updatedAt: FieldValue.serverTimestamp(),
                  },
                  { merge: true },
                );
            } else {
              logger.warn(
                `onJobStatusChanged: prestador ${providerId} sem chave Pix cadastrada (ou totalCents zerado) — QR Code não gerado pro orçamento ${budgetId}`,
              );
            }
          } catch (e) {
            // O aviso ao cliente (abaixo) não depende disso — se o QR
            // Code falhar por qualquer motivo, o prestador ainda pode
            // mostrar a cobrança presencialmente pela tela dele (ver
            // JobDetailsSheet/_PaymentQrCode no app).
            logger.warn('onJobStatusChanged: falha ao gravar QR Code Pix no orçamento', e);
          }
        }
        await notify(clientUid, {
          type: 'servico_aguardando_pagamento',
          title: 'Pagamento disponível',
          body: `${providerName} concluiu o serviço — pague pelo QR Code Pix direto em "Meus orçamentos".`,
          budgetId,
        });
        return;
      case 'concluido':
        if (budgetId) {
          await db
            .collection('providers')
            .doc(providerId)
            .collection('budgets')
            .doc(budgetId)
            .set({ paymentPaidAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() }, { merge: true })
            .catch((e) => logger.warn('onJobStatusChanged: falha ao marcar pagamento como confirmado', e));
        }
        await notify(clientUid, {
          type: 'servico_concluido',
          title: 'Como foi o serviço?',
          body: `${providerName} encerrou o serviço. Avalie o atendimento!`,
          budgetId,
        });
        return;
      default:
        return;
    }
  },
);
