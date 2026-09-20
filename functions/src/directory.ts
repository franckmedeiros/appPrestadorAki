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

/**
 * Registra quanto tempo o prestador levou pra responder um pedido de
 * orçamento. Chamada por `onBudgetStatusChanged` (functions/src/
 * notifications.ts) quando um orçamento sai de `pendente` pra `enviado`.
 *
 * Por que esses dois pontos: `createdAt` do orçamento é o instante em que
 * o CLIENTE pediu, e a virada pra `enviado` é o instante em que o
 * PRESTADOR respondeu. A diferença é o tempo de resposta de verdade, e os
 * dois carimbos já existiam desde sempre — o selo "Responde rápido" não
 * precisou de nenhum dado novo, só de alguém somar.
 *
 * Guarda SOMA e CONTAGEM, não a média pronta. Dois motivos: `increment` é
 * atômico, então dois orçamentos respondidos ao mesmo tempo não se
 * atropelam (recalcular a média exigiria ler-modificar-gravar); e com os
 * dois números dá pra mudar o critério do selo depois sem perder o
 * histórico.
 *
 * Só conta a PRIMEIRA resposta de cada orçamento (`pendente` -> `enviado`).
 * Um aditivo enviado depois é outra conversa, não mede a rapidez em
 * atender um pedido novo.
 */
export async function registrarTempoDeResposta(
  providerId: string,
  criadoEm: FirebaseFirestore.Timestamp | undefined,
): Promise<void> {
  if (!criadoEm) return;

  const minutos = Math.round((Date.now() - criadoEm.toMillis()) / 60000);
  // Negativo seria relógio fora de hora; absurdamente alto costuma ser
  // orçamento antigo que ficou esquecido e alguém respondeu semanas
  // depois — deixar entrar distorceria a média pra sempre. O teto de uma
  // semana é generoso e ainda assim protege.
  if (minutos < 0 || minutos > 60 * 24 * 7) return;

  try {
    await db
      .collection('providerDirectory')
      .doc(providerId)
      .update({
        respostasContadas: FieldValue.increment(1),
        respostaMinutosSoma: FieldValue.increment(minutos),
      });
  } catch (e) {
    // Listagem inexistente (prestador ainda não publicou o perfil) cai
    // aqui. Estatística é acessório: nunca pode derrubar o fluxo do
    // orçamento, que é o que importa.
    logger.warn('Não foi possível registrar tempo de resposta', { providerId, e });
  }
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

    // Área de atendimento (ver ProviderDirectoryRepository.upsertOwnListing).
    // A lista de exibição é "Cidade/UF"; a de busca guarda só o nome sem
    // acento. Recalcular aqui cobre o que não passa pelo app — edição pelo
    // Console, script de carga — e garante que as duas nunca divirjam.
    const cidadesAtendidas: string[] = Array.isArray(depois.cidadesAtendidas)
      ? depois.cidadesAtendidas.map((c: unknown) => String(c)).filter((c) => c.trim() !== '')
      : [];
    const nomesDasCidades = [
      ...(cidade ? [cidade] : []),
      ...cidadesAtendidas.map((c) => c.split('/')[0]),
    ]
      .map((c) => c.trim())
      .filter((c) => c !== '');
    const cidadesEsperadas = [...new Set(nomesDasCidades.map(normalizar))];

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

    // Comparação por conteúdo, não por referência: ordenar os dois lados
    // antes de comparar evita reescrever (e disparar o gatilho de novo) só
    // porque os mesmos municípios vieram em ordem diferente.
    const cidadesAtuais: string[] = Array.isArray(depois.cidadesNormalizadas)
      ? depois.cidadesNormalizadas.map((c: unknown) => String(c))
      : [];
    const cidadesDivergem =
      cidadesEsperadas.length > 0 &&
      JSON.stringify([...cidadesAtuais].sort()) !== JSON.stringify([...cidadesEsperadas].sort());

    const precisaCorrigir =
      faltaVisible ||
      cidadesDivergem ||
      (nomeEsperado !== null && depois.nameNormalized !== nomeEsperado) ||
      (cidadeEsperada !== null && depois.cityNormalized !== cidadeEsperada);

    if (precisaCorrigir) {
      try {
        await event.data!.after.ref.update({
          ...(faltaVisible ? { visible: true } : {}),
          ...(nomeEsperado !== null ? { nameNormalized: nomeEsperado } : {}),
          ...(cidadeEsperada !== null ? { cityNormalized: cidadeEsperada } : {}),
          ...(cidadesDivergem ? { cidadesNormalizadas: cidadesEsperadas } : {}),
        });
      } catch (e) {
        logger.warn('Falha ao normalizar listagem', { id: event.params.listingId, e });
      }
    }

    // Cidade nova no resumo. `arrayUnion` não duplica, então dá pra
    // chamar sempre sem checar antes — e sem risco de corrida entre duas
    // escritas simultâneas, diferente de ler-e-regravar a lista.
    // TODAS as cidades atendidas entram no autocomplete, não só a
    // principal: se o prestador atende Florianópolis, o cliente de lá
    // precisa conseguir escolher "Florianópolis" no filtro — senão a área
    // de atendimento existiria no banco e não teria como ser usada.
    const paraOAutocomplete = [...new Set(nomesDasCidades)];
    if (paraOAutocomplete.length > 0) {
      try {
        await db
          .collection('meta')
          .doc('cidades')
          .set({ cidades: FieldValue.arrayUnion(...paraOAutocomplete) }, { merge: true });
      } catch (e) {
        logger.warn('Falha ao atualizar meta/cidades', { cidades: paraOAutocomplete, e });
      }
    }
  },
);
