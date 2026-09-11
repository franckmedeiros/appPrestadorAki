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
    if (!afterStatus) return;

    // Pedido do Franck: depois de um aditivo num orçamento JÁ aceito
    // (ver BudgetsRepository.acceptFinal — reconfirmação), o valor da
    // cobrança precisa ser reenviado com o valor NOVO — inclusive quando
    // o Job já estava em "aguardando_pagamento" (cobrança/QR Code Pix já
    // mandados antes do aditivo, com o valor antigo). Sem este caso
    // extra, `beforeStatus === afterStatus` faria essa function ignorar
    // a atualização — o app só troca `totalCents`, nunca a raia, quando
    // o Job já estava aguardando pagamento (ver
    // JobsRepository.syncTotalFromAditivo).
    const isRepriceWhileAwaitingPayment =
      afterStatus === 'aguardando_pagamento' &&
      beforeStatus === 'aguardando_pagamento' &&
      (before.totalCents as number | undefined) !== (after.totalCents as number | undefined);
    if (beforeStatus === afterStatus && !isRepriceWhileAwaitingPayment) return;

    // Só jobs vindos de um pedido de cliente pelo marketplace têm
    // `clientUid` pra avisar (ver `Job.clientUid`) — na prática hoje todo
    // Job tem isso, porque só nasce em `acceptFinal` de um orçamento
    // desse tipo, mas a checagem fica por segurança.
    const clientUid = after.clientUid as string | undefined;
    if (!clientUid) return;

    const providerName = (after.providerName as string | undefined) || 'O prestador';
    const budgetId = after.budgetId as string | undefined;
    const providerId = event.params.providerId as string;

    // Espelha a etapa do serviço NO ORÇAMENTO do cliente, a cada mudança.
    //
    // Pedido do Franck: "conforme é tramitado lá do lado do prestador,
    // aqui precisa ir atualizando também, pra saber como está o
    // andamento". O app do cliente até tentava mostrar isso, mas indo
    // buscar o Job direto, com uma `collectionGroup('jobs')` — e o Job
    // mora na subcoleção do PRESTADOR, então essa leitura atravessa a
    // fronteira entre as duas contas e depende de regra e índice
    // certinhos. Na prática ela não estava trazendo nada, e como o
    // resultado vazio é indistinguível de "ainda não tem serviço", o
    // cliente ficava sem nenhuma informação de andamento — foi o que o
    // print do Franck mostrou (só "Aceito" e o aviso de pagamento).
    //
    // Gravando a etapa aqui, no documento que o cliente JÁ lê pra montar
    // o card, ele passa a ver o andamento sem depender de nada disso —
    // mesma solução que já tinha sido usada pro QR Code Pix logo abaixo.
    if (budgetId) {
      await db
        .collection('providers')
        .doc(providerId)
        .collection('budgets')
        .doc(budgetId)
        .set(
          {
            serviceStatus: afterStatus,
            serviceStatusUpdatedAt: FieldValue.serverTimestamp(),
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        )
        .catch((e) => logger.warn('onJobStatusChanged: falha ao espelhar a etapa do serviço no orçamento', e));
    }

    switch (afterStatus) {
      // Avisos das etapas do meio — antes o cliente só era avisado na
      // cobrança e na conclusão, e ficava no escuro entre o aceite e o
      // fim do serviço.
      case 'em_andamento':
        await notify(clientUid, {
          type: 'servico_em_andamento',
          title: 'Serviço iniciado',
          body: `${providerName} começou o atendimento.`,
          budgetId,
        });
        return;
      case 'interrompido':
        await notify(clientUid, {
          type: 'servico_interrompido',
          title: 'Serviço pausado',
          body: `${providerName} pausou o atendimento — ele avisa quando retomar.`,
          budgetId,
        });
        return;
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
          title: isRepriceWhileAwaitingPayment ? 'Valor da cobrança atualizado' : 'Pagamento disponível',
          body: isRepriceWhileAwaitingPayment
            ? `${providerName} atualizou o valor do serviço — confira o novo QR Code Pix em "Meus orçamentos".`
            : `${providerName} concluiu o serviço — pague pelo QR Code Pix direto em "Meus orçamentos".`,
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
