import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../../core/api_exception.dart';
import '../agenda/appointments_repository.dart';
import '../agenda/models/appointment.dart';
import '../jobs/jobs_repository.dart';
import 'models/budget.dart';

/// Lançada por `BudgetsRepository.acceptFinal` quando já existe outro
/// compromisso na agenda no mesmo dia/horário — a tela trata esse caso à
/// parte (pedir outro horário em vez de só mostrar um erro genérico), ver
/// pedido do Franck: "Bloquear e pedir outro horário".
class BudgetScheduleConflictException extends ApiException {
  BudgetScheduleConflictException()
      : super(0, 'Já existe um compromisso agendado nesse dia/horário. Escolha outro.');
}

/// Repositório do módulo formal de Orçamentos, direto no Firestore em
/// `providers/{uid}/budgets` — mesmo padrão de CustomersRepository/
/// AppointmentsRepository (CRUD simples, sem Cloud Function, isolamento
/// entre prestadores garantido pelo firestore.rules), com a exceção dos
/// métodos de transição de status abaixo (`sendToClient`/
/// `rejectAsProvider`/`acceptFinal`), que fazem parte do fluxo de pedido
/// de orçamento vindo do marketplace (ver `Budget.isFromClientRequest`).
class BudgetsRepository {
  BudgetsRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    AppointmentsRepository? appointmentsRepository,
    JobsRepository? jobsRepository,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _appointments = appointmentsRepository ??
            AppointmentsRepository(firestore: firestore, auth: auth),
        _jobs = jobsRepository ?? JobsRepository(firestore: firestore, auth: auth);

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final AppointmentsRepository _appointments;
  final JobsRepository _jobs;

  CollectionReference<Map<String, dynamic>> get _collection => _firestore
      .collection('providers')
      .doc(_auth.currentUser!.uid)
      .collection('budgets');

  /// Ao vivo, mais recente primeiro — mesma razão de
  /// AppointmentsRepository.watchRange: evita "salvei e não apareceu".
  Stream<List<Budget>> watchAll() {
    // Filtra por `providerUid` (em vez de confiar só no caminho da
    // subcoleção) pelo mesmo motivo de `firestore.rules`/
    // `Budget.providerUid`: a regra de `list` só pode usar campos do
    // documento (nunca `isOwner(providerId)`, que quebraria a
    // collectionGroup query do cliente em "Meus orçamentos"), e o
    // Firestore só consegue provar essa condição de campo se a própria
    // consulta já tiver um `where` correspondente — sem isso, a regra
    // não teria como garantir o resultado e negaria a listagem inteira.
    return _collection
        .where('providerUid', isEqualTo: _auth.currentUser!.uid)
        .orderBy('date', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(Budget.fromFirestore).toList());
  }

  Future<Budget> create(Budget budget) async {
    try {
      final now = FieldValue.serverTimestamp();
      final doc = await _collection.add({
        ...budget.toMap(),
        'providerUid': _auth.currentUser!.uid,
        'createdAt': now,
        'updatedAt': now,
      });
      final snapshot = await doc.get();
      return Budget.fromFirestore(snapshot);
    } on FirebaseException catch (e) {
      throw ApiException(0, e.message ?? 'Não foi possível salvar o orçamento.');
    }
  }

