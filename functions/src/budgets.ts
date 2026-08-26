import { FieldValue } from 'firebase-admin/firestore';
import { HttpsError, onCall, onRequest } from 'firebase-functions/v2/https';
import cors from 'cors';
import { db } from './lib/admin';
import {
  BudgetItemInput,
  calculateTotals,
  generatePublicToken,
  priceItems,
} from './lib/budget-helpers';

const corsHandler = cors({ origin: true });

// URL base do web-cliente (Next.js) que hospeda a página pública do
// orçamento — configurar via `firebase functions:config:set` ou variável
// de ambiente no deploy. Fallback é só um placeholder óbvio, pra nunca
// mandar um link quebrado sem perceber.
const PUBLIC_WEB_BASE_URL = process.env.PUBLIC_WEB_BASE_URL ?? 'https://SEU_DOMINIO_AQUI';

type BudgetStatus =
  | 'rascunho'
  | 'enviado'
  | 'visualizado'
  | 'aguardando_aprovacao'
  | 'aprovado'
  | 'recusado'
  | 'alteracao_solicitada'
  | 'expirado'
  | 'cancelado';

interface BudgetPayload {
  customerId: string;
  technicalVisitId?: string | null;
  items: BudgetItemInput[];
  discountCents?: number;
  additionCents?: number;
  validUntil?: string | null;
  executionDeadline?: string | null;
  paymentTerms?: string | null;
  notes?: string | null;
}

function requireProviderId(auth: { uid: string } | undefined): string {
  if (!auth) {
    throw new HttpsError('unauthenticated', 'É preciso estar autenticado.');
  }
  return auth.uid;
}

function validatePayload(data: BudgetPayload) {
  if (!data.customerId || typeof data.customerId !== 'string') {
    throw new HttpsError('invalid-argument', 'customerId é obrigatório.');
  }
  if (!Array.isArray(data.items) || data.items.length === 0) {
    throw new HttpsError('invalid-argument', 'O orçamento precisa de pelo menos um item.');
  }
  for (const item of data.items) {
    if (!item.description || item.quantity <= 0 || item.unitPriceCents < 0) {
      throw new HttpsError('invalid-argument', 'Item de orçamento inválido.');
    }
  }
}

// Cria o orçamento como rascunho, com numeração sequencial atômica (lê e
// incrementa providers/{uid}.nextBudgetNumber na mesma transação — é
// exatamente o tipo de operação que não dá pra confiar só em regra
// declarativa do Firestore, por isso vira Cloud Function).
export const createBudget = onCall(async (request) => {
  const providerId = requireProviderId(request.auth);
  const data = request.data as BudgetPayload;
  validatePayload(data);

  const providerRef = db.doc(`providers/${providerId}`);
  const customerRef = db.doc(`providers/${providerId}/customers/${data.customerId}`);
  const budgetRef = db.collection(`providers/${providerId}/budgets`).doc();

  const items = priceItems(data.items);
  const { subtotalCents, totalCents } = calculateTotals(
    items,
    data.discountCents ?? 0,
    data.additionCents ?? 0,
  );
  const publicToken = generatePublicToken();

  const budget = await db.runTransaction(async (tx) => {
    const [providerSnap, customerSnap] = await Promise.all([tx.get(providerRef), tx.get(customerRef)]);
    if (!providerSnap.exists) {
      throw new HttpsError('failed-precondition', 'Prestador não encontrado.');
    }
    if (!customerSnap.exists) {
      throw new HttpsError('not-found', 'Cliente não encontrado.');
    }

    const number = (providerSnap.data()?.nextBudgetNumber as number | undefined) ?? 1;
    tx.update(providerRef, { nextBudgetNumber: number + 1 });

    const now = FieldValue.serverTimestamp();
    const doc = {
      customerId: data.customerId,
      customerName: customerSnap.data()?.name ?? null,
      technicalVisitId: data.technicalVisitId ?? null,
      number,
      status: 'rascunho' as BudgetStatus,
      issueDate: new Date().toISOString().slice(0, 10),
      validUntil: data.validUntil ?? null,
      items,
      subtotalCents,
      discountCents: data.discountCents ?? 0,
      additionCents: data.additionCents ?? 0,
      totalCents,
      executionDeadline: data.executionDeadline ?? null,
      paymentTerms: data.paymentTerms ?? null,
      notes: data.notes ?? null,
      publicToken,
      sentAt: null,
      viewedAt: null,
      decidedAt: null,
      decidedByIp: null,
      createdAt: now,
      updatedAt: now,
    };
    tx.set(budgetRef, doc);
    tx.set(db.doc(`publicBudgetTokens/${publicToken}`), {
      providerId,
      budgetId: budgetRef.id,
    });

    return { id: budgetRef.id, ...doc };
  });

  return budget;
});

