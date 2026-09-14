/**
 * Manutenção do diretório público (`providerDirectory`) — os dois campos
 * que permitem a busca filtrar no SERVIDOR, e o resumo de cidades.
 *
 * Contexto: o diretório passou de algumas dezenas pra ~9.700 entradas
 * (carga de curadoria — ver scripts/README.md). Com esse tamanho, o
 * desenho antigo da busca (baixar tudo e filtrar no app, porque
 * comparação de string no Firestore é sensível a acento) virou ~10 mil
 * leituras por abertura da tela. A saída é guardar versões normalizadas
 * dos campos, que o Firestore consegue comparar direto:
 *
 *   nameNormalized — minúsculas, sem acento: busca por começo do nome
 *   cityNormalized — idem: filtro de cidade por igualdade
 *
 * O app já grava os dois quando o prestador salva o perfil (ver
 * ProviderDirectoryRepository.upsertOwnListing). Esta função existe pra
 * tudo que NÃO passa por lá: a carga de curadoria, uma edição feita à mão
 * no Console, um script. Assim a busca nunca depende de quem escreveu.
 *
 * E mantém `meta/cidades`: um documento só, com a lista de cidades que
 * têm prestador. Antes o app extraía isso varrendo a coleção inteira —
 * mais caro que a própria busca.
 */
import { onDocumentWritten } from 'firebase-functions/v2/firestore';
import { FieldValue } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';
import { db } from './lib/admin';

/** Mesma normalização de `normalizeForSearch` (lib/core/text_normalize.dart). */
function normalizar(valor: string): string {
  return valor
    .toLowerCase()
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '');
}

export const onListagemEscrita = onDocumentWritten(
  'providerDirectory/{listingId}',
  async (event) => {
    const depois = event.data?.after?.data();
    // Documento apagado: não há o que normalizar. A cidade dele continua
    // em `meta/cidades` — tirar exigiria saber se sobrou algum outro
    // prestador naquela cidade, ou seja, uma consulta a cada exclusão.
    // Uma cidade a mais no autocomplete não quebra nada: se ninguém mais
    // atende ali, a busca por ela volta vazia, que é a verdade.
    if (!depois) return;

    const nome = String(depois.name ?? '');
    const cidade = String(depois.city ?? '');

    const nomeEsperado = nome ? normalizar(nome) : null;
    const cidadeEsperada = cidade ? normalizar(cidade) : null;

    // ESTA COMPARAÇÃO É O QUE IMPEDE UM LOOP INFINITO: a função escreve
    // no mesmo documento que a dispara, então ela só pode escrever quando
    // há de fato algo a corrigir. Com os campos já certos, sai sem tocar
    // em nada e o gatilho não se realimenta.
    // `visible` ausente vira `true`. A busca passou a filtrar esse campo
    // no SERVIDOR (ver ProviderDirectoryRepository.search), e no Firestore
    // um documento SEM o campo não casa com `== true` — ou seja, quem não
    // tiver isso preenchido simplesmente some da busca. Preencher aqui
    // fecha esse buraco pra qualquer entrada nova, venha de onde vier.
    //
    // Só quando está AUSENTE: um `false` foi decisão de alguém (assinatura
    // inativa, ver functions/src/subscription.ts, ou a curadoria ocultada
    // pelo scripts/ocultar_prospeccao.js) e não pode ser desfeito por uma
    // rotina automática.
    const faltaVisible = depois.visible === undefined || depois.visible === null;

    const precisaCorrigir =
      faltaVisible ||
      (nomeEsperado !== null && depois.nameNormalized !== nomeEsperado) ||
      (cidadeEsperada !== null && depois.cityNormalized !== cidadeEsperada);

    if (precisaCorrigir) {
      try {
        await event.data!.after.ref.update({
          ...(faltaVisible ? { visible: true } : {}),
          ...(nomeEsperado !== null ? { nameNormalized: nomeEsperado } : {}),
          ...(cidadeEsperada !== null ? { cityNormalized: cidadeEsperada } : {}),
        });
      } catch (e) {
        logger.warn('Falha ao normalizar listagem', { id: event.params.listingId, e });
      }
    }

    // Cidade nova no resumo. `arrayUnion` não duplica, então dá pra
    // chamar sempre sem checar antes — e sem risco de corrida entre duas
    // escritas simultâneas, diferente de ler-e-regravar a lista.
    if (cidade) {
      try {
        await db
          .collection('meta')
          .doc('cidades')
          .set({ cidades: FieldValue.arrayUnion(cidade) }, { merge: true });
      } catch (e) {
        logger.warn('Falha ao atualizar meta/cidades', { cidade, e });
      }
    }
  },
);