  Future<void> update(Budget budget) async {
    try {
      await _collection.doc(budget.id).set({
        ...budget.toMap(),
        'providerUid': _auth.currentUser!.uid,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } on FirebaseException catch (e) {
      throw ApiException(0, e.message ?? 'Não foi possível atualizar o orçamento.');
    }
  }

  Future<void> delete(String id) async {
    try {
      await _collection.doc(id).delete();
    } on FirebaseException catch (e) {
      throw ApiException(0, e.message ?? 'Não foi possível excluir o orçamento.');
    }
  }

  /// Orçamentos que vieram de um pedido de cliente pelo marketplace e
  /// ainda não foram enviados (`status == pendente`) — usado pra destacar
  /// esses itens na tela de Orçamentos (ver pedido do Franck: "ficar como
  /// pendente para fazer/enviar o orçamento").
  Stream<List<Budget>> watchPending() {
    // Mesmo motivo do `where('providerUid', ...)` em `watchAll` acima —
    // ver comentário lá.
    return _collection
        .where('providerUid', isEqualTo: _auth.currentUser!.uid)
        .where('status', isEqualTo: BudgetStatus.pendente.wireValue)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(Budget.fromFirestore).toList());
  }

  /// Prestador termina de preencher itens/preço de um orçamento pendente
  /// (vindo de um pedido de cliente) e manda pro cliente — transiciona
  /// pendente -> enviado. `budget` deve trazer os itens/preço já
  /// preenchidos (mesmo objeto montado pelo formulário de edição).
  Future<void> sendToClient(Budget budget) async {
    try {
      await _collection.doc(budget.id).set({
        ...budget.toMap(),
        'providerUid': _auth.currentUser!.uid,
        'status': BudgetStatus.enviado.wireValue,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } on FirebaseException catch (e) {
      throw ApiException(0, e.message ?? 'Não foi possível enviar o orçamento.');
    }
  }

  /// Prestador recusa/cancela um pedido de orçamento — o prestador pode
  /// não aceitar o serviço por vários motivos (pedido do Franck). Válido
  /// a partir de `pendente` ou `enviado`.
  Future<void> rejectAsProvider(String id) async {
    try {
      await _collection.doc(id).set({
        'providerUid': _auth.currentUser!.uid,
        'status': BudgetStatus.recusado.wireValue,
        'rejectedBy': 'prestador',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } on FirebaseException catch (e) {
      throw ApiException(0, e.message ?? 'Não foi possível recusar o orçamento.');
    }
  }

  /// Registra um ADITIVO — pedido do Franck: "quando o orçamento sofrer
  /// revisão, realizar a opção de aditivo de orçamento" + "a data precisa
  /// ser a do aditivo" (tanto no PDF quanto no envio pelo app, ver
  /// `BudgetPdf`/`Budget.date`, os dois já leem direto de `Budget.date`,
  /// que este método atualiza). Só faz sentido pra orçamento já enviado
  /// ao cliente (`enviado`/`aprovado`/`aceito` — ver
  /// `BudgetFormScreen._buildReadOnlySummary`, que é quem chama isso).
  ///
  /// Guarda uma "foto" do estado ANTES do aditivo na subcoleção
  /// `versions` (reservada desde o desenho anterior do módulo, nunca
  /// usada até agora — ver comentário em firestore.rules) antes de
  /// sobrescrever, pra manter um histórico consultável de quantas vezes
  /// (e como) o orçamento mudou.
  ///
  /// Status: se o cliente ainda não tinha dado aceite final
  /// (`enviado`/`aprovado`), volta pra `enviado` — o novo valor precisa
  /// ser aprovado de novo antes do prestador confirmar o serviço. Se o
  /// serviço já foi agendado (`aceito`), o aditivo NÃO desfaz o
  /// agendamento (seria estranho reabrir a negociação de um serviço já
  /// em andamento) — só atualiza itens/valor/data e avisa o cliente (ver
  /// `functions/src/notifications.ts`, checagem de `revisionNumber`).
  Future<void> registerAditivo(
    Budget original, {
    required List<BudgetItem> items,
    required int discountCents,
    required String observations,
    required DateTime aditivoDate,
  }) async {
    // Pedido do Franck: "quando eu reenvio o aditivo... ele não poderia
    // estar como Aceito, e sim indicando que foi enviado pro cliente o
    // aditivo e aguardando aprovação do mesmo" — antes disso, um aditivo
    // registrado em cima de um orçamento já `aceito` simplesmente
    // mantinha `aceito`, escondendo que a REVISÃO ainda precisa ser
    // aprovada. Agora sempre vira `aditivoEnviado`, não importa o status
    // anterior (a UI já bloqueia registrar aditivo em cima de um
    // `recusado` — ver `canRegisterAditivo` em BudgetFormScreen).
    const newStatus = BudgetStatus.aditivoEnviado;
    try {
      await _collection.doc(original.id).collection('versions').add({
        'items': original.items.map((item) => item.toMap()).toList(),
        'discountCents': original.discountCents,
        if (original.observations != null && original.observations!.isNotEmpty)
          'observations': original.observations,
        'date': Timestamp.fromDate(original.date),
        'revisionNumber': original.revisionNumber,
        'recordedAt': FieldValue.serverTimestamp(),
      });
      await _collection.doc(original.id).set({
        'providerUid': _auth.currentUser!.uid,
        'items': items.map((item) => item.toMap()).toList(),
        'discountCents': discountCents,
        'observations': observations.trim().isEmpty ? FieldValue.delete() : observations.trim(),
        'date': Timestamp.fromDate(aditivoDate),
        'revisionNumber': original.revisionNumber + 1,
        'status': newStatus.wireValue,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } on FirebaseException catch (e) {
      throw ApiException(0, e.message ?? 'Não foi possível registrar o aditivo.');
    }
  }

  /// Aceite final do prestador, depois que o cliente já aprovou o
  /// orçamento (`status == aprovado`) — lança automaticamente o serviço
  /// na agenda, verificando antes se já não tem outro compromisso pro
  /// mesmo dia/horário (pedido do Franck: "verificando se tem serviço já
  /// agendado para aquele dia/hora" / "Bloquear e pedir outro horário").
  /// A data/hora do serviço só é definida agora, neste passo — é o que o
  /// Franck escolheu quando perguntado ("No aceite final do prestador").
  ///
  /// RECONFIRMAÇÃO (`budget.appointmentId` já preenchido): acontece
  /// quando um orçamento JÁ aceito antes recebe um aditivo (ver
  /// `registerAditivo`), o cliente aprova a revisão, e o prestador passa
  /// de novo por "Confirmar e agendar" — pedido do Franck: "Para os
  /// aditivos não precisa ter essa trava" (a checagem de conflito não
  /// pode barrar o compromisso contra ELE MESMO) + "depois de aceito,
  /// preciso reenviar o valor do aditivo via qrcode ou o valor total
  /// novamente para pagamento". Nesse caso o compromisso/Job que já
  /// existem são ATUALIZADOS no lugar (nunca duplicados) e o valor do
  /// Job é resincronizado — ver `JobsRepository.syncTotalFromAditivo`
  /// pra como isso reabre a cobrança/QR Code Pix quando já tinha sido
  /// enviada com o valor antigo.
  Future<void> acceptFinal(
    Budget budget, {
    required DateTime serviceScheduledAt,
    int serviceDurationMinutes = 60,
  }) async {
    final isReconfirmation = budget.appointmentId != null;
    try {
      final conflict = await _appointments.hasConflict(
        scheduledAt: serviceScheduledAt,
        durationMinutes: serviceDurationMinutes,
        excludeAppointmentId: budget.appointmentId,
      );
      if (conflict) throw BudgetScheduleConflictException();

      // Na reconfirmação o id do compromisso não muda — é o MESMO
      // compromisso, só atualizado no lugar (`update`), nunca um novo
      // (`create`) — por isso não precisa reler o documento pra saber o
      // id, já era conhecido (`budget.appointmentId`).
      final String appointmentId;
      if (isReconfirmation) {
        appointmentId = budget.appointmentId!;
        await _appointments.update(
          appointmentId,
          customerId: budget.customerId,
          customerName: budget.customerName,
          type: AppointmentType.servico,
          scheduledAt: serviceScheduledAt,
          durationMinutes: serviceDurationMinutes,
          addressText: budget.addressText,
          observations: budget.requestDescription,
        );
      } else {
        final appointment = await _appointments.create(
          customerId: budget.customerId,
          customerName: budget.customerName,
          type: AppointmentType.servico,
          scheduledAt: serviceScheduledAt,
          durationMinutes: serviceDurationMinutes,
          addressText: budget.addressText,
          observations: budget.requestDescription,
          budgetId: budget.id,
        );
        appointmentId = appointment.id;
      }

      await _collection.doc(budget.id).set({
        'providerUid': _auth.currentUser!.uid,
        'status': BudgetStatus.aceito.wireValue,
        'serviceScheduledAt': Timestamp.fromDate(serviceScheduledAt),
        'serviceDurationMinutes': serviceDurationMinutes,
        'appointmentId': appointmentId,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Nasce o serviço no módulo "Serviços" (Kanban — ver
      // JobsKanbanScreen/JobsRepository), no lugar do antigo atalho
      // "Pedidos" do Dashboard (pedido do Franck) — só orçamentos vindos
      // de um pedido de cliente pelo marketplace têm `clientUid`/
      // `providerDirectoryId` pra alimentar as notificações de mudança de
      // etapa (ver functions/src/jobs.ts); um orçamento manual do
      // prestador não gera Job nenhum (não tem cliente do app pra
      // acompanhar). Numa reconfirmação o Job já existe — só sincroniza o
      // valor (ver `syncTotalFromAditivo`), nunca cria um segundo.
      //
      // Try/catch PRÓPRIO aqui (em vez de deixar cair no `on FirebaseException`
      // /genérico lá embaixo): nesse ponto o compromisso na Agenda e o
      // status "aceito" do orçamento JÁ foram gravados com sucesso — se a
      // criação/atualização do Job falhar por qualquer motivo, o
      // prestador precisa saber EXATAMENTE disso (e não só ver um "não
      // foi possível confirmar o orçamento" genérico, que soa como se
      // nada tivesse sido salvo, escondendo a causa real — mesmo cuidado
      // que já tomamos antes com erro de Firestore engolido em outras
      // telas).
      if (budget.isFromClientRequest) {
        try {
          if (isReconfirmation) {
            await _jobs.syncTotalFromAditivo(budgetId: budget.id, totalCents: budget.totalCents);
          } else {
            await _jobs.create(
              customerName: budget.customerName,
              totalCents: budget.totalCents,
              budgetId: budget.id,
              appointmentId: appointmentId,
              clientUid: budget.clientUid,
              providerDirectoryId: budget.providerDirectoryId,
              providerName: budget.providerName,
              category: budget.category,
              addressText: budget.addressText,
            );
          }
        } catch (e) {
          debugPrint('BudgetsRepository.acceptFinal: falha ao sincronizar o Job: $e');
          throw ApiException(
            0,
            isReconfirmation
                ? 'O agendamento foi atualizado e o orçamento foi aceito, mas não '
                    'foi possível atualizar o valor em "Serviços" ($e). Avise o '
                    'suporte com essa mensagem.'
                : 'O serviço foi agendado e o orçamento foi aceito, mas não foi '
                    'possível criar o registro em "Serviços" ($e). Avise o suporte '
                    'com essa mensagem.',
          );
        }
      }
    } on BudgetScheduleConflictException {
      rethrow;
    } on FirebaseException catch (e) {
      throw ApiException(0, e.message ?? 'Não foi possível confirmar o orçamento.');
    }
  }
}
