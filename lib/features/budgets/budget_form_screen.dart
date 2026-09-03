import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/app_theme.dart';
import '../../core/auth_controller.dart';
import '../../core/currency_text_utils.dart';
import '../../core/date_text_utils.dart';
import '../../widgets/mask_text_input_formatter.dart';
import '../customers/customers_repository.dart';
import '../customers/models/customer.dart';
import '../marketplace/models/service_category.dart';
import 'budget_pdf.dart';
import 'budgets_repository.dart';
import 'models/budget.dart';
import 'widgets/aditivo_badge.dart';

/// Rótulo de quem recusou (ver `Budget.rejectedBy`) pronto pra exibir.
String _rejectedByLabel(String? rejectedBy) => switch (rejectedBy) {
      'cliente' => 'O cliente recusou este orçamento.',
      'prestador' => 'Você recusou este pedido.',
      _ => 'Este orçamento foi recusado.',
    };

/// Controllers de uma linha de item — cada linha vira um `BudgetItem` na
/// hora de salvar/gerar o PDF (ver `toItem()`). Ficam num objeto próprio
/// (em vez de 4 listas paralelas de controllers) só pra não perder o
/// vínculo entre os 4 campos de uma mesma linha ao adicionar/remover.
class _ItemRowControllers {
  _ItemRowControllers({
    String description = '',
    double quantity = 1,
    String unit = 'serviço',
    int unitPriceCents = 0,
    this.aditivoNumber,
  })  : descriptionController = TextEditingController(text: description),
        quantityController = TextEditingController(text: _formatQuantity(quantity)),
        unitController = TextEditingController(text: unit),
        unitPriceController = TextEditingController(
          text: unitPriceCents > 0 ? formatCentsBRL(unitPriceCents).replaceAll('R\$ ', '') : '',
        );

  final TextEditingController descriptionController;
  final TextEditingController quantityController;
  final TextEditingController unitController;
  final TextEditingController unitPriceController;

  /// `null` = item original; um número = acrescentado por esse aditivo
  /// (ver `BudgetItem.aditivoNumber` — pedido do Franck: o aditivo vira
  /// um item a mais no orçamento, marcado como tal, em vez de substituir
  /// os itens originais). Fixo por linha (não muda depois de criada).
  final int? aditivoNumber;

  static String _formatQuantity(double quantity) => quantity == quantity.roundToDouble()
      ? quantity.toInt().toString()
      : quantity.toString().replaceAll('.', ',');

  /// `null` quando a linha está em branco (descrição vazia) — usado tanto
  /// pra montar o orçamento de verdade quanto pro cálculo de subtotal ao
  /// vivo, ignorando linhas que a pessoa ainda não preencheu.
  BudgetItem? toItem() {
    final description = descriptionController.text.trim();
    if (description.isEmpty) return null;
    final quantity = double.tryParse(quantityController.text.trim().replaceAll(',', '.')) ?? 1;
    final unit = unitController.text.trim().isEmpty ? 'serviço' : unitController.text.trim();
    final unitPriceCents = tryParseCentsFromText(unitPriceController.text) ?? 0;
    return BudgetItem(
      description: description,
      quantity: quantity,
      unit: unit,
      unitPriceCents: unitPriceCents,
      aditivoNumber: aditivoNumber,
    );
  }

  void dispose() {
    descriptionController.dispose();
    quantityController.dispose();
    unitController.dispose();
    unitPriceController.dispose();
  }
}

/// Formulário de orçamento (módulo formal, ligado a Clientes cadastrados).
/// Cria um novo (`budget == null`) ou edita um já existente — inclusive um
/// que nasceu de um pedido de cliente pelo marketplace (ver
/// `Budget.isFromClientRequest`/`BudgetStatus`), caso em que a tela também
/// cuida do envio pro cliente, da recusa e do aceite final (ver
/// `_buildActions`/`_buildReadOnlySummary`). Gera o PDF no layout combinado
/// com o Franck a partir dos MESMOS dados do formulário — não precisa
/// salvar antes pra gerar.
///
/// Visual em cards com ícone, a partir de um mockup que o Franck mandou.
/// O mockup só mostrava "Salvar orçamento" e "Cancelar", mas "Gerar e
/// compartilhar PDF" é uma funcionalidade de verdade que já existia
/// (não dava pra simplesmente tirar) - virou um terceiro botão
/// secundário entre os outros dois, em vez de sumir.
class BudgetFormScreen extends StatefulWidget {
  const BudgetFormScreen({super.key, this.budget});

  final Budget? budget;

  @override
  State<BudgetFormScreen> createState() => _BudgetFormScreenState();
}

class _BudgetFormScreenState extends State<BudgetFormScreen> {
  late Future<List<Customer>> _customersFuture;
  String? _selectedCustomerId;

