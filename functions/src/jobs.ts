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
import { notify } from './notifications';

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

    switch (afterStatus) {
      case 'aguardando_pagamento':
        await notify(clientUid, {
          type: 'servico_aguardando_pagamento',
          title: 'Pagamento disponível',
          body: `${providerName} concluiu o serviço — escaneie o QR Code Pix no app dele pra pagar.`,
          budgetId,
        });
        return;
      case 'concluido':
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
