/**
 * HUB OP Outsourcing — avisa o hub a cada conta criada no PrestadorAki.
 * O aviso é centralizado no projeto do EstiloAki (que hospeda o hub):
 * função hubRegistrarAviso, protegida pela chave HUB_AVISO_CHAVE.
 *
 *   firebase functions:secrets:set HUB_AVISO_CHAVE   (o MESMO valor do EstiloAki)
 */
import * as functionsV1 from 'firebase-functions/v1';
import { defineSecret } from 'firebase-functions/params';

const CHAVE = defineSecret('HUB_AVISO_CHAVE');
const URL_HUB =
  'https://southamerica-east1-barbearia-opoutsourcing.cloudfunctions.net/hubRegistrarAviso';

export const hubAvisoCadastro = functionsV1
  .runWith({ secrets: [CHAVE] })
  .auth.user()
  .onCreate(async (u) => {
    try {
      // fetch global do Node 20 (sem depender dos tipos DOM no tsconfig).
      const r = await (globalThis as any).fetch(URL_HUB, {
        method: 'POST',
        headers: { 'content-type': 'application/json', 'x-hub-chave': CHAVE.value() },
        body: JSON.stringify({
          app: 'prestadoraki',
          uid: u.uid,
          nome: u.displayName ?? '',
          email: u.email ?? '',
          telefone: u.phoneNumber ?? '',
          provedor: (u.providerData ?? []).map((p) => p.providerId).join(','),
        }),
      });
      if (!r.ok) console.error('hubAvisoCadastro', r.status, await r.text());
    } catch (e) {
      console.error('hubAvisoCadastro', e);
    }
  });