  late final _addressController = TextEditingController(text: widget.budget?.addressText ?? '');
  late final DateTime _initialDate = widget.budget?.date ?? DateTime.now();
  late final _dateController = TextEditingController(text: formatDateDdMmYyyy(_initialDate));
  final _dateMask = MaskTextInputFormatter('##/##/####');
  late final _discountController = TextEditingController(
    text: (widget.budget != null && widget.budget!.discountCents > 0)
        ? formatCentsBRL(widget.budget!.discountCents).replaceAll('R\$ ', '')
        : '',
  );
  late final _observationsController = TextEditingController(text: widget.budget?.observations ?? '');

  late List<_ItemRowControllers> _itemRows;

  bool get _isEditing => widget.budget != null;

  /// Se este orçamento nasceu de um pedido de cliente pelo marketplace
  /// (em vez de criado manualmente pelo prestador) — ver
  /// `Budget.isFromClientRequest`. Controla tanto os botões quanto se o
  /// formulário de itens/preço fica editável ou vira um resumo.
  bool get _isClientRequest => widget.budget?.isFromClientRequest ?? false;

  BudgetStatus? get _status => widget.budget?.status;

  /// Só dá pra editar itens/preço enquanto o orçamento ainda não foi
  /// enviado pro cliente — depois disso (enviado/aprovado/aceito/
  /// recusado) a tela vira um resumo (ver `_buildReadOnlyBody`).
  bool get _isReadOnlyStatus =>
      _status != null && _status != BudgetStatus.pendente;

  late TimeOfDay _serviceTime = widget.budget?.serviceScheduledAt != null
      ? TimeOfDay.fromDateTime(widget.budget!.serviceScheduledAt!)
      : const TimeOfDay(hour: 9, minute: 0);

  bool _linkingCustomer = false;

  bool _saving = false;
  bool _generatingPdf = false;
  String? _error;

  // Aditivo (pedido do Franck: "quando o orçamento sofrer revisão,
  // realizar a opção de aditivo de orçamento") — reabre o formulário
  // completo de itens/preço mesmo com `_isReadOnlyStatus == true`, só
  // pra ESSE fluxo específico (ver `_startAditivo`/`_cancelAditivo`).
  // Data separada de `_dateController` DE PROPÓSITO: em `aprovado`,
  // `_dateController` já é reaproveitado por `_buildReadOnlySummary`
  // pra outra coisa (a data do SERVIÇO, ver `_acceptFinal`) — misturar
  // os dois ia confundir o valor de um com o do outro.
  bool _editingAditivo = false;
  late final _aditivoDateController =
      TextEditingController(text: formatDateDdMmYyyy(DateTime.now()));

  /// Campo de data "ativo" no formulário completo — o normal
  /// (`_dateController`, data do orçamento) ou, durante um aditivo, o
  /// dedicado (`_aditivoDateController`, data do aditivo). Único ponto
  /// usado tanto por `_buildBudgetFromForm` (validação/PDF) quanto pelo
  /// campo "Data" mostrado na tela — nunca diverge um do outro.
  TextEditingController get _activeDateController =>
      _editingAditivo ? _aditivoDateController : _dateController;

  Future<void> _pickActiveDate() => _editingAditivo ? _pickAditivoDate() : _pickDate();

  @override
  void initState() {
    super.initState();
    _customersFuture = context.read<CustomersRepository>().list();
    _selectedCustomerId = widget.budget?.customerId;
    if (_isClientRequest && _selectedCustomerId == null) {
      _linkClientCustomer();
    }
    final items = widget.budget?.items;
    _itemRows = (items != null && items.isNotEmpty)
        ? items
            .map((item) => _ItemRowControllers(
                  description: item.description,
                  quantity: item.quantity,
                  unit: item.unit,
                  unitPriceCents: item.unitPriceCents,
                  aditivoNumber: item.aditivoNumber,
                ))
            .toList()
        : [_ItemRowControllers()];
  }

  @override
  void dispose() {
    _addressController.dispose();
    _dateController.dispose();
    _aditivoDateController.dispose();
    _discountController.dispose();
    _observationsController.dispose();
    for (final row in _itemRows) {
      row.dispose();
    }
    super.dispose();
  }

  /// Item novo criado enquanto `_editingAditivo` está ativo já nasce
  /// marcado com o número do aditivo em registro — pedido do Franck: "o
  /// aditivo... seja como um item a mais no orçamento, marcando como
  /// aditivo". Os itens que já existiam antes de abrir o aditivo (ver
  /// `initState`/`_cancelAditivo`) continuam com o selo que já tinham
  /// (`null` = original), sem essa linha mexer neles.
  void _addItemRow() => setState(() => _itemRows.add(
        _ItemRowControllers(
          aditivoNumber: _editingAditivo ? (widget.budget?.revisionNumber ?? 0) + 1 : null,
        ),
      ));

  void _removeItemRow(int index) {
    setState(() {
      _itemRows.removeAt(index).dispose();
      if (_itemRows.isEmpty) _itemRows.add(_ItemRowControllers());
    });
  }