// Atualiza um orçamento existente. Se ele já saiu do estado "rascunho"
// (ou seja, já foi enviado), grava uma versão com o estado ANTERIOR antes
// de aplicar as mudanças — mesma regra "gera nova versão se já enviado"
// que existia no contrato de API original.
export const updateBudget = onCall(async (request) => {
  const providerId = requireProviderId(request.auth);
  const { budgetId, ...data } = request.data as BudgetPayload & { budgetId: string };
  if (!budgetId) throw new HttpsError('invalid-argument', 'budgetId é obrigatório.');
  validatePayload(data as BudgetPayload);

  const budgetRef = db.doc(`providers/${providerId}/budgets/${budgetId}`);

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(budgetRef);
    if (!snap.exists) throw new HttpsError('not-found', 'Orçamento não encontrado.');
    const current = snap.data()!;

    if (current.status !== 'rascunho') {
      const versionsRef = budgetRef.collection('versions');
      const countSnap = await tx.get(versionsRef);
      tx.set(versionsRef.doc(), {
        versionNumber: countSnap.size + 1,
        snapshot: current,
        changeReason: null,
        createdBy: providerId,
        createdAt: FieldValue.serverTimestamp(),
      });
    }

    const items = priceItems(data.items);
    const { subtotalCents, totalCents } = calculateTotals(
      items,
      data.discountCents ?? current.discountCents ?? 0,
      data.additionCents ?? current.additionCents ?? 0,
    );

    const update = {
      items,
      subtotalCents,
      totalCents,
      discountCents: data.discountCents ?? current.discountCents ?? 0,
      additionCents: data.additionCents ?? current.additionCents ?? 0,
      validUntil: data.validUntil ?? current.validUntil ?? null,
      executionDeadline: data.executionDeadline ?? current.executionDeadline ?? null,
      paymentTerms: data.paymentTerms ?? current.paymentTerms ?? null,
      notes: data.notes ?? current.notes ?? null,
      updatedAt: FieldValue.serverTimestamp(),
    };
    tx.update(budgetRef, update);
    return { id: budgetId, ...current, ...update };
  });
});

// Estados a partir dos quais faz sentido (re)enviar um orçamento pro
// cliente. Impede reenviar algo já decidido (aprovado/recusado/cancelado)
// por engano — nesses casos o fluxo correto é criar um orçamento novo.
const SENDABLE_STATUSES: BudgetStatus[] = ['rascunho', 'alteracao_solicitada'];

export const sendBudget = onCall(async (request) => {
  const providerId = requireProviderId(request.auth);
  const { budgetId } = request.data as { budgetId: string };
  const budgetRef = db.doc(`providers/${providerId}/budgets/${budgetId}`);
  const snap = await budgetRef.get();
  if (!snap.exists) throw new HttpsError('not-found', 'Orçamento não encontrado.');
  if (!SENDABLE_STATUSES.includes(snap.data()!.status as BudgetStatus)) {
    throw new HttpsError(
      'failed-precondition',
      `Não é possível enviar um orçamento com status "${snap.data()!.status}".`,
    );
  }

  await budgetRef.update({
    status: 'enviado' as BudgetStatus,
    sentAt: FieldValue.serverTimestamp(),
  });

  const publicUrl = `${PUBLIC_WEB_BASE_URL}/o/${snap.data()!.publicToken}`;
  return { publicUrl };
});

