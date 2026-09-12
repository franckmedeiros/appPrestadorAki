/**
 * Conversa dentro do orçamento (pedido do Franck: "ter um lugar no app
 * pra ele perguntar pro cliente, tipo um responder dentro do card. Porque
 * o cliente pode não ter informado o whatsapp corretamente") — ver
 * lib/features/budgets/budget_chat_screen.dart e o bloco `mensagens` no
 * firestore.rules.
 *
 * O app só grava a mensagem; tudo que acontece DEPOIS mora aqui:
 *
 *  - soma 1 no contador de não lidas do lado de quem RECEBE
 *    (`naoLidasCliente`/`naoLidasPrestador`, no próprio documento do
 *    orçamento), que é o que acende a bolinha na lista sem precisar de
 *    uma consulta por card;
 *  - carimba `ultimaMensagemEm`;
 *  - manda o push e grava no sininho, reusando o `notify` das
 *    notificações.
 *
 * Por que no servidor e não no app: somar o contador do OUTRO lado
 * exigiria que o firestore.rules deixasse cada um escrever um campo no
 * documento que pertence à contraparte — exatamente o tipo de brecha que
 * as regras daqui existem pra fechar. Aqui roda com Admin SDK, que ignora
 * as regras por natureza, e o app só pode zerar o PRÓPRIO contador.
 */
import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import { FieldValue } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';
import { db } from './lib/admin';
import { notify } from './notifications';

/** Push com a mensagem inteira fica ilegível — corta com reticências. */
function resumir(texto: string, limite = 120): string {
  return texto.length > limite ? `${texto.slice(0, limite - 3)}...` : texto;
}

export const onMensagemDoOrcamentoCriada = onDocumentCreated(
  'providers/{providerId}/budgets/{budgetId}/mensagens/{mensagemId}',
  async (event) => {
    const mensagem = event.data?.data();
    if (!mensagem) return;

    const providerId = event.params.providerId as string;
    const budgetId = event.params.budgetId as string;

    const orcamentoRef = db
      .collection('providers')
      .doc(providerId)
      .collection('budgets')
      .doc(budgetId);
    const snap = await orcamentoRef.get();
    const orcamento = snap.data();
    if (!orcamento) return;

    // Orçamento criado à mão pelo prestador não tem cliente do app do
    // outro lado — não existe pra quem notificar. Na prática a conversa
    // nem aparece nesses (a tela só oferece quando há `clientUid`), mas a
    // função não pode depender disso.
    const clientUid = orcamento.clientUid as string | undefined;
    if (!clientUid) return;

    const doCliente = mensagem.autorTipo === 'cliente';
    const destinatario = doCliente ? providerId : clientUid;
    const campoContador = doCliente ? 'naoLidasPrestador' : 'naoLidasCliente';

    try {
      await orcamentoRef.update({
        [campoContador]: FieldValue.increment(1),
        ultimaMensagemEm: FieldValue.serverTimestamp(),
        // `updatedAt` de fora de propósito: mensagem não altera o
        // orçamento, e mexer nessa data faria o card parecer editado.
      });
    } catch (e) {
      // Contador é conforto, mensagem é o que importa — se isso falhar, o
      // push abaixo ainda avisa a pessoa.
      logger.warn('Falha ao somar contador de mensagens não lidas', { providerId, budgetId, e });
    }

    const quem = doCliente
      ? ((orcamento.customerName as string | undefined) || 'O cliente')
      : ((orcamento.providerName as string | undefined) || 'O prestador');

    await notify(destinatario, {
      type: 'mensagem_orcamento',
      title: `Mensagem de ${quem}`,
      body: resumir(String(mensagem.texto ?? '')),
      budgetId,
    });
  },
);
