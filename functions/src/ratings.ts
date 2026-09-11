/**
 * Aviso ao PRESTADOR quando um cliente avalia ele.
 *
 * Não é correção de bug: essa notificação simplesmente nunca existiu. O
 * cliente avalia direto do app (ver ProviderDirectoryRepository.rate,
 * que grava a nota e recalcula a média numa transação), sem passar por
 * Cloud Function nenhuma — e nada avisava o prestador. Ele só descobria
 * a avaliação se entrasse em "Minhas avaliações" por conta própria.
 * Relato do Franck: "quando eu avalio o prestador não está indo msg pro
 * prestador".
 *
 * A avaliação mora em `providerDirectory/{providerId}/ratings/{clientUid}`
 * — o id do documento é o uid de quem avaliou, então cada cliente tem no
 * máximo uma avaliação por prestador; avaliar de novo EDITA a mesma (ver
 * ProviderRating). Por isso o gatilho escuta escrita (criação e
 * atualização), e o texto muda conforme o caso: "avaliou" numa nota nova,
 * "atualizou a avaliação" quando a pessoa mudou de ideia.
 *
 * Roda com privilégio de administrador (Admin SDK) — ignora
 * firestore.rules, mesmo padrão de notifications.ts e jobs.ts.
 */

import { onDocumentWritten } from 'firebase-functions/v2/firestore';
import { notify } from './notifications';

/** "★★★★☆" — mais fácil de ler de relance na notificação que "4/5". */
function estrelas(nota: number): string {
  const cheias = Math.max(0, Math.min(5, Math.round(nota)));
  return '★'.repeat(cheias) + '☆'.repeat(5 - cheias);
}

export const onProviderRated = onDocumentWritten(
  'providerDirectory/{providerId}/ratings/{clientUid}',
  async (event) => {
    const antes = event.data?.before?.data();
    const depois = event.data?.after?.data();

    // Avaliação apagada — nada a comemorar nem a avisar.
    if (!depois) return;

    const nota = (depois.stars as number | undefined) ?? 0;
    if (nota <= 0) return;

    // Edição que não mexeu na nota nem no comentário (ex.: só o
    // `clientName` foi preenchido depois) não vira notificação — senão o
    // prestador receberia aviso repetido da mesma avaliação.
    const notaAntes = (antes?.stars as number | undefined) ?? 0;
    const comentario = ((depois.comment as string | undefined) ?? '').trim();
    const comentarioAntes = ((antes?.comment as string | undefined) ?? '').trim();
    if (antes && notaAntes === nota && comentarioAntes === comentario) return;

    const providerId = event.params.providerId as string;
    const clientName = (depois.clientName as string | undefined)?.trim() || 'Um cliente';
    const ehEdicao = Boolean(antes);

    // O comentário entra no corpo quando existe — é o que o prestador
    // mais quer ler, e sem ele a notificação vira só um número. Cortado
    // pra caber: notificação longa é truncada pelo sistema de qualquer
    // jeito, e cortar aqui deixa o corte previsível.
    const trecho =
      comentario.length > 0
        ? ` "${comentario.length > 90 ? `${comentario.slice(0, 90)}...` : comentario}"`
        : '';

    await notify(providerId, {
      type: 'nova_avaliacao',
      title: ehEdicao ? 'Avaliação atualizada' : 'Você recebeu uma avaliação',
      body: `${clientName} ${ehEdicao ? 'atualizou a avaliação' : 'avaliou seu serviço'}: ${estrelas(nota)}${trecho}`,
    });
  },
);