export const rejectBudget = onCall(async (request) => {
  const providerId = requireProviderId(request.auth);
  const { budgetId } = request.data as { budgetId: string };
  const budgetRef = db.doc(`providers/${providerId}/budgets/${budgetId}`);
  const snap = await budgetRef.get();
  if (!snap.exists) throw new HttpsError('not-found', 'Orçamento não encontrado.');
  if (snap.data()!.status === 'aprovado') {
    throw new HttpsError('failed-precondition', 'Este orçamento já foi aprovado.');
  }
  await budgetRef.update({
    status: 'recusado' as BudgetStatus,
    decidedAt: FieldValue.serverTimestamp(),
  });
  return { ok: true };
});

export const requestBudgetChange = onCall(async (request) => {
  const providerId = requireProviderId(request.auth);
  const { budgetId, message } = request.data as { budgetId: string; message: string };
  if (!message?.trim()) throw new HttpsError('invalid-argument', 'message é obrigatório.');

  const budgetRef = db.doc(`providers/${providerId}/budgets/${budgetId}`);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(budgetRef);
    if (!snap.exists) throw new HttpsError('not-found', 'Orçamento não encontrado.');
    tx.update(budgetRef, { status: 'alteracao_solicitada' as BudgetStatus });
    tx.set(budgetRef.collection('changeRequests').doc(), {
      message,
      createdAt: FieldValue.serverTimestamp(),
      resolvedAt: null,
    });
  });
  return { ok: true };
});