  List<BudgetItem> _currentItems() =>
      _itemRows.map((row) => row.toItem()).whereType<BudgetItem>().toList();

  Future<void> _pickDate() async {
    final current = tryParseDateDdMmYyyy(_dateController.text) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(current.year - 2),
      lastDate: DateTime(current.year + 2),
    );
    if (picked != null) setState(() => _dateController.text = formatDateDdMmYyyy(picked));
  }

  /// Mesma lógica de `_pickDate`, mas pro campo dedicado do aditivo (ver
  /// `_aditivoDateController`) — permite ajustar pra uma data passada
  /// (ex.: o acordo do aditivo foi fechado há alguns dias) sem mexer na
  /// data original do orçamento.
  Future<void> _pickAditivoDate() async {
    final current = tryParseDateDdMmYyyy(_aditivoDateController.text) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(current.year - 2),
      lastDate: DateTime(current.year + 2),
    );
    if (picked != null) setState(() => _aditivoDateController.text = formatDateDdMmYyyy(picked));
  }

  Future<void> _pickServiceTime() async {
    final picked = await showTimePicker(context: context, initialTime: _serviceTime);
    if (picked != null) setState(() => _serviceTime = picked);
  }

  /// Cria (ou encontra) automaticamente o cadastro de Cliente a partir do
  /// pedido do marketplace, sem precisar cadastro manual — pedido do
  /// Franck: "já pode ser criado o cliente automaticamente para o
  /// prestador, sem a necessidade de inserir manualmente". Se falhar, o
  /// prestador ainda consegue escolher/cadastrar manualmente na hora de
  /// enviar o orçamento.
  Future<void> _linkClientCustomer() async {
    final budget = widget.budget;
    if (budget == null || budget.clientUid == null) return;
    setState(() => _linkingCustomer = true);
    try {
      final customer = await context.read<CustomersRepository>().findOrCreateForClient(
            clientUid: budget.clientUid!,
            name: budget.customerName,
            phone: budget.clientPhone,
          );
      if (!mounted) return;
      setState(() {
        _selectedCustomerId = customer.id;
        _customersFuture = context.read<CustomersRepository>().list();
      });
    } catch (_) {
      // Sem problema — o campo Cliente continua disponível pra escolher
      // ou cadastrar manualmente.
    } finally {
      if (mounted) setState(() => _linkingCustomer = false);
    }
  }

  /// Monta o `Budget` a partir do estado atual do formulário — usado
  /// tanto por `_save` quanto por `_generatePdf`, pra nunca ficarem
  /// divergentes sobre o que vale como orçamento válido.
  Future<Budget?> _buildBudgetFromForm() async {
    final items = _currentItems();
    if (items.isEmpty) {
      setState(() => _error = 'Adicione pelo menos um item com descrição.');
      return null;
    }
    if (_selectedCustomerId == null) {
      setState(() => _error = 'Selecione um cliente.');
      return null;
    }
    final date = tryParseDateDdMmYyyy(_activeDateController.text.trim());
    if (date == null) {
      setState(() => _error = _editingAditivo ? 'Data do aditivo inválida.' : 'Data inválida.');
      return null;
    }
    final customers = await _customersFuture;
    Customer? customer;
    for (final c in customers) {
      if (c.id == _selectedCustomerId) {
        customer = c;
        break;
      }
    }
    if (customer == null) {
      setState(() => _error = 'Cliente selecionado não encontrado — escolha de novo.');
      return null;
    }
    return Budget(
      id: widget.budget?.id ?? '',
      customerId: _selectedCustomerId,
      customerName: customer.name,
      addressText: _addressController.text.trim(),
      date: date,
      items: items,
      discountCents: tryParseCentsFromText(_discountController.text) ?? 0,
      observations: _observationsController.text.trim(),
      // Só pra o PDF (ver _generatePdf) já mostrar "ADITIVO Nº X" durante
      // a edição, antes de salvar — o valor que realmente conta é o
      // gravado por `registerAditivo` (ver `_save`).
      revisionNumber:
          _editingAditivo ? (widget.budget?.revisionNumber ?? 0) + 1 : (widget.budget?.revisionNumber ?? 0),
    );
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final budget = await _buildBudgetFromForm();
      if (budget == null) return;
      final repository = context.read<BudgetsRepository>();
      if (_editingAditivo) {
        // Registra o aditivo (ver BudgetsRepository.registerAditivo) —
        // NUNCA passa por update()/create(): itens/valor/data revisados
        // vêm do form, mas status/clientUid/etc. do orçamento ORIGINAL
        // (widget.budget!) é quem decide o que muda no documento.
        await repository.registerAditivo(
          widget.budget!,
          items: budget.items,
          discountCents: budget.discountCents,
          observations: budget.observations ?? '',
          aditivoDate: budget.date,
        );
      } else if (_status == BudgetStatus.pendente) {
        // Termina de preencher os itens/preço de um pedido de cliente e
        // manda pro cliente — pendente -> enviado (pedido do Franck: "vai
        // precisar terminar de preencher os dados para enviar o
        // orçamento para o cliente").
        await repository.sendToClient(budget);
      } else if (_isEditing) {
        await repository.update(budget);
      } else {
        await repository.create(budget);
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Não foi possível salvar o orçamento.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Reabre o formulário completo de itens/preço num orçamento já
  /// enviado (`enviado`/`aprovado`/`aceito`) pra registrar um aditivo —
  /// pedido do Franck. Confirma antes: mexer no valor de um orçamento já
  /// enviado/aceito é uma ação com peso. Um aditivo SEMPRE volta o
  /// orçamento pra "aguardando aprovação" (ver
  /// BudgetsRepository.registerAditivo/BudgetStatus.aditivoEnviado) — já
  /// não existe mais o caso especial de continuar "Aceito" sem o cliente
  /// precisar agir de novo.
  Future<void> _startAditivo() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Registrar aditivo?'),
        content: Text(
          _status == BudgetStatus.aceito
              ? 'Você vai poder alterar itens e valor deste orçamento. O '
                  'agendamento do serviço não muda, mas o orçamento volta a '
                  'aguardar aprovação — o cliente vai precisar confirmar o '
                  'novo valor.'
              : 'Você vai poder alterar itens e valor deste orçamento. O '
                  'cliente vai precisar aprovar o valor revisado de novo.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Continuar')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      _editingAditivo = true;
      _aditivoDateController.text = formatDateDdMmYyyy(DateTime.now());
    });
  }

  /// Sai do modo de aditivo sem salvar, voltando pro resumo — os
  /// controllers de itens/desconto/observações já estavam preenchidos
  /// com os dados de `widget.budget` desde o `initState`, mas podem ter
  /// sido editados enquanto `_editingAditivo` estava ativo; refaz do
  /// zero a partir do orçamento original pra não deixar rascunho preso
  /// caso o prestador reabra o aditivo de novo sem sair da tela.
  void _cancelAditivo() {
    final budget = widget.budget;
    if (budget == null) return;
    setState(() {
      _editingAditivo = false;
      _discountController.text =
          budget.discountCents > 0 ? formatCentsBRL(budget.discountCents).replaceAll('R\$ ', '') : '';
      _observationsController.text = budget.observations ?? '';
      for (final row in _itemRows) {
        row.dispose();
      }
      _itemRows = budget.items.isNotEmpty
          ? budget.items
              .map((item) => _ItemRowControllers(
                    description: item.description,
                    quantity: item.quantity,
                    unit: item.unit,
                    unitPriceCents: item.unitPriceCents,
                    aditivoNumber: item.aditivoNumber,
                  ))
              .toList()
          : [_ItemRowControllers()];
    });
  }

  /// Prestador recusa/cancela um pedido de orçamento vindo do
  /// marketplace — pedido do Franck: "precisa ter é uma opção de
  /// cancelar/rejeitar o orçamento, porque o prestador pode não aceitar
  /// o serviço por vários motivos". Válido em `pendente` (ainda nem
  /// respondeu) ou `enviado` (desiste depois de já ter mandado o valor).
  Future<void> _rejectAsProvider() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Recusar este pedido?'),
        content: const Text(
          'O cliente vai ser avisado que você não vai atender esse pedido de orçamento.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Voltar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Recusar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.read<BudgetsRepository>().rejectAsProvider(widget.budget!.id);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Não foi possível recusar o pedido.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Aceite final do prestador, depois que o cliente já aprovou — lança
  /// automaticamente o serviço na agenda (ver
  /// `BudgetsRepository.acceptFinal`), bloqueando se já houver outro
  /// compromisso pro mesmo dia/horário.
  Future<void> _acceptFinal() async {
    final date = tryParseDateDdMmYyyy(_dateController.text.trim());
    if (date == null) {
      setState(() => _error = 'Data inválida.');
      return;
    }
    final scheduledAt =
        DateTime(date.year, date.month, date.day, _serviceTime.hour, _serviceTime.minute);

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.read<BudgetsRepository>().acceptFinal(
            widget.budget!,
            serviceScheduledAt: scheduledAt,
          );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Não foi possível confirmar o orçamento.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _generatePdf() async {
    setState(() {
      _generatingPdf = true;
      _error = null;
    });
    try {
      final budget = await _buildBudgetFromForm();
      if (budget == null) return;
      final auth = context.read<AuthController>();
      final profileData = await auth.fetchOwnProfileData();
      final bytes = await buildBudgetPdf(
        budget,
        BudgetPdfProvider(
          name: auth.displayName,
          logoUrl: profileData['logoUrl'] as String?,
          pixKey: profileData['pixKey'] as String?,
        ),
      );
      if (!mounted) return;
      final suffix = budget.revisionNumber > 0 ? '_aditivo${budget.revisionNumber}' : '';
      await Printing.sharePdf(bytes: bytes, filename: 'orcamento_${budget.customerName}$suffix.pdf');
    } catch (_) {
      if (mounted) setState(() => _error = 'Não foi possível gerar o PDF. Tenta de novo.');
    } finally {
      if (mounted) setState(() => _generatingPdf = false);
    }
  }

  Widget _buildItemRow(int index) {
    final row = _itemRows[index];
    final item = row.toItem();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.muted.withValues(alpha: 0.10),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Item ${index + 1}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    if (row.aditivoNumber != null) ...[
                      const SizedBox(width: 8),
                      AditivoBadge(number: row.aditivoNumber!, compact: true),
                    ],
                  ],
                ),
              ),
              IconButton(
                onPressed: () => _removeItemRow(index),
                tooltip: 'Remover item',
                visualDensity: VisualDensity.compact,
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: AppColors.danger,
                  size: 19,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          TextField(
            controller: row.descriptionController,
            decoration: const InputDecoration(
              hintText: 'Descrição do item',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _CompactMiniField(
                  label: 'Qtd.',
                  child: TextField(
                    controller: row.quantityController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(hintText: '1'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: _CompactMiniField(
                  label: 'Unidade',
                  child: TextField(
                    controller: row.unitController,
                    decoration: const InputDecoration(hintText: 'Serviço'),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: _CompactMiniField(
                  label: 'Preço',
                  child: TextField(
                    controller: row.unitPriceController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(hintText: '0,00'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ),
            ],
          ),
          if (item != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Total: ${formatCentsBRL(item.totalCents)}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
  @override
  Widget build(BuildContext context) {
    final items = _currentItems();
    final subtotalCents = items.fold<int>(0, (sum, item) => sum + item.totalCents);
    final discountCents = tryParseCentsFromText(_discountController.text) ?? 0;
    final totalCents = (subtotalCents - discountCents).clamp(0, 1 << 62);
    final busy = _saving || _generatingPdf;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        toolbarHeight: 64,
        title: Text(_editingAditivo ? 'Aditivo de orçamento' : (_isEditing ? 'Editar orçamento' : 'Novo orçamento')),
        titleTextStyle: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(22),
          child: Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 7),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _isEditing
                    ? 'Atualize os dados e os itens do orçamento'
                    : 'Preencha os dados e adicione os itens do orçamento',
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _isReadOnlyStatus && !_editingAditivo
                ? _buildReadOnlySummary(widget.budget!)
                : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_editingAditivo) ...[
                    _buildAditivoBanner(),
                    const SizedBox(height: 12),
                  ],
                  if (_isClientRequest && !_editingAditivo) ...[
                    _buildPendingBanner(widget.budget!),
                    const SizedBox(height: 12),
                  ],
                  _SectionCard(
                    child: Column(
                      children: [
                        FutureBuilder<List<Customer>>(
                          future: _customersFuture,
                          builder: (context, snapshot) {
                            final customers = snapshot.data ?? [];
                            final hasSelected = _selectedCustomerId == null ||
                                customers.any((c) => c.id == _selectedCustomerId);

                            return _BudgetField(
                              icon: Icons.person_outline_rounded,
                              label: 'Cliente',
                              helperText: 'Não achou o cliente? Cadastre primeiro na aba Clientes.',
                              child: DropdownButtonFormField<String>(
                                initialValue: hasSelected ? _selectedCustomerId : null,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  hintText: 'Selecione o cliente',
                                ),
                                items: customers
                                    .map(
                                      (c) => DropdownMenuItem<String>(
                                        value: c.id,
                                        child: Text(
                                          c.name,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (value) =>
                                    setState(() => _selectedCustomerId = value),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                        _BudgetField(
                          icon: Icons.location_on_outlined,
                          label: 'Endereço (opcional, aparece no PDF)',
                          child: TextField(
                            controller: _addressController,
                            decoration: const InputDecoration(
                              hintText: 'Digite o endereço',
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _BudgetField(
                          icon: Icons.calendar_month_outlined,
                          label: _editingAditivo ? 'Data do aditivo' : 'Data',
                          child: TextField(
                            controller: _activeDateController,
                            keyboardType: TextInputType.datetime,
                            inputFormatters: [_dateMask],
                            decoration: InputDecoration(
                              suffixIcon: IconButton(
                                tooltip: 'Escolher no calendário',
                                icon: const Icon(
                                  Icons.edit_calendar_outlined,
                                  size: 18,
                                ),
                                onPressed: _pickActiveDate,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  const Text(
                    'Itens',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (var i = 0; i < _itemRows.length; i++) _buildItemRow(i),
                  _DottedActionButton(
                    onTap: _addItemRow,
                    label: 'Adicionar item',
                  ),
                  const SizedBox(height: 14),

                  _SectionCard(
                    child: Column(
                      children: [
                        _BudgetField(
                          icon: Icons.percent_rounded,
                          label: 'Desconto (opcional, em R\$)',
                          child: TextField(
                            controller: _discountController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              hintText: '0,00',
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _BudgetField(
                          icon: Icons.notes_outlined,
                          label: 'Observações (opcional)',
                          child: TextField(
                            controller: _observationsController,
                            maxLines: 3,
                            decoration: const InputDecoration(
                              hintText:
                                  'Adicione observações sobre o orçamento',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.10),
                      ),
                    ),
                    child: Column(
                      children: [
                        _totalsRow('Subtotal', formatCentsBRL(subtotalCents)),
                        if (discountCents > 0) ...[
                          const SizedBox(height: 4),
                          _totalsRow(
                            'Desconto',
                            formatCentsBRL(discountCents),
                          ),
                        ],
                        const Divider(height: 18),
                        _totalsRow(
                          'Total',
                          formatCentsBRL(totalCents.toInt()),
                          bold: true,
                        ),
                      ],
                    ),
                  ),

                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          SafeArea(
            top: false,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border(
                  top: BorderSide(
                    color: AppColors.muted.withValues(alpha: 0.10),
                  ),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: _buildActions(busy),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Botões do rodapé — variam conforme o status do orçamento (ver
  /// `BudgetStatus`). Um orçamento manual (`_status == null`) ou ainda
  /// pendente de envio usa o formulário completo de itens/preço (mesmos
  /// botões de sempre, + as ações específicas do pedido). A partir de
  /// `enviado` a tela vira um resumo (`_buildReadOnlySummary`) e os
  /// botões mudam de acordo com o que falta fazer.
  List<Widget> _buildActions(bool busy) {
    final status = _status;

    if (status == null || status == BudgetStatus.pendente || _editingAditivo) {
      return [
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton.icon(
            onPressed: busy ? null : _save,
            icon: _saving
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Icon(
                    _editingAditivo
                        ? Icons.difference_outlined
                        : (status == BudgetStatus.pendente ? Icons.send_outlined : Icons.save_outlined),
                    size: 18,
                  ),
            label: Text(
              _editingAditivo
                  ? 'Registrar aditivo e enviar pro cliente'
                  : (status == BudgetStatus.pendente
                      ? 'Enviar orçamento pro cliente'
                      : (_isEditing ? 'Salvar alterações' : 'Salvar orçamento')),
            ),
          ),
        ),
        TextButton.icon(
          onPressed: busy ? null : _generatePdf,
          icon: _generatingPdf
              ? const SizedBox(
                  height: 15,
                  width: 15,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(
                  Icons.picture_as_pdf_outlined,
                  size: 17,
                ),
          label: const Text('Gerar e compartilhar PDF'),
        ),
        if (_editingAditivo)
          TextButton.icon(
            onPressed: busy ? null : _cancelAditivo,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.danger,
              minimumSize: const Size(0, 30),
            ),
            icon: const Icon(Icons.close, size: 16),
            label: const Text('Cancelar aditivo'),
          )
        else if (status == BudgetStatus.pendente)
          TextButton.icon(
            onPressed: busy ? null : _rejectAsProvider,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.danger,
              minimumSize: const Size(0, 30),
            ),
            icon: const Icon(Icons.block_outlined, size: 16),
            label: const Text('Recusar pedido'),
          )
        else
          TextButton.icon(
            onPressed: busy ? null : () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.danger,
              minimumSize: const Size(0, 30),
            ),
            icon: const Icon(Icons.close, size: 16),
            label: const Text('Cancelar'),
          ),
      ];
    }

    if (status == BudgetStatus.enviado || status == BudgetStatus.aditivoEnviado) {
      return [
        SizedBox(
          width: double.infinity,
          height: 44,
          child: OutlinedButton.icon(
            onPressed: busy ? null : _rejectAsProvider,
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
            icon: busy
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.block_outlined, size: 17),
            label: const Text('Cancelar orçamento'),
          ),
        ),
        _registrarAditivoButton(busy),
        TextButton(
          onPressed: busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Fechar'),
        ),
      ];
    }

    if (status == BudgetStatus.aprovado) {
      return [
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton.icon(
            onPressed: busy ? null : _acceptFinal,
            icon: _saving
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.event_available_outlined, size: 18),
            label: const Text('Confirmar e agendar na agenda'),
          ),
        ),
        _registrarAditivoButton(busy),
        TextButton.icon(
          onPressed: busy ? null : _rejectAsProvider,
          style: TextButton.styleFrom(
            foregroundColor: AppColors.danger,
            minimumSize: const Size(0, 30),
          ),
          icon: const Icon(Icons.block_outlined, size: 16),
          label: const Text('Recusar mesmo assim'),
        ),
      ];
    }

    // aceito / recusado — estado final, só fechar (mais "Registrar
    // aditivo" logo acima, pra quem ainda pode registrar um — ver
    // `_registrarAditivoButton`).
    return [
      _registrarAditivoButton(busy),
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Fechar'),
      ),
    ];
  }

  /// Botão "Registrar aditivo" do rodapé fixo — pedido do Franck: ficar
  /// logo ACIMA do botão "Fechar" (antes vivia lá em cima, dentro do
  /// resumo somente-leitura que rola — ver `_buildReadOnlySummary`).
  /// Devolve um widget vazio (sem altura) em vez de `null` pra caber
  /// direto na lista de `children` de `_buildActions` sem precisar de um
  /// `if`/spread em cada branch.
  Widget _registrarAditivoButton(bool busy) {
    final status = _status;
    // Só faz sentido pra quem já viu o orçamento — não em `recusado`
    // (fluxo encerrado, sem mais volta).
    if (status == null || status == BudgetStatus.recusado) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: busy ? null : _startAditivo,
        icon: const Icon(Icons.difference_outlined, size: 16),
        label: const Text('Registrar aditivo (revisar itens/valor)'),
        style: TextButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: const Size(0, 32),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }

  Widget _totalsRow(String label, String value, {bool bold = false}) {
    final style = TextStyle(
      fontSize: bold ? 18 : 14,
      fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
      color: bold ? AppColors.primary : AppColors.ink,
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: style),
        Text(value, style: style),
      ],
    );
  }

  Color _statusColor(BudgetStatus status) => switch (status) {
        BudgetStatus.pendente => AppColors.primary,
        BudgetStatus.enviado => Colors.orange,
        BudgetStatus.aprovado => Colors.blue,
        BudgetStatus.aceito => Colors.green,
        BudgetStatus.aditivoEnviado => Colors.deepPurple,
        BudgetStatus.recusado => AppColors.danger,
      };

  Widget _statusChip(BudgetStatus status) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.label,
        style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12),
      ),
    );
  }

  /// Banner mostrado no topo do formulário completo (itens editáveis)
  /// quando o orçamento ainda está `pendente` — resume o pedido que o
  /// cliente mandou pelo marketplace, já que esses dados (categoria,
  /// descrição, data preferida) não têm campo próprio no formulário.
  Widget _buildPendingBanner(Budget budget) {
    final category = budget.category != null ? serviceCategoryFromWire(budget.category!) : null;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.mark_email_unread_outlined, size: 16, color: AppColors.primary),
              const SizedBox(width: 6),
              Text(
                category != null ? 'Pedido de orçamento — ${category.label}' : 'Pedido de orçamento',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.ink),
              ),
              const Spacer(),
              if (_linkingCustomer)
                const SizedBox(
                  height: 14,
                  width: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          if ((budget.requestDescription ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(budget.requestDescription!, style: const TextStyle(fontSize: 13, color: AppColors.ink)),
          ],
          if ((budget.preferredDate ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Data preferida do cliente: ${budget.preferredDate}',
                style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          ],
        ],
      ),
    );
  }

  /// Banner mostrado no topo do formulário completo enquanto
  /// `_editingAditivo` está ativo (ver `_startAditivo`) — deixa claro que
  /// isso não é a edição livre de um rascunho, é uma revisão formal de
  /// algo que o cliente já viu.
  Widget _buildAditivoBanner() {
    final nextNumber = (widget.budget?.revisionNumber ?? 0) + 1;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.difference_outlined, size: 18, color: Colors.orange),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Registrando o aditivo nº $nextNumber deste orçamento. Ajuste itens/valor e a '
              'data do aditivo abaixo — o cliente vai ver o valor atualizado.',
              style: const TextStyle(fontSize: 12.5, color: AppColors.ink),
            ),
          ),
        ],
      ),
    );
  }

  /// Resumo (sem edição de itens/preço) mostrado a partir do status
  /// `enviado` em diante — o orçamento já foi mandado pro cliente, então
  /// o formulário completo de itens deixa de fazer sentido; o que muda
  /// daqui pra frente é só o status e (em `aprovado`) o horário do
  /// serviço pro aceite final.
  Widget _buildReadOnlySummary(Budget budget) {
    final status = budget.status!;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _statusChip(status),
              if (budget.revisionNumber > 0) ...[
                const SizedBox(width: 8),
                AditivoBadge(number: budget.revisionNumber),
              ],
            ],
          ),
          const SizedBox(height: 12),
          if (status == BudgetStatus.recusado) ...[
            Text(_rejectedByLabel(budget.rejectedBy),
                style: const TextStyle(fontSize: 13, color: AppColors.ink)),
            const SizedBox(height: 12),
          ],
          if (status == BudgetStatus.enviado) ...[
            const Text('Aguardando o cliente aprovar ou recusar.',
                style: TextStyle(fontSize: 13, color: AppColors.ink)),
            const SizedBox(height: 12),
          ],
          if (status == BudgetStatus.aditivoEnviado) ...[
            const Text('Aguardando o cliente aprovar ou recusar o aditivo.',
                style: TextStyle(fontSize: 13, color: AppColors.ink)),
            const SizedBox(height: 12),
          ],
          if (status == BudgetStatus.aceito && budget.serviceScheduledAt != null) ...[
            Text(
              'Serviço agendado para ${formatDateDdMmYyyy(budget.serviceScheduledAt!)} às '
              '${TimeOfDay.fromDateTime(budget.serviceScheduledAt!).format(context)}.',
              style: const TextStyle(fontSize: 13, color: AppColors.ink),
            ),
            const SizedBox(height: 12),
          ],
          _SectionCard(
            child: Column(
              children: [
                _BudgetField(
                  icon: Icons.person_outline_rounded,
                  label: 'Cliente',
                  child: Text(budget.customerName, style: const TextStyle(fontSize: 14)),
                ),
                if ((budget.addressText ?? '').isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _BudgetField(
                    icon: Icons.location_on_outlined,
                    label: 'Endereço',
                    child: Text(budget.addressText!, style: const TextStyle(fontSize: 14)),
                  ),
                ],
                if (status == BudgetStatus.aprovado) ...[
                  const SizedBox(height: 12),
                  _BudgetField(
                    icon: Icons.calendar_month_outlined,
                    label: 'Data do serviço',
                    child: TextField(
                      controller: _dateController,
                      keyboardType: TextInputType.datetime,
                      inputFormatters: [_dateMask],
                      decoration: InputDecoration(
                        suffixIcon: IconButton(
                          tooltip: 'Escolher no calendário',
                          icon: const Icon(Icons.edit_calendar_outlined, size: 18),
                          onPressed: _pickDate,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _BudgetField(
                    icon: Icons.access_time_rounded,
                    label: 'Horário do serviço',
                    helperText: 'Verificamos conflito de horário na agenda ao confirmar.',
                    child: OutlinedButton(
                      onPressed: _pickServiceTime,
                      child: Text(_serviceTime.format(context)),
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 12),
                  _BudgetField(
                    icon: Icons.calendar_month_outlined,
                    label: 'Data',
                    child: Text(formatDateDdMmYyyy(budget.date), style: const TextStyle(fontSize: 14)),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          const Text('Itens', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.ink)),
          const SizedBox(height: 8),
          for (final item in budget.items)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.muted.withValues(alpha: 0.10)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(item.description,
                                  style: const TextStyle(fontWeight: FontWeight.w600)),
                            ),
                            if (item.aditivoNumber != null) ...[
                              const SizedBox(width: 8),
                              AditivoBadge(number: item.aditivoNumber!, compact: true),
                            ],
                          ],
                        ),
                        Text(item.quantityLabel,
                            style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                      ],
                    ),
                  ),
                  Text(formatCentsBRL(item.totalCents),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.10)),
            ),
            child: Column(
              children: [
                _totalsRow('Subtotal', formatCentsBRL(budget.subtotalCents)),
                if (budget.discountCents > 0) ...[
                  const SizedBox(height: 4),
                  _totalsRow('Desconto', formatCentsBRL(budget.discountCents)),
                ],
                const Divider(height: 18),
                _totalsRow('Total', formatCentsBRL(budget.totalCents), bold: true),
              ],
            ),
          ),
          if ((budget.observations ?? '').isNotEmpty) ...[
            const SizedBox(height: 14),
            _SectionCard(
              child: _BudgetField(
                icon: Icons.notes_outlined,
                label: 'Observações',
                child: Text(budget.observations!, style: const TextStyle(fontSize: 14)),
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }
}


class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.muted.withValues(alpha: 0.10),
        ),
      ),
      child: child,
    );
  }
}

class _BudgetField extends StatelessWidget {
  const _BudgetField({
    required this.icon,
    required this.label,
    required this.child,
    this.helperText,
  });

  final IconData icon;
  final String label;
  final Widget child;
  final String? helperText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: AppColors.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: AppColors.ink,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        child,
        if (helperText != null) ...[
          const SizedBox(height: 5),
          Text(
            helperText!,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 10,
            ),
          ),
        ],
      ],
    );
  }
}

class _CompactMiniField extends StatelessWidget {
  const _CompactMiniField({
    required this.label,
    required this.child,
  });

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            color: AppColors.muted,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 5),
        child,
      ],
    );
  }
}

/// Botão "Adicionar item" com borda pontilhada, igual ao mockup. O
/// Flutter não tem uma borda tracejada pronta sem depender de outro
/// pacote só pra isso — em vez de adicionar uma dependência nova pra um
/// detalhe puramente decorativo, a borda vira uma linha tracejada
/// desenhada à mão com CustomPainter (mais barato que trazer um pacote
/// inteiro pra um traço).
class _DottedActionButton extends StatelessWidget {
  const _DottedActionButton({required this.onTap, required this.label});

  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: CustomPaint(
        painter: _DashedBorderPainter(color: AppColors.primary, radius: 14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 11),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.add, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius));
    final path = Path()..addRRect(rrect);
    const dashWidth = 6.0;
    const dashSpace = 4.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + dashWidth;
        canvas.drawPath(metric.extractPath(distance, next.clamp(0, metric.length)), paint);
        distance = next + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}
