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
import { getStorage } from 'firebase-admin/storage';
import { randomUUID } from 'crypto';
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

/**
 * Sobe o logo (base64 vindo do EstiloAki) pro Storage e devolve a URL
 * pública com token — o mesmo formato do upload feito pelo app.
 */
async function salvarLogo(codigo: string, base64: string): Promise<string> {
  const bytes = Buffer.from(base64, 'base64');
  const png = bytes.length > 4 && bytes[0] === 0x89 && bytes[1] === 0x50;
  const bucket = getStorage().bucket();
  const caminho = `estiloaki/${codigo}/logo.${png ? 'png' : 'jpg'}`;
  const token = randomUUID();
  await bucket.file(caminho).save(bytes, {
    resumable: false,
    metadata: {
      contentType: png ? 'image/png' : 'image/jpeg',
      cacheControl: 'public, max-age=86400',
      metadata: { firebaseStorageDownloadTokens: token },
    },
  });
  return `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/` +
    `${encodeURIComponent(caminho)}?alt=media&token=${token}`;
}

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

      // Logo: só sobe de novo quando mudou (hash); "" remove.
      const logo: Record<string, unknown> = {};
      if (d.logoBase64 !== undefined) {
        const b64 = String(d.logoBase64 ?? '');
        const hash = texto(d.logoHash, 64);
        if (!b64) {
          logo.logoUrl = FieldValue.delete();
          logo.estiloakiLogoHash = FieldValue.delete();
        } else {
          const atual = (await ref.get()).data() ?? {};
          if (!atual.logoUrl || atual.estiloakiLogoHash !== hash) {
            try {
              logo.logoUrl = await salvarLogo(codigo, b64);
              logo.estiloakiLogoHash = hash;
            } catch (e) {
              logger.error('estiloakiSincronizar logo', e);
            }
          }
        }
      }
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
          ...logo,
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