// Núcleo compartilhado de "aprovar orçamento": usado tanto pelo endpoint
// autenticado (approveBudget, o prestador registrando que o cliente
// aprovou por outro canal) quanto pelo público (publicApproveBudget, o
// próprio cliente clicando no link). Cria o job automaticamente — ver a
// ressalva sobre data/hora placeholder em DATA_MODEL.md.
async function approveBudgetInternal(
  providerId: string,
  budgetId: string,
  decidedByIp: string | null,
): Promise<{ jobId: string }> {
  const budgetRef = db.doc(`providers/${providerId}/budgets/${budgetId}`);
  const jobRef = db.collection(`providers/${providerId}/jobs`).doc();

  await db.runTransaction(async (tx) => {
    const budgetSnap = await tx.get(budgetRef);
    if (!budgetSnap.exists) throw new HttpsError('not-found', 'Orçamento não encontrado.');
    const budget = budgetSnap.data()!;

    // Sem este guard, aprovar duas vezes o mesmo orçamento (ex.: o
    // prestador clica em "aprovar" no app enquanto o cliente também clica
    // no link público) criaria DOIS jobs duplicados — cada leitura da
    // transação vê o estado real no momento em que é retentada pelo
    // Firestore em caso de conflito de escrita concorrente.
    if (budget.status === 'aprovado') {
      throw new HttpsError('failed-precondition', 'Este orçamento já foi aprovado.');
    }

    let addressText = 'Endereço a confirmar';
    let scheduledDate = new Date().toISOString().slice(0, 10);
    let scheduledTime = '09:00';

    if (budget.technicalVisitId) {
      const visitSnap = await tx.get(
        db.doc(`providers/${providerId}/technicalVisits/${budget.technicalVisitId}`),
      );
      if (visitSnap.exists) {
        const visit = visitSnap.data()!;
        addressText = visit.addressText ?? addressText;
        scheduledDate = visit.scheduledDate ?? scheduledDate;
        scheduledTime = visit.scheduledTime ?? scheduledTime;
      }
    }

    tx.update(budgetRef, {
      status: 'aprovado' as BudgetStatus,
      decidedAt: FieldValue.serverTimestamp(),
      decidedByIp,
    });

    tx.set(jobRef, {
      customerId: budget.customerId,
      customerName: budget.customerName ?? null,
      budgetId,
      technicalVisitId: budget.technicalVisitId ?? null,
      appointmentId: null,
      addressText,
      // NOTA: se não havia visita técnica vinculada, esta data/hora é só
      // um placeholder — o prestador precisa confirmar/reagendar. Mesma
      // lacuna que já existia no contrato original (um orçamento não tem
      // data de execução própria).
      scheduledDate,
      scheduledTime,
      totalCents: budget.totalCents ?? 0,
      responsibleUserId: null,
      status: 'agendado',
      startedAt: null,
      arrivedAt: null,
      completedAt: null,
      notes: null,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });

  return { jobId: jobRef.id };
}

export const approveBudget = onCall(async (request) => {
  const providerId = requireProviderId(request.auth);
  const { budgetId } = request.data as { budgetId: string };
  return approveBudgetInternal(providerId, budgetId, null);
});

// ============================== ENDPOINTS PÚBLICOS ==============================
// Sem autenticação — protegidos só pelo token ser praticamente
// impossível de adivinhar (24 bytes aleatórios). Resolvem o token via
// Admin SDK (que ignora firestore.rules) e devolvem só os campos do
// PublicBudgetView, nunca o documento inteiro.

async function resolveToken(token: string): Promise<{ providerId: string; budgetId: string }> {
  const pointerSnap = await db.doc(`publicBudgetTokens/${token}`).get();
  if (!pointerSnap.exists) {
    throw new HttpsError('not-found', 'Link inválido ou expirado.');
  }
  return pointerSnap.data() as { providerId: string; budgetId: string };
}

export const getPublicBudget = onRequest((req, res) => {
  corsHandler(req, res, async () => {
    try {
      // Chamada esperada: GET .../getPublicBudget?token=XXX
      const token = String(req.query.token ?? '').trim();
      if (!token) {
        res.status(400).json({ message: 'Token ausente.' });
        return;
      }
      const { providerId, budgetId } = await resolveToken(token);
      const [providerSnap, budgetSnap] = await Promise.all([
        db.doc(`providers/${providerId}`).get(),
        db.doc(`providers/${providerId}/budgets/${budgetId}`).get(),
      ]);
      if (!budgetSnap.exists) {
        res.status(404).json({ message: 'Orçamento não encontrado.' });
        return;
      }
      const budget = budgetSnap.data()!;
      const provider = providerSnap.data() ?? {};

      // Primeira visualização registra `viewedAt` e passa o status pra
      // "visualizado" se ainda estava só "enviado" — mesma regra do
      // contrato original.
      if (!budget.viewedAt) {
        await budgetSnap.ref.update({
          viewedAt: FieldValue.serverTimestamp(),
          ...(budget.status === 'enviado' ? { status: 'visualizado' } : {}),
        });
      }

      res.json({
        providerName: provider.tradeName ?? provider.companyName ?? provider.name ?? 'Prestador',
        providerLogoUrl: provider.logoUrl ?? null,
        number: budget.number,
        status: budget.status,
        items: budget.items,
        totalCents: budget.totalCents,
        executionDeadline: budget.executionDeadline,
        paymentTerms: budget.paymentTerms,
        notes: budget.notes,
        validUntil: budget.validUntil,
      });
    } catch (error) {
      const status = error instanceof HttpsError ? httpsErrorToStatus(error) : 500;
      res.status(status).json({ message: (error as Error).message ?? 'Erro inesperado.' });
    }
  });
});

export const publicApproveBudget = onRequest((req, res) => {
  corsHandler(req, res, async () => {
    try {
      // Aceita o token tanto por query string quanto no corpo do POST.
      const token = String(req.query.token ?? req.body?.token ?? '').trim();
      if (!token) {
        res.status(400).json({ message: 'Token ausente.' });
        return;
      }
      const { providerId, budgetId } = await resolveToken(token);
      const ip = (req.headers['x-forwarded-for'] as string)?.split(',')[0]?.trim() ?? req.ip ?? null;
      await approveBudgetInternal(providerId, budgetId, ip);
      res.json({ ok: true });
    } catch (error) {
      const status = error instanceof HttpsError ? httpsErrorToStatus(error) : 500;
      res.status(status).json({ message: (error as Error).message ?? 'Erro inesperado.' });
    }
  });
});

function httpsErrorToStatus(error: HttpsError): number {
  switch (error.code) {
    case 'not-found':
      return 404;
    case 'invalid-argument':
      return 400;
    case 'unauthenticated':
      return 401;
    case 'failed-precondition':
      return 409;
    default:
      return 500;
  }
}
