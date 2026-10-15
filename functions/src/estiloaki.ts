/**
 * Parceria EstiloAki → PrestadorAki.
 *
 * Todo estabelecimento do EstiloAki (barbearia, salão, estética, unhas)
 * ganha uma entrada no diretório do PrestadorAki, ligada a ele:
 *
 *   providerDirectory/estiloaki-<codigo>  { estiloakiCodigo: <codigo>, ... }
 *
 * - O card mostra todos os dados (WhatsApp, endereço) sem assinatura.
 * - Não tem painel do prestador nem chat: no lugar de "Solicitar
 *   orçamento" aparece "Agendar pelo EstiloAki", que abre o EstiloAki
 *   direto no estabelecimento.
 *
 * Quem chama é o projeto do EstiloAki (functions/prestadoraki.js), quando
 * o estabelecimento é vinculado no HUB e a cada alteração dos dados dele.
 * Protegido pela mesma chave do aviso de cadastros:
 *
 *   firebase functions:secrets:set HUB_AVISO_CHAVE   (já existe nos dois)
 */
import { onRequest } from 'firebase-functions/v2/https';
import { defineSecret } from 'firebase-functions/params';
import { FieldValue } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';
import { db } from './lib/admin';

const CHAVE = defineSecret('HUB_AVISO_CHAVE');

/** Segmento do EstiloAki → categoria do PrestadorAki. */
const CATEGORIA: Record<string, string> = {
  barbearia: 'barbeiro',
  salao: 'cabeleireiro',
  estetica: 'esteticista',
  unhas: 'manicure',
};

const texto = (v: unknown, max = 300) => String(v ?? '').trim().slice(0, max);

export const estiloakiSincronizar = onRequest(
  { secrets: [CHAVE], maxInstances: 2, invoker: 'public' },
  async (req, res) => {
    if (req.method !== 'POST' || req.get('x-hub-chave') !== CHAVE.value()) {
      res.status(403).send('proibido');
      return;
    }
    const d = (req.body ?? {}) as Record<string, unknown>;
    const codigo = texto(d.codigo, 80).toLowerCase();
    if (!/^[a-z0-9-]{3,}$/.test(codigo)) {
      res.status(400).json({ erro: 'codigo inválido' });
      return;
    }
    const id = `estiloaki-${codigo}`;
    const ref = db.collection('providerDirectory').doc(id);
    try {
      if (d.acao === 'remover') {
        await ref.set({ visible: false, atualizadoEm: FieldValue.serverTimestamp() }, { merge: true });
        res.json({ id, removido: true });
        return;
      }
      const categoria = CATEGORIA[texto(d.segmento, 30)] ?? 'barbeiro';
      const slogan = texto(d.slogan, 200);
      await ref.set(
        {
          name: texto(d.nome, 120) || codigo,
          categories: [categoria],
          category: categoria,
          city: texto(d.cidade, 80),
          state: texto(d.uf, 2).toUpperCase() || null,
          whatsapp: texto(d.telefone, 30) || null,
          endereco: texto(d.endereco, 300) || null,
          bio: slogan
            ? `${slogan}\nAgende seu horário pelo app EstiloAki.`
            : 'Agende seu horário pelo app EstiloAki.',
          // Sem conta no PrestadorAki: sem painel e sem chat.
          claimed: false,
          aceitaPedidos: false,
          visible: d.ativa !== false,
          estiloakiCodigo: codigo,
          origem: 'estiloaki',
          atualizadoEm: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      res.json({ id });
    } catch (e) {
      logger.error('estiloakiSincronizar', e);
      res.status(500).json({ erro: String(e) });
    }
  },
);
